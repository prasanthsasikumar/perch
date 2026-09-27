# Keep-awake toggle — design

**Date:** 2026-09-27
**Status:** awaiting review

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

A power assertion (`IOPMAssertion`, what `caffeinate` uses) is not a
substitute. It prevents idle sleep; it does not prevent the sleep that
closing the lid causes. `disablesleep` is the setting that does.

## Pieces

| Piece | Where | Job |
|---|---|---|
| `PerchHelper` | new command-line target `PerchHelper/`, embedded in `Perch.app` | root LaunchDaemon; runs `pmset` |
| `SleepHelperProtocol` | `Shared/SleepHelperProtocol.swift`, compiled into both targets | the XPC interface |
| `SleepStateReader` | `Perch/Support/` | reads the current setting |
| `SleepController` | `Perch/Support/` | observable state; registers and calls the helper |
| footer button | `Perch/Host/PanelFooter.swift` | the control |

### The helper

Installed inside the bundle, registered with `SMAppService.daemon`:

```
Perch.app/Contents/MacOS/PerchHelper
Perch.app/Contents/Library/LaunchDaemons/org.ahlab.Perch.helper.plist
```

The launchd plist names the binary with `BundleProgram`, declares the mach
service `org.ahlab.Perch.helper`, and has no `KeepAlive` or `RunAtLoad`:
launchd starts the helper when Perch connects, and the helper exits after
being idle for a few seconds. Nothing stays resident.

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

1. If the daemon is not registered, register it.
2. If it then needs approval, set `.needsApproval`, open System Settings to
   Login Items (`SMAppService.openSystemSettingsLoginItems()`), and stop.
3. Otherwise call the helper, then `refresh()` from the system. The button
   shows what the system reports, not what was requested.

The helper client and the state reader are protocols injected into the
controller, so it can be tested without root or XPC.

### The button

Left of the gear. `cup.and.saucer` when sleep is normal,
`cup.and.saucer.fill` in the accent colour when it is disabled.

| State | Tooltip |
|---|---|
| off | Keep awake with lid closed |
| on | Staying awake with lid closed |
| needs approval | Allow Perch in System Settings → Login Items |
| failed | the helper's message |

## Changes outside new code

- **`project.yml`**: the `PerchHelper` target (signed like Perch: Development
  in Debug; Developer ID, hardened runtime and `--timestamp` in Release), a
  dependency from Perch that embeds it in `Contents/MacOS`, and a copy-files
  phase for the launchd plist.
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
| user has not approved the helper | `.needsApproval`; Settings opens; button unchanged |
| user later removes approval | next toggle lands in `.needsApproval` again |
| connection interrupted or invalidated | `.failed`; state re-read from the system |
| `pmset` exits non-zero | helper replies with its stderr; `.failed` |
| helper from an older Perch still registered | unregister and re-register on a version mismatch at launch |

## Testing

Unit tests, with a fake helper client and a fake reader:

- toggle on and off updates `isSleepDisabled` from the reader, not the request
- helper failure leaves the state as the system reports it and sets `.failed`
- unregistered daemon that needs approval sets `.needsApproval` and makes no
  helper call
- `refresh()` picks up a change made outside Perch
- the helper builds exactly `["-a", "disablesleep", "1"]` and `"0"`

Manual, on a signed build, because root and XPC cannot run under XCTest:

- first click asks for approval; after approval the toggle works
- `pmset -g | grep SleepDisabled` matches the button in both directions
- changing it from Terminal is reflected when the panel reopens
- with it on, closing the lid on battery keeps an SSH session alive
- an unsigned test client is refused by the helper

## Order of work, and the risks it retires

1. **Helper, registration and a bare XPC round trip from the sandboxed app**,
   before any UI. This is the part most likely to need adjusting. If the
   mach-lookup exception is not enough, the fallback is an app-group-prefixed
   service name.
2. **State reading from inside the sandbox.** If the sandbox blocks the IOKit
   read, the helper gains `getSleepDisabled(reply:)` and the reader calls it.
3. Controller and its tests.
4. Footer button.
5. README, release, and the manual checks above.

## Out of scope

Auto-off timers, battery thresholds, a menu bar indicator, a keyboard
shortcut, and a Settings pane entry.
