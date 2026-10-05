// Reads a Planet Fitness club page (planetfitness.com/gyms/<club>) and
// reports it in the same shape as busyness.js, plus the headcount.
//
// Anchors on what the page exposes for accessibility rather than on its
// utility class names:
//   - the live meter: [role=group][aria-label="11 percent full"]
//   - Crowd History: the selected [role=tab] (id "Monday"…) and, in its
//     panel, <meter id="bar_0"…"bar_23" value="15.67">
//   - the headcount: the page's React Router data stream, where the club's
//     {current, max, percentage} object sits in a table of values that
//     refer to each other by index. Decoding it is the fragile part, so a
//     failure only drops the headcount, never the reading.
(function () {
  "use strict";

  var out = {
    found: false, hasConsentForm: false, name: null, statusText: null,
    isLive: false, livePercent: null, usualPercent: null, currentHour: null,
    day: null, hours: [], headcount: null, capacity: null
  };

  function toInt(text) {
    var n = parseInt(text, 10);
    return isNaN(n) ? null : n;
  }

  // "Gym in Philadelphia (Washington Ave), PA | 1936 Washington Ave… | Planet Fitness"
  var title = (document.title || "").split("|")[0].trim();
  var named = /^Gym in (.+?)(?:,\s*[A-Z]{2})?$/.exec(title);
  if (named) out.name = "Planet Fitness " + named[1];

  var meter = document.querySelector('[role="group"][aria-label$="percent full"]');
  if (meter) {
    var full = /(\d+)\s*percent full/i.exec(meter.getAttribute("aria-label") || "");
    if (full) {
      out.found = true;
      out.isLive = true;
      out.livePercent = toInt(full[1]);
    }
  }

  var days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  var selected = document.querySelector('[role="tab"][aria-selected="true"]');
  if (selected && days.indexOf(selected.id) >= 0) {
    out.day = days.indexOf(selected.id) + 1;
    var panel = document.getElementById("control-" + selected.id) || document;
    var bars = panel.querySelectorAll('meter[id^="bar_"]');
    for (var i = 0; i < bars.length; i++) {
      var hour = toInt(bars[i].id.slice(4));
      var value = parseFloat(bars[i].getAttribute("value"));
      if (hour === null || isNaN(value)) continue;
      out.hours.push({ hour: hour, percent: Math.round(value) });
    }
  }

  try {
    var values = [];
    var scripts = document.querySelectorAll("script");
    var chunk = /streamController\.enqueue\(("(?:[^"\\]|\\.)*")\)/g;
    for (var s = 0; s < scripts.length; s++) {
      var text = scripts[s].textContent || "";
      var match;
      chunk.lastIndex = 0;
      while ((match = chunk.exec(text))) {
        var lines = JSON.parse(match[1]).split("\n");
        for (var l = 0; l < lines.length; l++) {
          if (!lines[l]) continue;
          var promised = /^P\d+:([\s\S]*)$/.exec(lines[l]);
          var parsed = JSON.parse(promised ? promised[1] : lines[l]);
          values = values.concat(Array.isArray(parsed) ? parsed : [parsed]);
        }
      }
    }
    for (var v = 0; v < values.length; v++) {
      var item = values[v];
      if (!item || typeof item !== "object" || Array.isArray(item)) continue;
      var resolved = {};
      for (var key in item) {
        if (key.charAt(0) === "_") resolved[values[toInt(key.slice(1))]] = values[item[key]];
      }
      if (typeof resolved.current === "number" && typeof resolved.max === "number" && "percentage" in resolved) {
        out.headcount = resolved.current;
        out.capacity = resolved.max;
        break;
      }
    }
  } catch (e) {
    out.headcount = null;
    out.capacity = null;
  }

  return JSON.stringify(out);
})();
