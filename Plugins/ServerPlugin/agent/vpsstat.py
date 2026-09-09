#!/usr/bin/env python3
"""vpsstat - a tiny, dependency-free host health daemon.

Reads /proc and /sys directly (no psutil, no pip), stores a rolling history in
SQLite, and serves a JSON API plus a static dashboard on 127.0.0.1:9110.

Design notes:
  - Fast tick (10s): cheap counter reads from /proc. Rates are computed from
    deltas between consecutive ticks.
  - Slow tick (60s): things that cost real work - walking /proc for per-process
    stats, reading container cgroups, and outbound HTTP health checks.
  - Raw samples are kept for 24h, 5-minute rollups for 30d, and per-day traffic
    totals forever (365 rows a year is nothing).
"""

import json
import os
import re
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("VPSSTAT_DB", "/var/lib/vpsstat/stats.db")
WEB_DIR = os.environ.get("VPSSTAT_WEB", "/usr/local/share/vpsstat")
BIND_HOST = os.environ.get("VPSSTAT_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("VPSSTAT_PORT", "9110"))
NET_IFACE = os.environ.get("VPSSTAT_IFACE", "eth0")
DISK_DEV = os.environ.get("VPSSTAT_DISK", "vda")
FS_MOUNT = "/"

FAST_INTERVAL = 10
SLOW_EVERY = 6           # slow tick runs every 6 fast ticks = 60s
RAW_RETENTION = 24 * 3600
ROLLUP_RETENTION = 30 * 86400
ROLLUP_BUCKET = 300      # 5 minutes
SECTOR = 512
PAGE = os.sysconf("SC_PAGE_SIZE")
HZ = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1

def _parse_health_targets(raw):
    """`name=url,name=url` -> [(name, url)]. Empty string means check nothing.

    Configuration rather than a constant so the agent carries no site-specific
    hostnames: the same file runs on any machine, and what it watches is set in
    the unit file beside it.
    """
    targets = []
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        name, sep, url = item.partition("=")
        if sep:
            targets.append((name.strip(), url.strip()))
        else:
            # A bare URL is allowed; it names itself.
            targets.append((item, item))
    return targets


HEALTH_TARGETS = _parse_health_targets(os.environ.get("VPSSTAT_HEALTH", ""))

# systemd units to report. Same reasoning as the health targets.
UNITS = [u.strip() for u in os.environ.get(
    "VPSSTAT_UNITS", "vpsstat").split(",") if u.strip()]

# Columns stored per sample. Kept in one list so the schema, the INSERT and the
# rollup aggregation can never drift apart.
RATE_COLS = [
    "cpu_user", "cpu_sys", "cpu_iowait", "cpu_steal", "cpu_idle",
    "load1", "load5", "load15",
    "mem_total", "mem_used", "mem_avail", "mem_cache",
    "swap_total", "swap_used", "swap_in", "swap_out",
    "net_rx_bps", "net_tx_bps", "disk_read_bps", "disk_write_bps",
    "fs_total", "fs_used", "procs", "procs_running", "procs_blocked", "zombies",
]
SUM_COLS = ["net_rx_bytes", "net_tx_bytes", "disk_read_bytes", "disk_write_bytes"]
ALL_COLS = RATE_COLS + SUM_COLS


def _read(path):
    with open(path, "r") as fh:
        return fh.read()


def _read_int(path, default=0):
    try:
        return int(_read(path).strip())
    except (OSError, ValueError):
        return default


# --------------------------------------------------------------------------
# Raw /proc readers. Each returns absolute counters; rates come from deltas.
# --------------------------------------------------------------------------

def read_cpu():
    line = _read("/proc/stat").split("\n", 1)[0]
    parts = [int(x) for x in line.split()[1:]]
    parts += [0] * (10 - len(parts))
    user, nice, system, idle, iowait, irq, softirq, steal = parts[:8]
    return {
        "user": user + nice,
        "sys": system + irq + softirq,
        "idle": idle,
        "iowait": iowait,
        "steal": steal,
        "total": user + nice + system + idle + iowait + irq + softirq + steal,
    }


def read_meminfo():
    out = {}
    for line in _read("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        out[key] = int(rest.split()[0]) * 1024   # kB -> bytes
    total = out.get("MemTotal", 0)
    avail = out.get("MemAvailable", 0)
    cache = out.get("Cached", 0) + out.get("Buffers", 0) + out.get("SReclaimable", 0)
    swap_total = out.get("SwapTotal", 0)
    swap_used = swap_total - out.get("SwapFree", 0)
    return {
        "mem_total": total,
        "mem_avail": avail,
        "mem_used": total - avail,
        "mem_cache": cache,
        "swap_total": swap_total,
        "swap_used": swap_used,
    }


def read_vmstat_swap():
    swin = swout = 0
    for line in _read("/proc/vmstat").splitlines():
        if line.startswith("pswpin "):
            swin = int(line.split()[1])
        elif line.startswith("pswpout "):
            swout = int(line.split()[1])
    return swin * PAGE, swout * PAGE


def read_net(iface):
    for line in _read("/proc/net/dev").splitlines():
        name, _, rest = line.partition(":")
        if name.strip() != iface:
            continue
        f = rest.split()
        return {
            "rx": int(f[0]), "tx": int(f[8]),
            "rx_drop": int(f[3]), "tx_drop": int(f[11]),
            "rx_err": int(f[2]), "tx_err": int(f[10]),
        }
    return {"rx": 0, "tx": 0, "rx_drop": 0, "tx_drop": 0, "rx_err": 0, "tx_err": 0}


def read_disk(dev):
    for line in _read("/proc/diskstats").splitlines():
        f = line.split()
        if len(f) > 9 and f[2] == dev:
            return {"read": int(f[5]) * SECTOR, "write": int(f[9]) * SECTOR}
    return {"read": 0, "write": 0}


def read_loadavg():
    f = _read("/proc/loadavg").split()
    running, _, total = f[3].partition("/")
    return {
        "load1": float(f[0]), "load5": float(f[1]), "load15": float(f[2]),
        "procs_running": int(running), "procs": int(total),
    }


def read_blocked():
    m = re.search(r"^procs_blocked (\d+)", _read("/proc/stat"), re.M)
    return int(m.group(1)) if m else 0


def read_fs(mount):
    """Report the same numbers df does.

    df counts the root-reserved blocks as neither used nor available, so its
    percentage is used/(used+avail), not used/total. Matching that convention
    means the dashboard and `df -h` never disagree."""
    st = os.statvfs(mount)
    used = (st.f_blocks - st.f_bfree) * st.f_frsize
    avail = st.f_bavail * st.f_frsize
    return {"fs_total": used + avail, "fs_used": used}


def read_uptime():
    return float(_read("/proc/uptime").split()[0])


# --------------------------------------------------------------------------
# Slow-tick collectors
# --------------------------------------------------------------------------

def scan_processes(prev, now_ts):
    """Walk /proc once. Returns (top_cpu, top_mem, zombie_count, new_prev)."""
    cur, rows, zombies = {}, [], 0
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            stat = _read("/proc/%s/stat" % pid)
            # comm can contain spaces and parens, so split on the LAST ')'.
            head, _, tail = stat.rpartition(")")
            comm = head[head.index("(") + 1:]
            f = tail.split()
            state = f[0]
            if state == "Z":
                zombies += 1
                continue
            jiffies = int(f[11]) + int(f[12])          # utime + stime
            rss = int(f[21]) * PAGE
        except (OSError, ValueError, IndexError):
            continue
        cur[pid] = jiffies
        pct = 0.0
        if pid in prev and now_ts > prev.get("_ts", now_ts):
            dt = now_ts - prev["_ts"]
            pct = (jiffies - prev[pid]) / HZ / dt * 100.0
        rows.append({"pid": int(pid), "name": comm, "cpu": round(max(pct, 0.0), 1), "rss": rss})
    cur["_ts"] = now_ts
    top_cpu = sorted(rows, key=lambda r: -r["cpu"])[:8]
    top_mem = sorted(rows, key=lambda r: -r["rss"])[:8]
    return top_cpu, top_mem, zombies, cur


CGROUP_ROOT = "/sys/fs/cgroup/system.slice"


def docker_names():
    """id -> name. Shelling out to docker is the only way to get names, but it
    only happens on the slow tick and the result is reused for the cgroup reads."""
    try:
        out = subprocess.run(
            ["docker", "ps", "--no-trunc", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}"],
            capture_output=True, text=True, timeout=15, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    m = {}
    for line in out.strip().splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            m[parts[0]] = (parts[1], parts[2])
    return m


def scan_containers(prev, now_ts):
    """Per-container CPU% and RAM read straight from cgroup v2 files."""
    names = docker_names()
    cur, rows = {}, []
    for cid, (name, status) in names.items():
        base = os.path.join(CGROUP_ROOT, "docker-%s.scope" % cid)
        if not os.path.isdir(base):
            continue
        usec = 0
        try:
            for line in _read(os.path.join(base, "cpu.stat")).splitlines():
                if line.startswith("usage_usec "):
                    usec = int(line.split()[1])
                    break
        except OSError:
            continue
        mem = _read_int(os.path.join(base, "memory.current"))
        # docker stats reports memory.current minus inactive_file; use the same
        # definition so the two never disagree.
        cache = 0
        try:
            for line in _read(os.path.join(base, "memory.stat")).splitlines():
                if line.startswith("inactive_file "):
                    cache = int(line.split()[1])
                    break
        except OSError:
            pass
        cur[cid] = usec
        pct = 0.0
        if cid in prev and now_ts > prev.get("_ts", now_ts):
            dt = now_ts - prev["_ts"]
            pct = (usec - prev[cid]) / 1e6 / dt * 100.0
        rows.append({
            "name": name, "status": status,
            "cpu": round(max(pct, 0.0), 1),
            "mem": max(mem - cache, 0), "mem_total": mem,
        })
    cur["_ts"] = now_ts
    rows.sort(key=lambda r: -r["cpu"])
    return rows, cur


_SSL_CTX = ssl.create_default_context()


def check_health():
    out = []
    for name, url in HEALTH_TARGETS:
        t0 = time.time()
        code, ok, err = None, False, None
        try:
            req = urllib.request.Request(url, method="GET",
                                         headers={"User-Agent": "vpsstat/1.0"})
            with urllib.request.urlopen(req, timeout=8, context=_SSL_CTX) as r:
                code = r.status
                r.read(1)
            ok = True
        except urllib.error.HTTPError as e:
            # An HTTP error still proves the service answered.
            code, ok = e.code, True
        except Exception as e:                       # noqa: BLE001 - report anything
            err = type(e).__name__
        out.append({
            "name": name, "url": url, "code": code, "ok": ok,
            "ms": int((time.time() - t0) * 1000), "error": err,
        })
    return out


def systemd_units():
    units = UNITS
    out = []
    if not units:
        return out
    try:
        res = subprocess.run(["systemctl", "is-active"] + units,
                             capture_output=True, text=True, timeout=10)
        states = res.stdout.strip().splitlines()
    except (OSError, subprocess.SubprocessError):
        states = []
    for i, u in enumerate(units):
        state = states[i] if i < len(states) else "unknown"
        out.append({"name": u, "state": state, "ok": state == "active"})
    return out


# --------------------------------------------------------------------------
# Storage
# --------------------------------------------------------------------------

def connect():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    return db


def init_db(db):
    cols = ", ".join("%s REAL" % c for c in ALL_COLS)
    db.execute("CREATE TABLE IF NOT EXISTS samples (ts INTEGER PRIMARY KEY, %s)" % cols)
    db.execute("CREATE TABLE IF NOT EXISTS rollups (ts INTEGER PRIMARY KEY, %s)" % cols)
    db.execute("""CREATE TABLE IF NOT EXISTS traffic_daily (
                    day TEXT PRIMARY KEY, rx INTEGER NOT NULL, tx INTEGER NOT NULL)""")
    db.execute("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)")
    db.commit()


def insert_sample(db, ts, row):
    cols = ",".join(ALL_COLS)
    ph = ",".join("?" * len(ALL_COLS))
    db.execute("INSERT OR REPLACE INTO samples (ts,%s) VALUES (?,%s)" % (cols, ph),
               [ts] + [row.get(c, 0) for c in ALL_COLS])


def bump_traffic(db, rx, tx):
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    db.execute("""INSERT INTO traffic_daily (day, rx, tx) VALUES (?,?,?)
                  ON CONFLICT(day) DO UPDATE SET rx=rx+excluded.rx, tx=tx+excluded.tx""",
               (day, int(rx), int(tx)))


def rollup_and_prune(db):
    """Fold raw samples older than the raw window into 5-minute buckets."""
    cutoff = int(time.time()) - RAW_RETENTION
    avg = ", ".join("AVG(%s)" % c for c in RATE_COLS)
    tot = ", ".join("SUM(%s)" % c for c in SUM_COLS)
    cols = ",".join(ALL_COLS)
    db.execute("""INSERT OR REPLACE INTO rollups (ts,%s)
                  SELECT (ts/%d)*%d, %s, %s FROM samples WHERE ts < ?
                  GROUP BY ts/%d""" % (cols, ROLLUP_BUCKET, ROLLUP_BUCKET, avg, tot,
                                       ROLLUP_BUCKET), (cutoff,))
    db.execute("DELETE FROM samples WHERE ts < ?", (cutoff,))
    db.execute("DELETE FROM rollups WHERE ts < ?", (int(time.time()) - ROLLUP_RETENTION,))
    db.commit()


# --------------------------------------------------------------------------
# Sampler
# --------------------------------------------------------------------------

LATEST = {"ready": False}
LATEST_LOCK = threading.Lock()


def sampler():
    db = connect()
    init_db(db)
    prev = None
    proc_prev, cont_prev = {}, {}
    slow = {"containers": [], "top_cpu": [], "top_mem": [], "health": [],
            "units": [], "zombies": 0}
    tick = 0
    last_rollup = 0.0

    # Prime the per-process and per-container CPU counters before the first
    # real tick. Without this the first minute after a restart reports 0% for
    # everything, because a CPU percentage needs two samples to exist.
    try:
        _, _, _, proc_prev = scan_processes({}, time.time())
        _, cont_prev = scan_containers({}, time.time())
        time.sleep(3)
    except Exception as e:                           # noqa: BLE001
        sys.stderr.write("prime error: %r\n" % (e,))

    while True:
        t0 = time.time()
        try:
            now = time.time()
            cur = {
                "ts": now,
                "cpu": read_cpu(),
                "net": read_net(NET_IFACE),
                "disk": read_disk(DISK_DEV),
                "swap": read_vmstat_swap(),
            }
            mem = read_meminfo()
            load = read_loadavg()
            fs = read_fs(FS_MOUNT)

            row = {}
            row.update(mem)
            row.update(load)
            row.update(fs)
            row["procs_blocked"] = read_blocked()

            if prev is not None:
                dt = cur["ts"] - prev["ts"]
                dtot = cur["cpu"]["total"] - prev["cpu"]["total"]
                if dt > 0 and dtot > 0:
                    for k in ("user", "sys", "idle", "iowait", "steal"):
                        row["cpu_" + k] = round(
                            (cur["cpu"][k] - prev["cpu"][k]) / dtot * 100.0, 2)
                    # Counters can go backwards on reboot; clamp to zero.
                    d_rx = max(cur["net"]["rx"] - prev["net"]["rx"], 0)
                    d_tx = max(cur["net"]["tx"] - prev["net"]["tx"], 0)
                    d_rd = max(cur["disk"]["read"] - prev["disk"]["read"], 0)
                    d_wr = max(cur["disk"]["write"] - prev["disk"]["write"], 0)
                    d_si = max(cur["swap"][0] - prev["swap"][0], 0)
                    d_so = max(cur["swap"][1] - prev["swap"][1], 0)
                    row["net_rx_bps"] = d_rx / dt
                    row["net_tx_bps"] = d_tx / dt
                    row["net_rx_bytes"] = d_rx
                    row["net_tx_bytes"] = d_tx
                    row["disk_read_bps"] = d_rd / dt
                    row["disk_write_bps"] = d_wr / dt
                    row["disk_read_bytes"] = d_rd
                    row["disk_write_bytes"] = d_wr
                    row["swap_in"] = d_si / dt
                    row["swap_out"] = d_so / dt
                    bump_traffic(db, d_rx, d_tx)

            if tick % SLOW_EVERY == 0:
                tc, tm, zz, proc_prev = scan_processes(proc_prev, now)
                conts, cont_prev = scan_containers(cont_prev, now)
                slow = {
                    "containers": conts, "top_cpu": tc, "top_mem": tm,
                    "health": check_health(), "units": systemd_units(), "zombies": zz,
                }
            row["zombies"] = slow["zombies"]

            if prev is not None:
                insert_sample(db, int(now), row)
                db.commit()

            with LATEST_LOCK:
                LATEST.clear()
                LATEST.update(row)
                LATEST.update(slow)
                LATEST["ts"] = now
                LATEST["uptime"] = read_uptime()
                LATEST["ncpu"] = NCPU
                LATEST["host"] = socket.gethostname()
                LATEST["net_drop"] = cur["net"]["rx_drop"] + cur["net"]["tx_drop"]
                LATEST["net_err"] = cur["net"]["rx_err"] + cur["net"]["tx_err"]
                LATEST["traffic"] = traffic_totals(db)
                LATEST["ready"] = prev is not None
                LATEST["self_rss"] = int(_read("/proc/self/statm").split()[1]) * PAGE

            prev = cur
            tick += 1
            if time.time() - last_rollup > 900:
                rollup_and_prune(db)
                last_rollup = time.time()
        except Exception as e:                       # noqa: BLE001 - never die
            sys.stderr.write("sampler error: %r\n" % (e,))
        time.sleep(max(FAST_INTERVAL - (time.time() - t0), 1))


def traffic_totals(db):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    month = today[:7]
    r = db.execute("SELECT rx,tx FROM traffic_daily WHERE day=?", (today,)).fetchone()
    m = db.execute("SELECT SUM(rx) rx, SUM(tx) tx FROM traffic_daily WHERE day LIKE ?",
                   (month + "%",)).fetchone()
    days = db.execute("""SELECT day, rx, tx FROM traffic_daily
                         ORDER BY day DESC LIMIT 30""").fetchall()
    # Totals accumulate from vpsstat's own deltas, so they start at first run,
    # not at boot. Report that date so the numbers can't be misread.
    since = db.execute("SELECT MIN(day) d FROM traffic_daily").fetchone()
    return {
        "today": {"rx": (r["rx"] if r else 0) or 0, "tx": (r["tx"] if r else 0) or 0},
        "month": {"rx": (m["rx"] if m else 0) or 0, "tx": (m["tx"] if m else 0) or 0},
        "since": since["d"] if since else None,
        "days": [{"day": d["day"], "rx": d["rx"], "tx": d["tx"]} for d in reversed(days)],
    }


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

RANGES = {"1h": (3600, "samples"), "6h": (6 * 3600, "samples"),
          "24h": (24 * 3600, "samples"), "7d": (7 * 86400, "rollups"),
          "30d": (30 * 86400, "rollups")}


class Handler(BaseHTTPRequestHandler):
    server_version = "vpsstat"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass                                          # keep the journal quiet

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if path in ("/", "/index.html"):
            return self._file("dashboard.html", "text/html; charset=utf-8")
        if path == "/api/now":
            with LATEST_LOCK:
                return self._send(200, json.dumps(LATEST))
        if path == "/api/history":
            return self._history(query)
        if path == "/healthz":
            return self._send(200, "ok", "text/plain")
        return self._send(404, json.dumps({"error": "not found"}))

    def _file(self, name, ctype):
        p = os.path.join(WEB_DIR, name)
        try:
            with open(p, "rb") as fh:
                return self._send(200, fh.read(), ctype)
        except OSError:
            return self._send(404, "missing %s" % name, "text/plain")

    def _history(self, query):
        params = dict(kv.split("=", 1) for kv in query.split("&") if "=" in kv)
        rng = params.get("range", "1h")
        if rng not in RANGES:
            return self._send(400, json.dumps({"error": "bad range"}))
        window, table = RANGES[rng]
        since = int(time.time()) - window
        db = connect()
        try:
            cols = ",".join(ALL_COLS)
            rows = db.execute(
                "SELECT ts,%s FROM %s WHERE ts>=? ORDER BY ts" % (cols, table),
                (since,)).fetchall()
        finally:
            db.close()
        return self._send(200, json.dumps({
            "range": rng, "table": table,
            "cols": ["ts"] + ALL_COLS,
            "rows": [[r[c] for c in (["ts"] + ALL_COLS)] for r in rows],
        }))


def main():
    threading.Thread(target=sampler, daemon=True).start()
    srv = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    srv.daemon_threads = True
    srv.serve_forever()


if __name__ == "__main__":
    main()
