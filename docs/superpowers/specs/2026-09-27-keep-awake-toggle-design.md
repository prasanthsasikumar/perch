# Keep-awake toggle — design

**Date:** 2026-09-27
**Status:** approved, implemented. Amended during implementation: see
"Who registers the helper".

A one-click replacement for typing `sudo pmset -a disablesleep 1` and
`sudo pmset -a disablesleep 0`. With it on, the Mac stays awake when the lid
is closed.

## Decisions already made

- **Privileges come from a bundled root helper**, not a password prompt and
  not a sudoers rule. One approval in System Settings, then every toggle is
  instant.
- **The control is a footer button**, host-owned, visible on every tab. It is
  not a plugin.
- **It is a plain toggle.** It behaves like the command: the setting stays
  until it is turned off, and outlives Perch and a restart. No timers, no
  battery threshold.

## Why a helper at all

`pmset -a disablesleep` needs root. Perch is sandboxed, and the sandbox blocks
both routes a non-sandboxed app would take: `sudo` (setuid binaries do not
run) and AppleScript's `with administrator privileges`.

## Who registers the helper

The design first had Perch register the helper itself. That cannot work: the
sandbox refuses, and says so in the system log as
`Sandbox: Perch deny(1) job-creation`. Found on 2026-09-27 on the first real
click.

So the helper belongs to a companion app, `PerchKeepAwake.app`, inside
Perch's bundle. It is not sandboxed. It registers the helper, opens Login
Items if approval is needed, explains itself in an alert in every other case,
and quits. It has no window and no Dock icon. It never quits without
sending the user somewhere, because Perch only runs it when something is
wrong.

Dropping Perch's sandbox instead was rejected: it would move every plugin's
stored data out of the container.

A consequence: Perch cannot ask whether the helper is registered, because
`SMAppService` answers for the calling app's own bundle. Perch learns it by
trying. A helper it cannot reach means "run the companion".

A power assertion (`IOPMAssertion`, what `caffeinate` uses) is not a
substitute. It prevents idle sleep; it does not prevent the sleep that
closing the lid causes. `disablesleep` is the setting that does.

## Pieces

| Piece | Where | Job |
|---|---|---|
| `PerchKeepAwake` | new app target `PerchKeepAwake/`, embedded in `Perch.app/Contents/Helpers` | registers the helper, then quits |
| `PerchHelper` | new command-line target `PerchHelper/`, embedded in the companion | root LaunchDaemon; runs `pmset` |
| `SleepHelperProtocol` | `Shared/SleepHelper.swift`, compiled into all three targets | the XPC interface |
| `SleepStateReader` | `Perch/Support/` | reads the current setting |
| `SleepController` | `Perch/Support/` | observable state; calls the helper, runs the companion when it cannot |
| footer button | `Perch/Host/PanelFooter.swift` | the control |

### The helper

Installed inside the companion, which registers it with
`SMAppService.daemon`:

```
Perch.app/Contents/Helpers/PerchKeepAwake.app/
  Contents/MacOS/PerchKeepAwake
  Contents/MacOS/PerchHelper
  Contents/Library/LaunchDaemons/org.ahlab.Perch.helper.plist
```

The launchd plist names the binary with `BundleProgram`, declares the mach
service `org.ahlab.Perch.helper`, and has no `KeepAlive` or `RunAtLoad`:
launchd starts the helper when Perch connects, and the helper exits after
being idle for ten seconds, never while a call is in flight. Nothing stays
resident.

### The XPC interface

```swift
@objc protocol SleepHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void)
}
```

`reply` carries `nil` on success and a message on failure. The helper turns
the boolean into `/usr/bin/pmset -a disablesleep 0` or `1`, with the path and
every argument fixed in the helper.

### Security

The helper is root, so:

- It takes a boolean. No string from the caller ever reaches a command line.
- It sets a code-signing requirement on its listener
  (`NSXPCListener.setConnectionCodeSigningRequirement`, macOS 13+) so only a
  caller with identifier `org.ahlab.Perch` signed by team `3U4384584Z` can
  connect. The requirement is on the team, not one certificate, so both the
  Development-signed Debug build and the Developer ID Release build pass.
- Perch sets the mirror-image requirement on its connection, so it will not
  talk to an impostor service.

### Reading the state

Perch does not store the setting. It reads it from the system, which is what
keeps the button truthful when the setting is changed from Terminal.

`SleepStateReader` reads `SleepDisabled` from the `IOPMrootDomain` registry
entry with IOKit; this needs no privileges. It is read at launch and every
time the panel opens.

### The controller

```swift
@MainActor @Observable
final class SleepController {
    enum Status { case ready, needsApproval, failed(String) }
    private(set) var isSleepDisabled: Bool
    private(set) var status: Status
    func refresh()
    func toggle() async
}
```

`toggle()`:

1. Call the helper.
2. If the helper cannot be reached, launch the companion and set
   `.needsApproval`. The next click, after approval, succeeds.
3. If the helper answers with an error, set `.failed` with its message.
4. Either way, `refresh()` from the system. The button shows what the system
   reports, not what was requested.

The helper client, the installer and the state reader are protocols injected into the
controller, so it can be tested without root or XPC.

### The button

Left of the gear. `cup.and.saucer` when sleep is normal,
`cup.and.saucer.fill` in the accent colour when it is disabled.

| State | Tooltip |
|---|---|
| off | Keep awake with lid closed |
| on | Staying awake with lid closed |
| needs approval | Click again. If nothing changes, allow Perch Keep Awake in System Settings → Login Items |
| failed | the helper's message |

## Changes outside new code

- **`project.yml`**: the `PerchHelper` and `PerchKeepAwake` targets (signed
  like Perch: Development in Debug; Developer ID, hardened runtime and
  `--timestamp` in Release). The companion embeds the helper and the launchd
  plist; Perch embeds the companion. The helper is signed with an explicit
  `--identifier`, because a command-line tool is otherwise signed under its
  product name and both ends of the connection check the identifier.
- **`Perch.entitlements`**:
  `com.apple.security.temporary-exception.mach-lookup.global-name` listing
  `org.ahlab.Perch.helper`, so the sandboxed app can reach the helper. This
  is acceptable for Developer ID distribution and would not pass App Store
  review; Perch does not ship there.
- **Release process**: unchanged in its steps. The helper is a nested binary
  of the app, so the existing notarize-and-staple covers it. After release,
  `codesign -dv --verbose=4` on the helper should show the Developer ID,
  hardened runtime and a secure timestamp.
- **README**: a short section on the toggle and its one-time approval.

## Error handling

| Situation | Behaviour |
|---|---|
| helper not registered, or not yet approved | companion runs; `.needsApproval`; button unchanged |
| user later removes approval | next toggle lands in `.needsApproval` again |
| helper switched off in Login Items | registering is refused; the companion says so and offers to open Login Items |
| helper caught exiting from idle | the call is tried once more; launchd starts a fresh helper |
| allowed, but still unreachable after the second try | the companion says so and offers to open Login Items. It never unregisters to repair: macOS then marks the helper disabled |
| `pmset` exits non-zero | helper replies with its stderr; `.failed` |

An updated Perch needs no re-registration. The launchd job names the helper
by its path inside the bundle, and the helper exits when idle, so the next
connection after an update starts the new binary.

## Testing

Unit tests, with a fake helper client and a fake reader:

- toggle on and off updates `isSleepDisabled` from the reader, not the request
- helper failure leaves the state as the system reports it and sets `.failed`
- an unreachable helper runs the companion once and sets `.needsApproval`
- a helper that answers with an error does not run the companion
- the click after approval succeeds
- `refresh()` picks up a change made outside Perch
- the helper builds exactly `["-a", "disablesleep", "1"]` and `"0"`

Manual, on a signed build, because root and XPC cannot run under XCTest:

- first click asks for approval; after approval the toggle works
- `pmset -g | grep SleepDisabled` matches the button in both directions
- changing it from Terminal is reflected when the panel reopens
- with it on, closing the lid on battery keeps an SSH session alive
- an unsigned test client is refused by the helper

## Order of work, and the risks it retires

1. The shared contract and the `pmset` command, with tests.
2. The helper target, embedded and signed.
3. Reader, helper client and controller, with tests.
4. Footer button.
5. **Proof on a real build.** The button is the harness, which is why it
   comes first. Two risks are retired here:
   - *Sandbox to daemon XPC.* If the mach-lookup exception is not enough,
     the fallback is an app-group-prefixed service name.
   - *Reading state from inside the sandbox.* If the sandbox blocks the
     IOKit read, the helper gains `getSleepDisabled(reply:)`.
6. README.

## Out of scope

Auto-off timers, battery thresholds, a menu bar indicator, a keyboard
shortcut, and a Settings pane entry.
