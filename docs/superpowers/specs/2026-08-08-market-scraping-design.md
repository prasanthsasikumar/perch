# Market scraping — design (Plan 2)

**Date:** 2026-08-08
**Status:** approved, not yet implemented

Make the Market tab actually find listings. Plan 1 built the store, the
scheduling, the panel, and a `ListingSource` seam filled with a stub that
returns nothing. This replaces the stub with a real one backed by `WKWebView`,
and adds the sign-in flow that makes it possible.

Parent spec: `2026-08-08-market-plugin-design.md`. That document covers both
plans; this one records the Plan 2 decisions and the detail the parent left
open.

## What Plan 1 left in place

- `ListingSource` — `search(query:maxPrice:location:radiusKm:) async throws -> [ScrapedListing]`,
  `@MainActor`, with `SearchError.signedOut` and `SearchError.failed(String)`.
- `WatchPoller` — serial, 600s floor, ±20% jitter, backoff to 7200s, treats
  `signedOut` as a human problem rather than a flaky scrape.
- `MarketStore`, the new-vs-seen diff, the panel, the settings pane.
- `Market.setEnabled(_:)` — the poller only runs while the plugin is enabled.

Nothing above the seam changes. This plan writes what sits below it.

## Components

```
Plugins/MarketPlugin/Sources/MarketPlugin/
  Session/
    FacebookSession.swift        owns the WKWebView and the shared cookie store
    LoginSignals.swift           pure: is this page a login wall?
    FacebookListingSource.swift  the ListingSource conformance
    Resources/extract.js         the DOM extraction
  Views/
    SignInWindow.swift           an NSWindow hosting the same webview
```

`StubListingSource` is deleted; `Market.init(context:)` constructs a
`FacebookListingSource`. `Market.init(context:source:)` stays, so tests keep
injecting a fake.

## Extraction: scrape the DOM

`extract.js` selects `a[href*="/marketplace/item/"]`, takes the listing id from
the href, and pulls title, price, and location from each anchor's text.

**The decision, and its cost.** The alternative was intercepting the GraphQL
JSON that populates the results — better data, notably real numeric prices, and
more stable against cosmetic redesigns. It was rejected for v1 on two grounds:
it is roughly double the work for something that has never yet fetched a single
real listing, and reading an undocumented internal endpoint sits less
comfortably against Facebook's terms than reading the page a browser has
already rendered.

The cost is that Facebook's class names are obfuscated and churn, so this will
break periodically. Three things make that survivable:

- `extract.js` is a bundled resource, not a Swift string literal. A selector
  fix is a one-file change that does not touch compiled code.
- Fixture tests fail loudly when the parser stops matching the markup it was
  written against.
- The "all watches empty, repeatedly" banner (below) surfaces breakage in the
  UI rather than as silence.

If the DOM approach proves too fragile in daily use, the GraphQL interceptor is
the upgrade path and the `ListingSource` seam means it changes nothing above it.

`ScrapedListing` gains `priceValue: Int?` beside the existing display `price`.
A display string cannot be sorted or thresholded, and adding the field later —
once a Swift menu-bar client reads the shape — is far more awkward than adding
it now.

## The session

One `WKWebView`, owned by `FacebookSession`, on `WKWebsiteDataStore.default()`.
One webview is also what makes the poller's serial guarantee structural rather
than a matter of discipline.

**Cookies persist across launches.** This is the single biggest gain over the
superseded Python sidecar, which signed in once per *run* and could not do
better without forking its upstream dependency. Here the user signs in once,
ever, until Facebook expires the session.

**The webview lives in an offscreen window while polling.** A `WKWebView` that
is not in a window may not lay out or run scripts reliably; parking it offscreen
is the standard way to keep it live without showing it.

**A search is:** build the URL, load it, await `didFinish`, run the login probe,
then run `extract.js` and decode the JSON.

**Navigation has a timeout.** A `WKWebView` load can hang indefinitely — no
delegate callback ever arrives. The session races the load against a deadline
and throws `SearchError.failed` on expiry, so a hung page backs that watch off
instead of wedging the poller forever.

## Login detection

After each load the session gathers a `LoginSignals` value — the current URL's
path, and whether the DOM contains the markers of a Facebook login screen. A
pure function decides from that whether this is a login wall, and the session
throws `SearchError.signedOut` when it is.

**It never infers "logged out" from an empty result set.** That inference is
what made `needs_login` unreachable in the Python implementation: upstream
returned an empty list for both "no matches" and "session dead", so a dead
session was indistinguishable from a quiet search and the sign-in prompt could
never fire. Detection here is positive or it is nothing.

The signals are gathered in `FacebookSession` and judged in `LoginSignals`,
split precisely so the judgement is testable without a browser.

## Sign-in

`SignInWindow` is an `NSWindow` hosting the *same* webview the scraper uses —
not a second one, or the cookies would land in the wrong place.

The user signs in at their own pace. Nothing times them out and nothing tears
the window down underneath them; the Python version gave them 60 seconds and
then closed the window mid-2FA, which is the failure this design exists to
avoid.

Perch is `LSUIElement`, so showing the window activates the app explicitly and
closing it returns focus without leaving a dock icon.

The panel's yellow "Sign in to Facebook" row opens this window. When the session
is valid again the poller resumes on its own.

## Failure states

Plan 1's table, plus the row it dropped:

| State | Panel shows |
|---|---|
| Not signed in | Yellow "Sign in to Facebook", opens the sign-in window |
| No location set | Add field disabled: "Set a location in Settings first" |
| Navigation failed or timed out | Row keeps its last results, "retrying in 40m" |
| One watch matching nothing | "nothing yet, since Aug 2" |
| **All watches matching nothing, repeatedly** | "Facebook may have changed — check your sign-in" |

The last row was promised by the parent spec and silently dropped from Plan 1,
where it would have fired constantly because the stub always returned nothing.
With a real source it earns its place: it is the one signal that distinguishes
"nothing matched" from "the parser stopped working" or "the session died
quietly".

Concretely: `WatchPoller` keeps a counter of consecutive ticks in which every
watch it polled returned zero listings — *zero listings scraped*, not zero
listings that were new. A tick that polls nothing (all watches paused, or none
due) leaves the counter untouched rather than resetting it. Any watch returning
at least one listing resets it to zero. At **three** the poller reports the
condition, which the panel renders as the row above.

Three rather than one because a genuinely quiet set of searches is common and a
single empty round means nothing; three rounds is roughly forty-five minutes at
the default interval, which is late enough to be sure and early enough to be
useful. The counter lives on the poller, not the store — it describes the health
of scraping, not anything worth persisting across launches.

## Carried-forward fixes

Two items the Plan 1 reviews deferred with "must fix before a real source goes
behind the seam". A real source is now going behind the seam.

- **A reentrancy guard on `WatchPoller.tick()`.** Sign-in, a manual action, and
  the background loop can now overlap; `tick()` was written assuming it never
  runs concurrently with itself.
- **The navigation timeout** described above.

The stale-`Watch`-snapshot hazard was already fixed during Plan 1's final wave.

## Testing

**`extract.js` against saved HTML fixtures**, loaded with `loadHTMLString` into
a real `WKWebView` in `PerchTests` — offline, no login, no network. This is the
coverage the Python design could not have at any price, and the check that would
have caught its worst bug.

**An honest limit.** A genuine Facebook fixture requires a logged-in session,
which belongs to the user, so the first fixtures are hand-built from the
structure Facebook currently uses. They prove the parser's logic; they do not
prove it matches today's Facebook. Closing that gap needs one artefact from the
user: a saved Marketplace search-results page, after sign-in works. Until then
the live run is the only proof, and the plan must say so rather than implying
green tests mean a working scraper.

**`LoginSignals`** is a pure function over a small value and is tested directly,
including the negative case — a normal results page must not be read as a login
wall.

**URL building** is pure and tested: the city slug, the query encoding, the
price cap, the radius.

**`FacebookSession` itself** is thin by design — navigate, probe, evaluate — and
what remains after the pure parts are extracted is not unit-testable without a
browser. That is stated rather than papered over with a test that asserts
nothing.

## Out of scope

The full Market window — listing history, per-watch detail, the settings pane —
is Plan 3. This plan builds only the sign-in window.

Also out: notifications on new finds; AI scoring; marketplaces other than
Facebook; watching a single listing URL; per-watch location overrides.

## Known risks

- **Markup drift**, discussed above. The primary ongoing maintenance cost of
  choosing this project over a hosted API.
- **Facebook may treat automated navigation as abuse.** The polling policy —
  serial, ten-minute floor, jitter, backoff — exists for this reason, and is not
  a tuning preference.
- **Terms of service.** Automated scraping sits against Facebook's terms. This
  is a personal-use tool polling a handful of searches at a human cadence, which
  is worth knowing before it ships to anyone else.
