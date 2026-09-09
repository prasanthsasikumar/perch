import SwiftUI

/// The plugin's half of the dropdown: a card per server, and a form to add
/// one.
struct ServerPanelView: View {
    @Bindable var store: ServerStore

    /// How old the numbers may be before opening the panel refetches. Short,
    /// because opening this panel is almost always someone asking "is it OK
    /// right now".
    private static let openRefreshAge: TimeInterval = 30

    @State private var isAdding = false
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var addressError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let notice = store.loadFailureNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let notice = store.saveFailureNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if store.servers.isEmpty && !isAdding {
                    empty
                } else {
                    ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 { Divider() }
                        ServerCardView(
                            server: server,
                            snapshot: store.snapshots[server.id],
                            failure: store.failures[server.id],
                            alerts: store.alerts(for: server.id),
                            trend: store.trends[server.id] ?? [],
                            onDelete: { store.deleteServer(id: server.id) }
                        )
                    }
                }

                if isAdding {
                    Divider()
                    addForm
                } else if !store.servers.isEmpty {
                    Button("Add a server") { isAdding = true }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
            footer
        }
        .task {
            guard !store.servers.isEmpty else { return }
            await store.refreshIfStale(maxAge: Self.openRefreshAge)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No servers yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Point this at a machine running the vpsstat agent, for example https://status.example.com.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Add a server") { isAdding = true }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("https://status.example.com", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            HStack(spacing: 6) {
                TextField("Username (optional)", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
            }
            if let addressError {
                Text(addressError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Add", action: add)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { reset() }
                Spacer()
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking…")
            } else {
                Text(freshness)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var freshness: String {
        guard let lastRefreshed = store.lastRefreshed else { return "Not checked yet" }
        return "Updated \(RelativeTime.describe(lastRefreshed))"
    }

    private func add() {
        guard store.addServer(
            address: address,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        ) != nil else {
            addressError = ServerError.badURL.message
            return
        }
        reset()
        Task { await store.refresh() }
    }

    private func reset() {
        address = ""
        username = ""
        password = ""
        addressError = nil
        isAdding = false
    }
}
