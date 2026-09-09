# vpsstat

The agent the Server plugin talks to. One machine runs one of these; Perch
polls its `/api/now`.

It is a single Python file with no dependencies — no pip, no `psutil`. It reads
`/proc` and cgroup v2 directly, keeps a rolling history in SQLite, and serves a
JSON API plus a small dashboard on `127.0.0.1:9110`.

Measured cost on a 1 vCPU / 2 GB box: about 26 MB RSS and well under 1% of a
core. The unit file caps it at 64 MB and de-prioritises its CPU and I/O, so the
monitor can never become the problem it is meant to diagnose.

## Install

Needs Python 3.9+ and systemd. Nothing else.

```bash
scp vpsstat.py root@your-box:/usr/local/bin/vpsstat.py
scp dashboard.html root@your-box:/usr/local/share/vpsstat/dashboard.html
scp vpsstat.service root@your-box:/etc/systemd/system/vpsstat.service
ssh root@your-box '
  mkdir -p /usr/local/share/vpsstat /var/lib/vpsstat
  chmod 755 /usr/local/bin/vpsstat.py
  systemctl daemon-reload && systemctl enable --now vpsstat'
```

Check it: `curl -s http://127.0.0.1:9110/api/now`.

## Exposing it to Perch

The agent binds to localhost only and has no authentication of its own. Put a
reverse proxy in front of it for TLS and a password. With Caddy that is four
lines:

```
status.example.com {
	encode gzip
	basicauth {
		you $2a$14$...        # caddy hash-password --plaintext 'your-password'
	}
	reverse_proxy 127.0.0.1:9110
}
```

Then give Perch `https://status.example.com` with that username and password.
Perch stores the password in your login Keychain.

## Configuration

All optional, set as `Environment=` lines in the unit file.

| Variable | Default | What it does |
|---|---|---|
| `VPSSTAT_HEALTH` | *(empty)* | `name=url,name=url` to HTTP-check each cycle. Any HTTP reply counts as up; only a timeout or refused connection is down. |
| `VPSSTAT_UNITS` | `vpsstat` | Comma-separated systemd units to report. |
| `VPSSTAT_PORT` | `9110` | Listen port. |
| `VPSSTAT_HOST` | `127.0.0.1` | Listen address. Leave it on localhost and use a proxy. |
| `VPSSTAT_IFACE` | `eth0` | Network interface to measure. |
| `VPSSTAT_DISK` | `vda` | Block device to measure. |
| `VPSSTAT_DB` | `/var/lib/vpsstat/stats.db` | History database. |

## What it measures

CPU split by user / system / iowait / **steal**, load against the core count,
memory and swap including swap-in and swap-out **rate**, network throughput and
per-day and per-month totals, disk usage and I/O, per-container CPU and memory
from cgroup v2, top processes, systemd unit states, and the HTTP checks above.

Two conventions are matched deliberately to the standard tools, so the numbers
never disagree with the box itself:

- **Filesystem usage follows `df`.** Root-reserved blocks are excluded from the
  denominator, so `used/(used+avail)`, not `used/total`.
- **Container memory follows `docker stats`.** `memory.current` minus
  `inactive_file`.

## History and retention

Raw samples every 10 s are kept for 24 hours, folded into 5-minute rollups kept
for 30 days, with per-day traffic totals kept indefinitely. Pruning runs every
15 minutes. Steady-state database size is about 10 MB.

Network totals accumulate from the agent's own deltas, so "today" and "this
month" run from when the agent started, not from boot. The dashboard says so.

## The dashboard

`dashboard.html` is served at `/` — the same data as the plugin but with the
full 24-hour and 30-day charts, drawn as inline SVG with no CDN and no
JavaScript libraries. Perch's ••• menu opens it.

## API

- `GET /api/now` — current snapshot. What Perch polls.
- `GET /api/history?range=1h|6h|24h|7d|30d` — columnar history.
- `GET /healthz` — liveness.
