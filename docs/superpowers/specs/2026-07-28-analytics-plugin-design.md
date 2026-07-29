# Analytics plugin

**Goal:** Bring the numbers from `google-analytics-summary/ga_summary.py` into
Perch as a plugin, so the stats are a menu bar click away instead of a terminal
command.

**Shape:** `Plugins/AnalyticsPlugin`, a local Swift package depending only on
`PerchKit`. Identifier `org.ahlab.perch.analytics`, display name **Analytics**,
icon `chart.line.uptrend.xyaxis`, capabilities `[.network, .credentials]`.

## Why native REST rather than the Google SDK

The official Swift path to GA4 is gRPC, which drags in a large dependency tree
for three read-only calls. The Data API and the Admin API both expose plain
JSON over HTTPS, and service-account auth is a signed JWT exchanged for a
bearer token — a few hundred lines with no dependency beyond `Foundation`,
`Security`, and `CryptoKit`. Shelling out to the Python script is not an option:
Perch is sandboxed and cannot run an interpreter outside its container.

## Layout

```
Plugins/AnalyticsPlugin/Sources/AnalyticsPlugin/
  Analytics.swift                 PerchPlugin conformance, refresh timer
  Models/
    AnalyticsProperty.swift       id + display name
    PropertyStats.swift           30d totals, both week totals, 7 daily points
    ServiceAccount.swift          client_email + private key, parsed from GA JSON
    AnalyticsError.swift          every failure the UI has to render
  Auth/
    DER.swift                     minimal DER reader; PKCS#8 -> PKCS#1 unwrap
    Keychain.swift                generic-password item under the plugin id
    GoogleTokenProvider.swift     RS256 assertion -> access token, cached
  API/
    HTTPTransport.swift           protocol + URLSession implementation
    GoogleAnalyticsAPI.swift      protocol the store talks to
    LiveGoogleAnalyticsAPI.swift  Data API + Admin API over the transport
    RunReportResponse.swift       runReport JSON -> PropertyStats
  Store/
    AnalyticsStore.swift          Observable state, refresh, cache, staleness
  Views/
    AnalyticsPanelView.swift      property cards + "updated N ago"
    PropertyCardView.swift        one property, expandable
    SparklineView.swift           7-day bars
    AnalyticsSettingsView.swift   key import, discovery, property list
  Support/
    Formatting.swift              fmt_num / pct_change parity
    DateWindows.swift             the week boundaries compare_periods uses
```

## Authentication

1. Settings offers a file picker for the service-account `.json`. `NSOpenPanel`
   is what grants a sandboxed app read access to a file outside its container,
   so the user picking the file *is* the permission grant.
2. `client_email` and `private_key` are parsed out and written to the login
   Keychain as one generic-password item, service `org.ahlab.perch.analytics`.
   The file itself is never copied; no bookmark is retained.
3. `GoogleTokenProvider` builds the assertion Google's service-account flow
   wants: header `{"alg":"RS256","typ":"JWT"}`, claims `iss` = client email,
   `scope` = `https://www.googleapis.com/auth/analytics.readonly` (which covers
   both the Data and Admin APIs, so discovery needs no second grant), `aud` =
   the token endpoint, `iat` = now, `exp` = now + 1h. Segments are base64url,
   signed with `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)`.
4. POST `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=…` to
   `https://oauth2.googleapis.com/token`. The access token is held in memory
   until 60s before expiry and never written to disk.

Google ships the private key as PKCS#8 (`BEGIN PRIVATE KEY`) and
`SecKeyCreateWithData` expects a bare PKCS#1 `RSAPrivateKey`, so the DER has to
be unwrapped: outer SEQUENCE, skip the version INTEGER, skip the
AlgorithmIdentifier SEQUENCE, take the contents of the OCTET STRING. This is
the one genuinely error-prone step and gets its own tests against a generated
key.

## Fetching

Per property, per refresh, three POSTs to
`https://analyticsdata.googleapis.com/v1beta/properties/{id}:runReport`:

| Call | Dimensions | Metrics | Range |
|---|---|---|---|
| 30-day totals | none | activeUsers, sessions, screenPageViews, bounceRate, averageSessionDuration | `30daysAgo`–`today` |
| Week comparison | none | activeUsers, sessions, screenPageViews | two ranges in one request |
| Daily | `date` | activeUsers, sessions | `7daysAgo`–`today` |

The week comparison sends both ranges in a single request rather than the two
the Python makes; GA returns one row per range, tagged with a synthetic
`dateRange` dimension. Today's active-user count for the menu bar is read off
the last daily row, so it costs no extra call.

Week boundaries match the script exactly: current is `today-7 … today`,
previous is `today-14 … today-8`, both in the local calendar.

Two properties every 30 minutes is roughly 290 requests a day against a 25,000
token/day quota.

## Discovery

`GET https://analyticsadmin.googleapis.com/v1beta/accountSummaries` returns
every property the service account can see. Settings presents them as a
checklist. A manual *Add property* row stays available, because a service
account granted access at the property level rather than the account level can
come back with nothing.

## State and caching

`AnalyticsStore` is `@Observable` and owns the property list, a stats
dictionary keyed by property id, a per-property error dictionary, and the last
refresh timestamp. All of it round-trips through `PluginStorage` as one
`analytics.json` document, so the panel opens on real numbers rather than a
spinner. A 30-minute timer refreshes in the background; opening the panel
refreshes if the cache is more than 60 seconds old. `flush()` writes
synchronously.

Errors are held per property, so one property returning 403 leaves the others
rendering normally.

## Errors, as the user sees them

| Condition | Panel |
|---|---|
| No key imported | "Connect Google Analytics" prompt pointing at Settings |
| 401 / `invalid_grant` | "Sign-in failed — re-import your key"; cached token dropped |
| 403 on a property | That card only: "No access — add `<client_email>` as a viewer in GA4 Admin", email copyable |
| Offline | Cached numbers stay, dimmed, with how old they are |
| Corrupt cache | `PluginStorage` keeps a `.bak` and throws; the store starts empty |

Nothing is a modal. A menu bar panel that throws up a dialog is a menu bar
panel that interrupts whatever the user was actually doing.

## Host changes

- `com.apple.security.network.client` added to `Perch.entitlements`. macOS
  entitlements are per-app, so this is the whole binary — which is exactly what
  `PluginCapability`'s documentation already says and what the Plugins settings
  pane already discloses.
- `AnalyticsPlugin` added to `project.yml` as a package and a dependency.
- One line in `PerchApp.makePlugins()`.
- The README's claim that every shipped plugin "touches the network never" is
  no longer true and is rewritten.

## Tests

All offline, behind the `GoogleAnalyticsAPI` and `HTTPTransport` seams.

- **Formatting** — `1234 → "1.2K"`, `1_500_000 → "1.5M"`, sub-thousand grouping,
  non-numeric passthrough; percent change signs, one decimal, and both
  zero-denominator cases the Python special-cases.
- **DateWindows** — boundaries computed against an injected `today`, so the
  tests do not drift.
- **RunReportResponse** — fixture decoding, metric lookup by header order, the
  two-date-range row mapping, and empty `rows` yielding zeros rather than a
  crash.
- **ServiceAccount / DER** — valid key JSON, missing fields, and a PKCS#8
  payload unwrapping to something `SecKeyCreateWithData` accepts.
- **GoogleTokenProvider** — assertion has three segments with the expected
  header and claims, `exp == iat + 3600`, and the token is reused before expiry
  and refetched after, against a stub transport.
- **AnalyticsStore** — staleness threshold, cache round-trip through a temp
  directory, per-property error isolation, and the primary property driving the
  menu bar label.

## Out of scope

Realtime API, custom date ranges, event and conversion breakdowns, more than
one service account, and a user-consent OAuth flow. The plugin reads five
metrics for a handful of properties; anything more belongs in the GA web UI.
