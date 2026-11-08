import KeyboardShortcuts
import SwiftUI

/// The first thing a fresh install shows: a welcome, a grid of every plugin to
/// pick from, and a last step that says where Perch lives.
struct WelcomeView: View {
    static let size = NSSize(width: 980, height: 660)

    private enum Step: Int, CaseIterable {
        case welcome, choose, done
    }

    let registry: PluginRegistry
    /// Called when the user finishes; `true` asks for the panel to open.
    let onFinish: (Bool) -> Void

    @State private var step: Step = .welcome
    @State private var selection: Set<String>
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    init(registry: PluginRegistry, onFinish: @escaping (Bool) -> Void) {
        self.registry = registry
        self.onFinish = onFinish
        // Starts from what is on now: on a fresh install that is the short
        // recommended list; reopened from Settings, it is the user's own.
        _selection = State(initialValue: Set(registry.enabled.map(\.id)))
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .choose: chooseStep
                    case .done: doneStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)

                footer
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            VStack(spacing: 10) {
                Text("Welcome to Perch")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Small tools that live in your menu bar.\nPick the ones you want — leave the rest out.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                highlight(
                    symbol: "square.grid.2x2.fill",
                    title: "Only what you choose",
                    detail: "Each tool is a tab. Off means fully off."
                )
                highlight(
                    symbol: "lock.shield.fill",
                    title: "Private by default",
                    detail: "Your data stays on your Mac."
                )
                highlight(
                    symbol: "menubar.arrow.up.rectangle",
                    title: "Always a click away",
                    detail: "Glance at the menu bar, or open with a shortcut."
                )
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose your tools")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Each one you pick becomes a tab in the Perch panel.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = allSelected ? [] : Set(registry.entries.map(\.id))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.accent)
            }

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    spacing: 12
                ) {
                    ForEach(registry.entries) { entry in
                        PluginCard(entry: entry, isSelected: selection.contains(entry.id)) {
                            if selection.contains(entry.id) {
                                selection.remove(entry.id)
                            } else {
                                selection.insert(entry.id)
                            }
                        }
                    }
                    AddYourOwnCard()
                }
                .padding(4)

                Label(
                    "Small icons show what a tool can do — connect to the internet, store a key, "
                        + "send notifications. Hover one for details.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
    }

    private var doneStep: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Brand.accent.opacity(0.12))
                    .frame(width: 112, height: 112)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Brand.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 10) {
                Text("You're all set")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Perch lives in your menu bar, at the top right of your screen.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            chosenStrip

            VStack(spacing: 0) {
                HStack {
                    Label("Open Perch at login", systemImage: "power")
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .tint(Brand.accent)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            guard newValue != LaunchAtLogin.isEnabled else { return }
                            try? LaunchAtLogin.set(newValue)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                }
                .padding(.vertical, 10)
                Divider()
                HStack {
                    Label("Keyboard shortcut", systemImage: "command")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .openPerch)
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .frame(width: 420)

            Text("You can change your tools anytime in Settings › Plugins.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    /// The tools the user picked, as a row of tiles, so the last step
    /// confirms the choice rather than just announcing success.
    private var chosenStrip: some View {
        HStack(spacing: 10) {
            ForEach(registry.entries.filter { selection.contains($0.id) }) { entry in
                PluginIconTile(symbol: entry.icon, tint: PluginTint.color(for: entry.id), size: 34)
                    .help(entry.displayName)
            }
        }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack {
            stepDots
            Spacer()
            switch step {
            case .welcome:
                Button("Get Started") { go(to: .choose) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            case .choose:
                Text(selection.isEmpty ? "Pick at least one" : "\(selection.count) of \(registry.entries.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                Button("Back") { go(to: .welcome) }
                Button("Continue") {
                    registry.setEnabledIDs(selection)
                    go(to: .done)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            case .done:
                Button("Back") { go(to: .choose) }
                Button("Open Perch") { onFinish(true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .tint(Brand.accent)
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(candidate == step ? Brand.accent : Color.primary.opacity(0.18))
                    .frame(width: candidate == step ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Brand.accent.opacity(0.14), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private func highlight(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Brand.accent)
                .frame(height: 28)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var allSelected: Bool { selection.count == registry.entries.count }

    private func go(to next: Step) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { step = next }
    }
}
