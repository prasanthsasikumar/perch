# MenuDo

Your current task, always visible in the macOS menu bar.

MenuDo keeps a single, simple todo list one click away. The task at the top of your list shows right in the menu bar, so what you should be doing next is always in front of you. Click it to add, complete, reorder, or delete tasks.

## Download

Grab the latest `MenuDo.zip` from the [Releases page](../../releases/latest), unzip it, and drag `MenuDo.app` into your Applications folder.

Requires macOS 14 (Sonoma) or later. Apple Silicon and Intel are both supported.

### First launch

This build is signed ad hoc rather than with a paid Apple Developer certificate, so macOS Gatekeeper will block it the first time. To open it:

1. Right click (or Control click) `MenuDo.app` and choose **Open**.
2. Click **Open** again in the dialog that appears.

You only need to do this once. If macOS still refuses, run this in Terminal and try again:

```bash
xattr -dr com.apple.quarantine /Applications/MenuDo.app
```

A properly signed and notarized App Store build is planned, which will remove this step entirely.

## Features

- **Current task in the menu bar.** The first unfinished task on your list is always visible. Complete it and the next one takes its place.
- **Quick add.** Open the dropdown, type, press Return.
- **Edit in place.** Double-click a task to fix its title. Return saves, Escape cancels.
- **Reorder by dragging.** Whatever you drag to the top becomes your current task.
- **Done section.** Completed tasks collapse out of the way instead of disappearing. Clear them when you want.
- **Global hotkey.** Set a shortcut in Settings to open the list and start typing from any app.
- **Launch at login.** Toggle it on in Settings and MenuDo is there every morning.
- **Adjustable display.** Show the task title or just the icon, and set how long a title can get before it truncates.

## Settings

Click the gear icon in the dropdown.

| Setting | What it does |
|---|---|
| Show current task in menu bar | Switches between the task title and an icon only menu bar item |
| Title length | How many characters of the title to show, from 10 to 60 |
| Launch at login | Starts MenuDo automatically when you log in |
| Open MenuDo | Records a global keyboard shortcut. None is set by default |

## Your data

Tasks are stored as plain JSON inside the app's own sandbox container, on your Mac only:

```
~/Library/Containers/org.ahlab.MenuDo/Data/Library/Application Support/MenuDo/tasks.json
```

MenuDo has no network access, no accounts, no analytics, and no telemetry. Nothing you type leaves your machine. If that file is ever unreadable, MenuDo keeps a `.bak` copy beside it and tells you, rather than silently starting empty.

## Building from source

MenuDo is a SwiftUI app built around `MenuBarExtra`. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so only `project.yml` is tracked in git.

```bash
brew install xcodegen
git clone https://github.com/prasanthsasikumar/menudo.git
cd menudo
xcodegen generate
open MenuDo.xcodeproj
```

Run the tests with:

```bash
xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS'
```

### Layout

```
MenuDo/
  MenuDoApp.swift        MenuBarExtra scene and the menu bar label
  Models/TodoItem.swift  The task model
  Store/TaskStore.swift  Single source of truth, JSON persistence
  Views/                 Dropdown list, task rows, settings
  Support/               Launch at login, hotkey state, title truncation
MenuDoTests/             22 unit tests covering the store and helpers
```

Dependencies are [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the sandbox safe global hotkey and [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) for opening the dropdown programmatically.

## App Store submission checklist

For maintainers preparing a store release:

1. Replace the placeholder icon in `MenuDo/Resources/Assets.xcassets/AppIcon.appiconset` with final artwork.
2. Confirm the app name is available on the App Store, and rename in `project.yml` if not.
3. Set `DEVELOPMENT_TEAM: <TEAMID>` in `project.yml` and remove `CODE_SIGN_IDENTITY: "-"`, then regenerate.
4. Create the App Store Connect record for bundle ID `org.ahlab.MenuDo`.
5. Archive in Xcode, then Distribute App to App Store Connect.
6. Privacy label is "Data Not Collected". Encryption is exempt, already declared in the Info.plist.
7. Screenshots at 1280x800 or larger: dropdown with tasks in light and dark mode, plus the Settings window.
8. Re-verify launch at login with the properly signed build.

## License

MIT. See [LICENSE](LICENSE).
