# Perch

Small tools that live in your macOS menu bar.

Perch is a host. The tools themselves are plugins: today there's **Tasks**, the
todo list Perch grew out of, and **Analytics**, which puts your Google
Analytics numbers a click away. More can be added without disturbing what's
already there.

## Download

Grab the latest `Perch.zip` from the [Releases page](../../releases/latest),
unzip it, and drag `Perch.app` into your Applications folder.

Requires macOS 14 (Sonoma) or later. Apple Silicon and Intel are both supported.

### First launch

This build is signed ad hoc rather than with a paid Apple Developer certificate,
so macOS Gatekeeper will block it the first time. To open it:

1. Right click (or Control click) `Perch.app` and choose **Open**.
2. Click **Open** again in the dialog that appears.

You only need to do this once. If macOS still refuses, run this in Terminal and
try again:

```bash
xattr -dr com.apple.quarantine /Applications/Perch.app
```

## Coming from MenuDo

Perch is MenuDo renamed and rebuilt as a plugin host. It starts with an empty
list — macOS gives each app its own sandbox, and Perch's is a different one, so
tasks from a MenuDo install do not carry over.

If you want them, copy the old file across by hand before first launch:

```
from: ~/Library/Containers/org.ahlab.MenuDo/Data/Library/Application Support/MenuDo/tasks.json
to:   ~/Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/org.ahlab.perch.menudo/tasks.json
```

Also **move `MenuDo.app` to the Trash**. Perch can't unregister MenuDo's
launch-at-login entry, so until the old app is deleted both will start when you
log in.

## Plugins

### Tasks

- **Current task in the menu bar.** The first unfinished task is always visible.
  Complete it and the next one takes its place.
- **Quick add.** Open the panel, type, press Return.
- **Edit in place.** Double-click a task to fix its title. Return saves, Escape
  cancels.
- **Reorder by dragging.** Whatever you drag to the top becomes your current task.
- **Done section.** Completed tasks collapse out of the way instead of
  disappearing. Clear them when you want.

Tasks declares no capabilities: everything it stores stays on your Mac.

### Analytics

Your GA4 numbers in the menu bar, without opening a browser or running a
script.

- **Latest day in the menu bar.** Active users for whichever property you mark
  primary, read from the most recent day GA has — the property's own timezone,
  not your laptop's.
- **A card per property.** This week versus last with signed percentages, a
  sparkline of the week, and the 30-day totals and daily rows one click down.
- **Half-hourly, and on open.** Refreshes in the background, and again when you
  open the panel if what's cached has gone stale. Last-fetched numbers are kept
  on disk, so the panel opens on real data rather than a spinner.

Analytics declares `network` and `credentials`: it talks to Google, and it
holds a service-account key. It is the first plugin in Perch to do either.

#### Setting it up

1. In the [Google Cloud console](https://console.cloud.google.com), create a
   service account and download a JSON key. Enable the **Google Analytics Data
   API**, and the **Admin API** too if you want Perch to find your properties
   for you.
2. In GA4 Admin › Property Access, add the service account's address
   (`…@….iam.gserviceaccount.com`) as a **Viewer**.
3. In Perch, open Settings › Analytics, choose the key file, then either
   **Discover Properties** or add a property by its numeric ID.

The key goes into your login Keychain. Perch reads the file you pick once and
never copies it or keeps a reference to it.

## Settings

Click the gear icon in the panel.

| Pane | What's in it |
|---|---|
| General | Which plugin owns the menu bar, title display and length, launch at login, global hotkey |
| Plugins | Enable or disable each plugin, and see what each one can access |
| Tasks | Per-plugin settings, when a plugin has any |
| Analytics | Service-account key, watched properties, which one is primary |

## Your data

Each plugin gets its own directory inside Perch's sandbox container, on your Mac
only:

```
~/Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/<plugin-id>/
```

Tasks stores a plain JSON file there and nothing else. If that file is ever
unreadable, Perch keeps a `.bak` copy beside it and tells you, rather than
silently starting empty.

Analytics is the exception, and it is the honest illustration of the limit
here: macOS grants permissions to an app, not to individual plugins. Because
Analytics needs the network, the whole binary carries the network entitlement,
including the plugins that would never use it. Perch's Settings window
discloses what each plugin does, but disclosure is all it can offer — it cannot
sandbox one plugin away from another's permissions. Analytics sends nothing but
authenticated requests to Google's own APIs, and stores its key in the
Keychain rather than in the container.

## Building from source

Perch is a SwiftUI app built around `MenuBarExtra`. The Xcode project is
generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so only
`project.yml` is tracked in git.

```bash
brew install xcodegen
git clone https://github.com/prasanthsasikumar/perch.git
cd perch
xcodegen generate
open Perch.xcodeproj
```

Run the tests with:

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS'
```

### Layout

```
PerchKit/                The public plugin API. Knows nothing about the host.
Plugins/MenuDoPlugin/    The Tasks plugin: model, store, views
Plugins/AnalyticsPlugin/ The Analytics plugin: GA4 client, auth, store, views
Perch/
  PerchApp.swift         MenuBarExtra scene, plugin instantiation
  Host/                  Registry, panel chrome, menu bar label
  Views/                 Settings window
  Support/               Launch at login, hotkey state, title truncation
PerchTests/              Unit tests for the kit, the plugin, and the host
```

Dependencies are
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the
sandbox-safe global hotkey and
[MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) for opening
the panel programmatically.

## Writing a plugin

`PerchKit` is the contract. A plugin is a Swift package depending on it, with one
type conforming to `PerchPlugin`, added to the array in `PerchApp.makePlugins()`.

The API is **0.x and unstable** — it will change once a second plugin proves the
shape is right. Plugins are compiled in rather than loaded at runtime.

## License

MIT. See [LICENSE](LICENSE).
