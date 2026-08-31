// Reads Google's popular-times widget off a rendered search results page.
//
// Google's class names are obfuscated and change often, so this anchors on
// the things that are structural rather than cosmetic:
//
//   - the widget is `div[data-attrid="kc:/local:busyness"]`
//   - each hour is a `[data-hour]` column; the current hour is the one with
//     `aria-checked="true"`
//   - bars are leaf elements with an inline `height:<px>`, and every observed
//     height is 0.75px per percent
//   - the current hour's column holds two bars in DOM order: usual, then live
//   - the status line is the widget's `aria-live` region, reading either
//     "Live: A little busy" or, with no live data, "Usually a little busy"
//
// Returns a JSON string, because that is what evaluateJavaScript can hand
// back across the bridge without ceremony.
(function () {
  function toInt(value) {
    var n = parseInt(value, 10);
    return isNaN(n) ? null : n;
  }

  function percentFromHeight(element) {
    var match = /([\d.]+)px/.exec(element.style.height || "");
    if (!match) return null;
    var percent = Math.round(parseFloat(match[1]) / 0.75);
    return Math.max(0, Math.min(100, percent));
  }

  var out = {
    found: false,
    hasConsentForm: document.querySelector('form[action*="consent"]') !== null,
    name: null,
    statusText: null,
    isLive: false,
    livePercent: null,
    usualPercent: null,
    currentHour: null,
    day: null,
    hours: [],
  };

  var title = document.querySelector('[data-attrid="title"]');
  if (title) out.name = title.textContent.trim() || null;

  var root = document.querySelector('div[data-attrid="kc:/local:busyness"]');
  if (!root) return JSON.stringify(out);
  out.found = true;

  var day = root.querySelector('[data-day][aria-checked="true"]');
  if (day) out.day = toInt(day.getAttribute("data-day"));

  var status = root.querySelector("[aria-live]");
  if (status) {
    var text = status.textContent.replace(/\s+/g, " ").trim();
    var live = /^Live:\s*(.*)$/i.exec(text);
    if (live) {
      out.isLive = true;
      out.statusText = live[1].trim() || null;
    } else if (text) {
      out.statusText = text;
    }
  }

  var columns = root.querySelectorAll("[data-hour]");
  for (var i = 0; i < columns.length; i++) {
    var column = columns[i];
    var hour = toInt(column.getAttribute("data-hour"));
    if (hour === null) continue;

    var bars = [];
    var candidates = column.querySelectorAll('[style*="height"]');
    for (var c = 0; c < candidates.length; c++) {
      var percent = percentFromHeight(candidates[c]);
      if (percent !== null) bars.push(percent);
    }
    if (bars.length === 0) continue;

    out.hours.push({ hour: hour, percent: bars[0] });
    if (column.getAttribute("aria-checked") === "true") {
      out.currentHour = hour;
      out.usualPercent = bars[0];
      if (bars.length > 1) out.livePercent = bars[1];
    }
  }

  return JSON.stringify(out);
})();
