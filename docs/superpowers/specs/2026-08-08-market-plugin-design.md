# Market plugin — design

**Date:** 2026-08-08
**Status:** approved, not yet implemented

Watch a Facebook Marketplace search from the menu bar. Type a query and a price
cap into a third Perch tab; Perch keeps looking; new listings appear in the
panel, and in full in a Perch window one click away.

Everything runs inside Perch. Nothing to install, nothing to start, no terminal.

## Why this shape

This replaces an earlier design — a Python sidecar wrapping the
`ai-marketplace-monitor` library, talked to over `127.0.0.1`. That version was
built and reviewed (see `~/Documents/GitHub/marketwatch`) and it worked, but it
required the user to run `uv run marketwatch` in a terminal. Perch is
app-sandboxed and cannot spawn a Python interpreter, so the sidecar could only
ever be a second thing the user installs and starts.

Perch ships to people who download an app and expect it to work. That rules the
sidecar out no matter how good it is.

Rewriting the scraping in Swift costs us the upstream project that was
absorbing Facebook's markup changes. It buys three things that matter more:

1. **One artifact.** No Python runtime, no Chromium, no second install, no
   background daemon. Perch stays a few megabytes.
2. **The sandbox survives.** `WKWebView` needs only `com.apple.security.network.client`,
   which Perch already has for Analytics. Tasks and Analytics keep the security
   story the README promises.
3. **The session persists.** `WKWebsiteDataStore.default()` keeps Facebook
   cookies across launches, so the user signs in once, ever — in a window
   inside Perch. The sidecar signed in once per *run*, in a Chromium window it
   did not own, and could not do better without forking upstream.

## Components

```
Plugins/MarketPlugin/
  Sources/MarketPlugin/
    Market.swift              PerchPlugin conformance, refresh loop
    Models/
      Watch.swift             a query, a price cap, its schedule
      Listing.swift           one found listing
      SessionState.swift      signedIn | signedOut | unknown
    Store/
      MarketStore.swift       @Observable; watches, listings, settings
      NewListings.swift       the new-vs-seen diff, a free function
    Session/
      FacebookSession.swift   owns the WKWebView and the cookie store
      ListingScraper.swift    navigate → evaluate → [Listing]
      Resources/extract.js    the DOM extraction
    Poller/
      WatchPoller.swift       which watches are due, and when next
    Views/
      MarketPanelView.swift   the tab
      WatchRowView.swift
      MarketWindow.swift      full history, settings, sign-in
      MarketSettingsView.swift
```

Registered in `PerchApp.makePlugins()` and added to `project.yml` as a local
package, exactly as `TasksPlugin` and `AnalyticsPlugin` are.

Identifier `org.ahlab.perch.market`, display name **Market**, icon
`binoculars`, capabilities `.network` and `.notifications`.

## How scraping works

One `WKWebView`, owned by `FacebookSession`, on `WKWebsiteDataStore.default()`.
One webview means polling is serial by construction rather than by discipline.

A poll navigates to
`https://www.facebook.com/marketplace/<city>/search?query=<q>&maxPrice=<p>&radius=<km>`,
waits for `didFinish`, and calls `evaluateJavaScript` with `extract.js`, which
returns a JSON array. The webview is off-screen while polling; it is kept in an
offscreen window rather than detached, so layout and script execution actually
run.

`extract.js` selects `a[href*="/marketplace/item/"]` and pulls an id from the
href plus title, price, and location from the anchor's text. This is the
fragile part of the design and it is fragile in exactly the way the upstream
Python scraper was — the difference is that we now own it. Two things make that
bearable:

- `extract.js` is a bundled resource, not a Swift string literal. A selector
  fix is a one-file change and does not touch compiled code.
- The extraction is testable offline (see Testing), which the Python scraper
  never was.

## Login

**Detection is positive, not inferred.** After a load, the session checks the
webview's URL for a login path and asks the page whether a login form is
present. It never concludes "logged out" from an empty result set, and never
concludes "no matches" from a login wall.

This is worth stating plainly because the sidecar got it wrong: it inferred
login state from an exception the upstream library never raised, so the
`needs_login` state could not fire at all, and a dead session was
indistinguishable from a search that matched nothing.

**Signing in** brings the same webview on-screen in the Market window. The user
takes as long as they need — there is no timer, and nothing tears the window
down underneath them. Cookies land in the shared data store, so this happens
once rather than once per launch. When the session is valid again the poller
resumes on its own.

## Data model and storage

A single JSON document via `PluginStorage`, following Tasks rather than
introducing a database. The host already gives us atomic writes and a `.bak`
copy if the file ever fails to decode.

- `Watch` — `id, query, maxPrice, location, radiusKm, paused, createdAt,
  lastCheckedAt, consecutiveFailures, nextCheckAt`. Location and radius are
  stamped from settings at creation, not read live, so changing the default
  does not silently move existing watches.
- `Listing` — `id (Facebook listing id), watchId, title, price, location, url,
  imageURL, firstSeenAt, seen`
- `Settings` — `location, radiusKm, pollIntervalMinutes, notificationsEnabled`

Listings are capped at **200 per watch**, oldest dropped, so the document stays
modest — `PluginStorage`'s own docstring asks for that. At a 15-minute cadence
that is far more history than the panel or window ever shows, and it bounds the
file without a retention setting nobody would tune.

"Already fetched" and "the user has looked at it" stay distinct as a `seen`
flag on the listing.

**A location must be set before a watch can be created.** Facebook scopes
marketplace searches to a city; without one the search returns nothing while
raising nothing. The panel's add field is disabled until a location is set, and
says why. No default city ships: a wrong city fails as silently as no city.

## Polling policy

Unchanged from the sidecar design, and still not a tuning preference — this is
what keeps a residential IP from being rate-limited into uselessness.

- One webview, one watch at a time, strictly serial.
- 10-minute floor between checks of the same watch; 15-minute default interval;
  ±20% jitter so checks do not land on a fixed cadence.
- Consecutive failures back off exponentially, capped at 2 hours.
- The loop sleeps entirely when there are no watches.
- Jitter is clamped so it can never schedule *below* the floor.

The loop runs for as long as Perch does, whether or not the panel is open and
whether or not Market is the tab in front — a watcher that only watches while
you are looking at it is not a watcher. It is a `Task` loop holding a weak
reference, matching how Analytics refreshes.

## The panel

```
┌─ Tasks │ Analytics │ Market ─────────┐
│  ┌────────────────────────┬───────┐  │
│  │ GoPro Hero 12          │ $200  │  │  Return commits
│  └────────────────────────┴───────┘  │
│                                       │
│  GoPro Hero 12      ≤$200      ● 3    │  ● = unseen count
│    $180 · Auckland · 2h ago           │  click opens the listing
│    $195 · Hamilton · 5h ago           │
│    $150 · Manukau · yesterday         │
│                                       │
│  Ryobi 18V drill    ≤$80         —    │  collapsed once seen
│  checked 6 min ago                    │
│                                       │
│  Open Market           ⚙  ⏻          │
└───────────────────────────────────────┘
```

Menu bar label: `binoculars` plus the total unseen count, text `nil` when zero
— the icon is always contributed so the menu bar item keeps a stable shape,
matching Analytics.

## The window

Two modes, one window.

**Normal:** watches on the left, that watch's full listing history on the
right, plus settings (location, radius, poll interval, notifications) and a row
showing session state with a **Sign in to Facebook** button.

**Sign-in:** the webview fills the window. Returns to normal once the session
is valid.

Perch is `LSUIElement`, so showing the window activates the app explicitly;
closing it returns focus without leaving a dock icon behind.

## Failure states

Every one is visible. The plugin never presents itself as watching when it is
not.

| State | Panel shows |
|---|---|
| Not signed in | Yellow "Sign in to Facebook"; polling paused |
| No location set | Add field disabled: "Set a location in Settings first" |
| Navigation failed or timed out | Row keeps its last results, "retrying in 40m" |
| One watch matching nothing | "nothing yet, since Aug 2" |
| **All** watches matching nothing, repeatedly | "Facebook may have changed — check your sign-in" |

The last row exists because of what happened to the sidecar: a default install
could not find anything, and reported itself healthy while doing so. Silence is
not an acceptable output.

## Testing

Split by what each test needs. Pure logic — the diff, the poller's scheduling,
the store's persistence, `RelativeTime` — lives in `MarketPlugin`'s own test
target and runs with `swift test` in about a quarter of a second. Anything that
genuinely needs the app host, notably Plan 2's `WKWebView` fixture tests, goes
in `PerchTests` alongside the Tasks and Analytics tests, which run fine (164
tests, 3.5s, verified 2026-08-08).

This is a departure from Perch's one-target convention, taken for loop speed
rather than necessity.

- `NewListings` is a free function over two collections, tested directly. A
  listing must be reported exactly once — never missed, never announced twice.
- `WatchPoller`'s scheduling (floor, jitter bounds, backoff growth, cap,
  paused watches, per-watch isolation) with an injected clock. No `sleep`.
- `MarketStore` persistence round-trips through a temporary `PluginStorage`
  directory, including the unreadable-file path.
- `FacebookSession` sits behind a protocol; the poller's tests use a fake. No
  test reaches the network.
- **`extract.js` against saved HTML fixtures**, loaded with `loadHTMLString`
  into a real `WKWebView`, asserting the parsed listings. Offline, no login.
  This is the coverage the Python design could not have at any price, and it is
  the check that would have caught its worst bug.

## Known risks

- **Facebook markup drift.** We own it now. Mitigated by the fixture tests, the
  separately-shippable `extract.js`, and the "all watches empty" signal — not
  eliminated.
- **Notifications under an ad-hoc signature.** `.notifications` is a capability
  no Perch plugin currently uses, and Perch is ad-hoc signed rather than
  Developer ID signed. If `UNUserNotificationCenter` will not authorize, v1
  ships with the menu-bar badge alone and says so, rather than a notification
  that silently never fires.
- **PerchKit is 0.x and unstable**, by its own documentation. A third plugin
  may be what forces the API to change. Expected.
- **Terms of service.** Automated scraping sits against Facebook's terms. This
  is a personal-use tool polling a handful of searches at a human cadence, but
  it is worth knowing before it ships to anyone else.

## Out of scope for v1

AI scoring of listings; marketplaces other than Facebook; watching a single
listing URL for price drops; per-watch location overrides; multi-account;
syncing between machines.

## Not part of this work

Shipping to clients as "download and it works" also needs an Apple Developer ID
and notarization. Perch is ad-hoc signed today, so first launch requires
right-click → Open or clearing the quarantine attribute by hand. That is true
of Perch now, independent of this plugin, and it is a prerequisite for handing
the app to anyone non-technical.

## The superseded sidecar

`~/Documents/GitHub/marketwatch` holds the Python implementation: 26 commits,
195 passing tests, a full spec and plan. It is superseded, not deleted. Its
design document, its new-vs-seen diff, and its polling policy port directly and
are the reference for this plugin. Its branch merges to `main` and its README
gains a note saying what happened.
