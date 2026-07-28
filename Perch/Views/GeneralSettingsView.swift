import AppKit
import KeyboardShortcuts
import PerchKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Bindable var registry: PluginRegistry
    @Bindable var migration: MigrationState

    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show in menu bar", selection: Binding(
                    get: { registry.primary?.id ?? "" },
                    set: { registry.primaryID = $0 }
                )) {
                    ForEach(registry.enabled) { entry in
                        Text(entry.displayName).tag(entry.id)
                    }
                }
                .disabled(registry.enabled.isEmpty)
                Toggle("Show title in menu bar", isOn: $showTitleInMenuBar)
                Stepper(
                    "Title length: \(titleTruncationLength) characters",
                    value: $titleTruncationLength,
                    in: 10...60,
                    step: 5
                )
                .disabled(!showTitleInMenuBar)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // Re-fired by the resync below; actual state already matches.
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.set(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                        let actual = LaunchAtLogin.isEnabled
                        if actual != newValue {
                            if newValue && LaunchAtLogin.status == .requiresApproval {
                                launchAtLoginError = "Approval needed: enable Perch in System Settings → General → Login Items."
                            }
                            launchAtLogin = actual
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                KeyboardShortcuts.Recorder("Open Perch:", name: .openPerch)
            }

            Section("Migration") {
                Button("Import from MenuDo…") { importFromMenuDo() }
                Text(
                    "Only needed if your tasks didn't carry over from MenuDo 1.x. "
                    + "Choose the old tasks.json when prompted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The fallback for when the sandbox refuses the automatic import. The
    /// user picking the file is itself the consent that grants read access, so
    /// this path works with no entitlement at all.
    private func importFromMenuDo() {
        let panel = NSOpenPanel()
        panel.title = "Import from MenuDo"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = LegacyImporter.legacyTasksURL.deletingLastPathComponent()
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let destination = PluginContext
            .standard(appName: "Perch", identifier: "org.ahlab.perch.menudo")
            .storage
            .url(named: "tasks.json")
        switch LegacyImporter.importTasksOutcome(from: source, to: destination) {
        case .imported:
            migration.notice = "Imported. Relaunch Perch to see your tasks."
        case .alreadyHasData:
            migration.notice = "Nothing imported — Perch already has tasks saved."
        case .nothingToImport:
            migration.notice = "That file couldn't be read — choose the tasks.json file again."
        case .failed:
            migration.notice =
                "Import failed — something went wrong copying that file. "
                + "Check that Perch can read it and try again."
        }
    }
}
