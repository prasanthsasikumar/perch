import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The plugin's pane in Perch's Settings window: one credential, a list of
/// properties, and a way to find them.
struct AnalyticsSettingsView: View {
    @Bindable var store: AnalyticsStore

    @State private var importError: String?
    @State private var isDiscovering = false
    @State private var discovered: [AnalyticsProperty]?
    @State private var discoveryError: String?
    @State private var manualID = ""
    @State private var manualName = ""

    var body: some View {
        Form {
            credentialSection
            propertiesSection
            manualSection
        }
        .formStyle(.grouped)
        .sheet(item: Binding(
            get: { discovered.map(DiscoveryResult.init) },
            set: { if $0 == nil { discovered = nil } }
        )) { result in
            DiscoverySheet(
                found: result.properties,
                selected: Set(store.properties.map(\.id)),
                onCancel: { discovered = nil },
                onApply: { chosen in
                    store.setProperties(chosen)
                    discovered = nil
                    Task { await store.refresh() }
                }
            )
        }
    }

    // MARK: - Credential

    @ViewBuilder
    private var credentialSection: some View {
        Section {
            if let email = store.clientEmail {
                LabeledContent("Service account") {
                    Text(email)
                        .textSelection(.enabled)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Replace Key…") { importKey() }
                    Button("Remove", role: .destructive) {
                        try? store.removeCredential()
                    }
                }
            } else {
                Button("Choose Service Account Key…") { importKey() }
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Credentials")
        } footer: {
            Text(
                "The key is stored in your login Keychain, not copied into Perch. "
                + "Add the service account as a viewer in GA4 Admin › Property Access "
                + "before it can read anything."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Properties

    @ViewBuilder
    private var propertiesSection: some View {
        Section {
            if store.properties.isEmpty {
                Text("No properties yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.properties) { property in
                    HStack {
                        // A radio rather than a picker: the choice is which
                        // row, and a picker would restate the same list.
                        Button {
                            store.primaryPropertyID = property.id
                        } label: {
                            Image(systemName: store.primaryPropertyID == property.id
                                  ? "largecircle.fill.circle" : "circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Show this property in the menu bar")

                        VStack(alignment: .leading, spacing: 1) {
                            // Editable in place: GA's names are often the
                            // console nickname ("homepage") rather than the
                            // domain, and this is the only place they show.
                            TextField("Name", text: Binding(
                                get: { property.displayName },
                                set: { store.renameProperty(id: property.id, to: $0) }
                            ))
                            .textFieldStyle(.plain)
                            Text(property.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.removeProperty(id: property.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop watching this property")
                    }
                }
            }

            HStack {
                Button("Discover Properties…") { discover() }
                    .disabled(!store.isConfigured || isDiscovering)
                if isDiscovering {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Refresh Now") {
                    Task { await store.refresh() }
                }
                .disabled(!store.isConfigured || store.properties.isEmpty || store.isRefreshing)
            }

            if let discoveryError {
                Text(discoveryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Properties")
        } footer: {
            Text("The selected property is the one the menu bar shows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Manual entry

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField("Name", text: $manualName, prompt: Text("example.com"))
            TextField("Property ID", text: $manualID, prompt: Text("516503233"))
            Button("Add Property") {
                let id = manualID.trimmingCharacters(in: .whitespaces)
                let name = manualName.trimmingCharacters(in: .whitespaces)
                store.addProperty(AnalyticsProperty(id: id, displayName: name.isEmpty ? id : name))
                manualID = ""
                manualName = ""
                Task { await store.refresh() }
            }
            .disabled(manualID.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Add by ID")
        } footer: {
            Text(
                "Discovery lists what the whole account can see. A service account granted "
                + "access to one property rather than the account won't show up there — "
                + "add it here instead."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func importKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the service-account JSON key downloaded from Google Cloud."
        // Settings can be behind another app when this fires, and a modal
        // sheetless panel behind it is a panel the user cannot find.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.importCredential(from: url)
            importError = nil
            Task { await store.refresh() }
        } catch let error as AnalyticsError {
            importError = error.message(clientEmail: nil)
        } catch let error as KeychainCredentialStore.Failure where error.isUnavailable {
            importError = "This build can't reach the Keychain, so the key can't be stored."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func discover() {
        isDiscovering = true
        discoveryError = nil
        Task {
            defer { isDiscovering = false }
            do {
                let found = try await store.discoverProperties()
                if found.isEmpty {
                    discoveryError = "This account can't see any properties. "
                        + "Grant it access in GA4 Admin, or add a property by ID below."
                } else {
                    discovered = found
                }
            } catch let error as AnalyticsError {
                discoveryError = error.message(clientEmail: store.clientEmail)
            } catch {
                discoveryError = error.localizedDescription
            }
        }
    }
}

/// `sheet(item:)` needs an `Identifiable`, and an array is not one.
private struct DiscoveryResult: Identifiable {
    let properties: [AnalyticsProperty]
    var id: String { properties.map(\.id).joined(separator: ",") }

    init(_ properties: [AnalyticsProperty]) {
        self.properties = properties
    }
}

private struct DiscoverySheet: View {
    let found: [AnalyticsProperty]
    let onCancel: () -> Void
    let onApply: ([AnalyticsProperty]) -> Void

    @State private var selected: Set<String>

    init(
        found: [AnalyticsProperty],
        selected: Set<String>,
        onCancel: @escaping () -> Void,
        onApply: @escaping ([AnalyticsProperty]) -> Void
    ) {
        self.found = found
        self.onCancel = onCancel
        self.onApply = onApply
        // Pre-ticks what is already being watched, so applying the sheet is
        // never a silent way to lose properties.
        _selected = State(initialValue: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties this account can see")
                .font(.headline)

            List(found) { property in
                Toggle(isOn: Binding(
                    get: { selected.contains(property.id) },
                    set: { isOn in
                        if isOn {
                            selected.insert(property.id)
                        } else {
                            selected.remove(property.id)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(property.displayName)
                        Text(property.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Watch Selected") {
                    onApply(found.filter { selected.contains($0.id) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
