# MenuDo

Your current task, always visible in the macOS menu bar. Click to manage a
simple todo list: add, complete, reorder, done-section, settings, global
hotkey, launch at login.

- macOS 14+, SwiftUI `MenuBarExtra`, sandboxed, no network.
- Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  `xcodegen generate`, then open `MenuDo.xcodeproj`.
- Tests: `xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS'`

## App Store submission checklist (manual)

1. Replace the placeholder icon in
   `MenuDo/Resources/Assets.xcassets/AppIcon.appiconset` with final art.
2. Confirm the app name (check App Store availability; rename = edit
   `project.yml` + `CFBundleDisplayName`, regenerate).
3. In `project.yml`, set `DEVELOPMENT_TEAM: <TEAMID>` and remove
   `CODE_SIGN_IDENTITY: "-"`; run `xcodegen generate`.
4. In App Store Connect: create the app record with bundle ID
   `org.ahlab.MenuDo`.
5. Xcode → Product → Archive → Distribute App → App Store Connect.
6. Privacy: "Data Not Collected" (the app has no network access and collects
   nothing). Encryption: exempt (`ITSAppUsesNonExemptEncryption` is false).
7. Screenshots: dropdown open with a few tasks (light + dark), Settings
   window. 1280×800 or larger.
8. Re-verify launch-at-login with the properly signed build.
