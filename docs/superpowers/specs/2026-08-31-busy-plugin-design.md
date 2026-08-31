# Busy plugin — design

**Date:** 2026-08-31
**Status:** approved, implemented in the same session

How busy a place is right now, in the menu bar. The user types a place the
way they would search for it on Google ("lion gym kesavadasapuram"); Perch
shows Google's live busyness for it, today's popular-times histogram, and
keeps it fresh in the background. The motivating case is picking a gym time.

## Where the data comes from

Google's Places API does not expose popular times or live busyness. What does
expose it is the knowledge panel on an ordinary Google Search results page:
a `div[data-attrid="kc:/local:busyness"]` holding day tabs, one bar per open
hour, and a text line reading either `Live: A little busy` (live data
present) or `Usually not too busy` (no live data).

Verified against the real page on 2026-08-31:

- The bars are leaf `div`s with an inline `height:<px>`; every observed
  height divides cleanly by 0.75, so `percent = height / 0.75`.
- The current hour's column holds **two** bars in DOM order: the usual bar
  first, the live bar second. Every other column holds one.
- Hour labels are `aria-label="4 am"`…`"9 pm"` elements in the widget, one per
  column, in document order.
- The selected day tab is `[role="radio"][aria-checked="true"]` with a
  `data-day` of 1 (Monday) to 7 (Sunday); Google preselects today.
- Plain `curl` gets a JavaScript-only shell — the page must be rendered.

So this plugin scrapes a rendered page through a hidden `WKWebView`, exactly
as Market does with Facebook, and accepts the same maintenance cost for the
same reasons (see `2026-08-08-market-scraping-design.md`). It never signs in
to anything; there is no session to keep.

The extractor anchors on the things above — the `data-attrid`, inline
heights, ARIA labels, DOM order — and never on Google's obfuscated class
names or computed colours, because neither survives a fixture and neither
survives a redesign.

## Components

```
Plugins/BusyPlugin/Sources/BusyPlugin/
  Busy.swift                       the PerchPlugin; owns the refresh loop
  Models/
    Place.swift                    one saved place: id, query, createdAt
    Busyness.swift                 one fetched result, plus BusyLevel
    BusySettings.swift             refresh interval
  Session/
    GoogleSession.swift            owns the WKWebView; loads a URL, runs the script
    GoogleBusynessSource.swift     the BusynessSource conformance
    BusynessSource.swift           the seam: fetch(query:) -> ScrapedBusyness
    ExtractedBusyness.swift        script loading and JSON decoding
    Resources/busyness.js          the DOM extraction
  Store/
    BusyStore.swift                places, results, settings; refresh()
    BusyDocument.swift             the one persisted file
  Views/
    BusyPanelView.swift            add field + a card per place
    PlaceCardView.swift            status line, histogram, checked-ago
    HistogramView.swift            today's hours, current hour highlighted
    BusySettingsView.swift         the interval stepper
```

## Data

`Place` — `id: UUID`, `query: String`, `createdAt: Date`. The query is sent
to Google verbatim; the panel shows the name Google returns once it has one.

`Busyness` — what the last successful fetch found:

- `name: String?` — the knowledge-panel title
- `statusText: String?` — Google's own words, without the `Live:` prefix
- `isLive: Bool` — whether `statusText` came from a `Live:` line
- `livePercent: Int?`, `usualPercent: Int?` — the current hour's two bars
- `currentHour: Int?` — the hour those bars sit in (place-local)
- `hours: [HourBusyness]` — `(hour, percent)` for the selected day
- `fetchedAt: Date`

`BusyLevel` is a pure mapping from the status text (falling back to the live
percent) to `.quiet` / `.moderate` / `.busy`, which the views turn into
green / yellow / red. Google's phrasings observed: "Not busy", "Not too busy",
"A little busy", "Busy", "Very busy", "As busy as it gets".

`BusyDocument` — `places`, `results: [UUID: Busyness]`, `settings`. One
file, `busy.json`, debounced writes, flushed on quit.

## Fetching

`BusynessSource.fetch(query:)` throws `BusyError`:

- `.notFound` — the page rendered but had no busyness widget. Google does
  not have popular times for this place, or the query matched nothing.
  Reported per place, not retried harder.
- `.consentWall` — Google redirected to its cookie-consent page. Nothing in
  the plugin can click through it; the panel says so.
- `.failed(String)` — navigation failed or timed out. Worth retrying.

`BusyStore.refresh()` walks the places **serially** (one webview) and records
a result or a failure per place; a failure keeps the previous result on
screen, dimmed, with the message underneath. `refreshIfStale(maxAge:)` runs
when the panel opens; `Busy.setEnabled(true)` starts a loop that refreshes
every `settings.refreshIntervalMinutes` (default 10, floor 5) and
`setEnabled(false)` stops it — the same shape as Analytics.

## Panel

Top: a text field, "Add a place, as you'd search it on Google". Below: a card
per place —

- name, with a hover-gated delete
- a coloured dot and the status: `A little busy · 78% now, usually 61%`, or
  `Usually 61% at this hour` when there is no live figure, or the failure
- today's histogram, one bar per hour, current hour drawn in the level colour
  with the live bar over the usual one
- `checked 3m ago`

Menu bar label: the icon, plus the first place's live percent when there is
one. Footer: Refresh. Settings: the interval.

## Testing

- Package (`swift test --package-path Plugins/BusyPlugin`): decoding the
  script payload, `BusyLevel`, the search URL, store persistence, and
  `refresh()` against a fake source — failures recorded, results kept, a
  place deleted mid-fetch not resurrected.
- Host (`xcodebuild test`): `busyness.js` against
  `PerchTests/Plugins/Busy/Fixtures/busyness-live.html`, a saved copy of the
  real widget, plus a page with no widget and a consent page.

## Out of scope

Notifications ("the gym just got quiet"), multiple days, wait-time and
typical-visit-length lines, and a Maps deep link. All cheap to add once the
extraction has proven itself on real pages for a while.
