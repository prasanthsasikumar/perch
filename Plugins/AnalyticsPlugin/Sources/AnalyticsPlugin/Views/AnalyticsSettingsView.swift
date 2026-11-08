import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The plugin's pane in Perch's Settings window: which source to read, its
/// credential, a list of properties (or sites), and a way to find them.
struct AnalyticsSettingsView: View {
    @Bindable var store: AnalyticsStore
    /// `nil` hides the picker, for a plugin built with one source only.
    var source: Binding<AnalyticsSource>?

    @State private var importError: String?
    @State private var isShowingGuide = false
    @State private var isDiscovering = false
    @State private var discovered: [AnalyticsProperty]?
    @State private var discoveryError: String?
    @State private var manualID = ""
    @State private var manualName = ""

    // PostHog's connection form.
    @State private var isEditingPostHog = false
    @State private var postHogRegion: PostHogCredential.Region = .us
    @State private var postHogProjectID = ""
    @State private var postHogKey = ""

    private var isPostHog: Bool { store.source == .postHog }
    /// "property" for GA, "site" for PostHog.
    private var noun: String { store.source.siteNoun }
    private var nounPlural: String { isPostHog ? "sites" : "properties" }

    var body: some View {
        Form {
            if let source {
                sourceSection(source)
            }
            if isPostHog {
                postHogSection
            } else {
                credentialSection
            }
            propertiesSection
            manualSection
        }
        .formStyle(.grouped)
        .sheet(item: Binding(
            get: { discovered.map(DiscoveryResult.init) },
            set: { if $0 == nil { discovered = nil } }
        )) { result in
            DiscoverySheet(
                title: isPostHog ? "Sites with pageviews in the last 30 days" : "Properties this account can see",
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

    // MARK: - Source

    private func sourceSection(_ source: Binding<AnalyticsSource>) -> some View {
        Section {
            Picker("Data source", selection: source) {
                ForEach(AnalyticsSource.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Each source keeps its own key and list, so switching loses nothing. The panel and menu bar show the selected one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - PostHog

    @ViewBuilder
    private var postHogSection: some View {
        Section {
            if let credential = store.postHogCredential, !isEditingPostHog {
                LabeledContent("Region", value: credential.region.title)
                LabeledContent("Project ID") {
                    Text(credential.projectID).textSelection(.enabled)
                }
                LabeledContent("API key") {
                    Text(credential.maskedKey).font(.callout.monospaced())
                }
                if store.properties.isEmpty {
                    Label("Connected. Next, click **Discover Sites…** below to choose the sites to watch.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                HStack {
                    Button("Replace Key…") {
                        // Pre-filled with what is there, so replacing the key
                        // does not mean retyping the project.
                        postHogRegion = credential.region
                        postHogProjectID = credential.projectID
                        postHogKey = ""
                        importError = nil
                        isEditingPostHog = true
                    }
                    Button("Remove", role: .destructive) {
                        try? store.removeCredential()
                    }
                }
            } else {
                PostHogSetupSteps(region: postHogRegion)
                    .padding(.vertical, 4)
                Picker("Region", selection: $postHogRegion) {
                    ForEach(PostHogCredential.Region.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Project ID", text: $postHogProjectID, prompt: Text("12345"))
                SecureField("Personal API key", text: $postHogKey, prompt: Text("phx_…"))
                if let postHogHint {
                    Label(postHogHint, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Connect") { connectPostHog() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            postHogProjectID.trimmingCharacters(in: .whitespaces).isEmpty
                                || postHogKey.trimmingCharacters(in: .whitespaces).isEmpty
                                || postHogHint != nil
                        )
                    if isEditingPostHog {
                        Button("Cancel") {
                            isEditingPostHog = false
                            postHogKey = ""
                            importError = nil
                        }
                    }
                }
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("PostHog")
        } footer: {
            Text("The key is stored in your login Keychain. Perch only reads from PostHog; a key with just **Query: read** can't change anything there.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Catches the two mistakes almost everyone makes on the way, before
    /// Connect turns them into a less specific error.
    private var postHogHint: String? {
        let project = postHogProjectID.trimmingCharacters(in: .whitespaces)
        let key = postHogKey.trimmingCharacters(in: .whitespaces)
        if !project.isEmpty, !project.allSatisfy(\.isNumber) {
            return "The Project ID is a number, such as 12345. You'll find it in step 1."
        }
        if key.hasPrefix("phc_") {
            return "That's the project token your websites use. Perch needs a personal API key from step 2, which starts with phx_."
        }
        if !key.isEmpty, !key.hasPrefix("phx_") {
            return "Personal API keys start with phx_."
        }
        return nil
    }

    private func connectPostHog() {
        do {
            try store.connectPostHog(region: postHogRegion, projectID: postHogProjectID, apiKey: postHogKey)
            importError = nil
            postHogKey = ""
            isEditingPostHog = false
            // With nothing chosen yet, go straight to picking sites. It is
            // also the first real request, so a wrong key or a missing scope
            // shows up here, next to the form, instead of later in the panel.
            if store.properties.isEmpty {
                discover()
            } else {
                Task { await store.refresh() }
            }
        } catch let error as AnalyticsError {
            importError = error.message(clientEmail: nil, source: .postHog)
        } catch let error as KeychainCredentialStore.Failure where error.isUnavailable {
            importError = "This build can't reach the Keychain, so the key can't be stored."
        } catch {
            importError = error.localizedDescription
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
            HStack(spacing: 4) {
                Text("Credentials")
                Button {
                    isShowingGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Where to get a service-account key")
                .accessibilityLabel("Where to get a service-account key")
                .popover(isPresented: $isShowingGuide, arrowEdge: .bottom) {
                    SetupGuide(clientEmail: store.clientEmail)
                }
            }
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
                Text("No \(nounPlural) yet")
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
                        .help("Show this \(noun) in the menu bar")

                        VStack(alignment: .leading, spacing: 1) {
                            // Editable in place: GA's names are often the
                            // console nickname ("homepage") rather than the
                            // domain, and this is the only place they show.
                            TextField("Name", text: Binding(
                                get: { property.displayName },
                                set: { store.renameProperty(id: property.id, to: $0) }
                            ))
                            .textFieldStyle(.plain)
                            // A PostHog site's id is its domain, which the
                            // name already shows unless it was renamed.
                            if !isPostHog || property.displayName != property.id {
                                Text(property.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            store.removeProperty(id: property.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop watching this \(noun)")
                    }
                }
            }

            HStack {
                Button(isPostHog ? "Discover Sites…" : "Discover Properties…") { discover() }
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
            Text(isPostHog ? "Sites" : "Properties")
        } footer: {
            Text("The selected \(noun) is the one the menu bar shows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Manual entry

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField("Name", text: $manualName, prompt: Text(isPostHog ? "Optional" : "example.com"))
            TextField(
                isPostHog ? "Domain" : "Property ID",
                text: $manualID,
                prompt: Text(isPostHog ? "example.com" : "516503233")
            )
            Button(isPostHog ? "Add Site" : "Add Property") {
                let typed = manualID.trimmingCharacters(in: .whitespaces)
                let id = isPostHog ? AnalyticsProperty.host(fromTyped: typed) : typed
                let name = manualName.trimmingCharacters(in: .whitespaces)
                store.addProperty(AnalyticsProperty(id: id, displayName: name.isEmpty ? id : name))
                manualID = ""
                manualName = ""
                Task { await store.refresh() }
            }
            .disabled(manualID.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text(isPostHog ? "Add by domain" : "Add by ID")
        } footer: {
            Text(
                isPostHog
                    ? "Discovery lists every domain ($host) with pageviews in the last 30 days. "
                        + "Add one here if it hasn't had traffic yet. Use the domain exactly as "
                        + "PostHog records it, without https://."
                    : "Discovery lists what the whole account can see. A service account granted "
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
                    discoveryError = isPostHog
                        ? "No pageviews in the last 30 days yet. Add a site by domain below."
                        : "This account can't see any properties. "
                            + "Grant it access in GA4 Admin, or add a property by ID below."
                } else {
                    discovered = found
                }
            } catch let error as AnalyticsError {
                discoveryError = error.message(clientEmail: store.clientEmail, source: store.source)
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
    let title: String
    let found: [AnalyticsProperty]
    let onCancel: () -> Void
    let onApply: ([AnalyticsProperty]) -> Void

    @State private var selected: Set<String>

    init(
        title: String,
        found: [AnalyticsProperty],
        selected: Set<String>,
        onCancel: @escaping () -> Void,
        onApply: @escaping ([AnalyticsProperty]) -> Void
    ) {
        self.title = title
        self.found = found
        self.onCancel = onCancel
        self.onApply = onApply
        // Pre-ticks what is already being watched, so applying the sheet is
        // never a silent way to lose properties.
        _selected = State(initialValue: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
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
                        if property.displayName != property.id {
                            Text(property.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

/// The PostHog half of setup, as numbered steps beside the fields they fill.
/// Shown until a key is connected, so nobody has to know PostHog's settings
/// layout to get started.
private struct PostHogSetupSteps: View {
    let region: PostHogCredential.Region

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SetupStep(number: 1, title: "Copy your Project ID") {
                Text("In PostHog, open **Settings › Project › General**. It's the number under **Project ID**. It's also the number after /project/ in PostHog's address bar.")
                Link("Open project settings", destination: region.host.appendingPathComponent("settings/project"))
            }
            SetupStep(number: 2, title: "Create a personal API key") {
                Text("Open **Account settings › Personal API keys** and click **Create personal API key**. Name it **Perch**.")
                Text("Under scopes, set **Query** to **Read** and leave everything else off. If PostHog asks, limit it to this project.")
                Text("Copy the key right away: PostHog shows it only once. It starts with **phx_**.")
                    .foregroundStyle(.secondary)
                Link("Open personal API keys", destination: region.host.appendingPathComponent("settings/user-api-keys"))
            }
            SetupStep(number: 3, title: "Paste both below and click Connect") {
                Text("Choose **EU Cloud** only if your PostHog address starts with eu.posthog.com.")
            }
            SetupStep(number: 4, title: "Pick your sites") {
                Text("Perch then lists every domain that sent page views in the last 30 days, and you tick the ones to watch.")
            }
        }
    }
}
