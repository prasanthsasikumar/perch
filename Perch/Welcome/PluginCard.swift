import PerchKit
import SwiftUI

/// The tint each built-in plugin's card uses. Keyed by identifier so a plugin
/// keeps its colour wherever it sits in the grid; anything unknown falls back
/// to the system accent.
enum PluginTint {
    static func color(for id: String) -> Color {
        switch id {
        case "org.ahlab.perch.tasks": .blue
        case "org.ahlab.perch.analytics": .orange
        case "org.ahlab.perch.market": .teal
        case "org.ahlab.perch.busy": .pink
        case "org.ahlab.perch.server": .indigo
        case "org.ahlab.perch.internet": .green
        case "org.ahlab.perch.download": .red
        case "org.ahlab.perch.tap": .purple
        case "org.ahlab.perch.spin": .brown
        case "org.ahlab.perch.scroll": .cyan
        default: .accentColor
        }
    }
}

extension PluginCapability {
    /// A small glyph for the capability row on a card; the full sentence is
    /// its tooltip.
    var symbol: String {
        switch self {
        case .credentials: "key.fill"
        case .network: "network"
        case .notifications: "bell.fill"
        case .downloads: "arrow.down.circle.fill"
        case .accessibility: "hand.tap.fill"
        case .media: "music.note"
        case .input: "computermouse.fill"
        }
    }

    /// A word or two for a capability tag in Settings, where there is room for
    /// a label but not the full sentence (which is the tag's tooltip).
    var shortLabel: String {
        switch self {
        case .credentials: "Account key"
        case .network: "Internet"
        case .notifications: "Notifications"
        case .downloads: "Downloads"
        case .accessibility: "Controls other apps"
        case .media: "Music"
        case .input: "Mouse & trackpad"
        }
    }
}

/// A rounded tile with a plugin's symbol on its tint, the way an app icon
/// would show it.
struct PluginIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.85), tint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.35), radius: 4, y: 2)
    }
}

/// One plugin in the welcome grid. The whole card is the toggle.
struct PluginCard: View {
    let entry: PluginRegistry.Entry
    let isSelected: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    private var tint: Color { PluginTint.color(for: entry.id) }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    PluginIconTile(symbol: entry.icon, tint: tint)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Brand.accent : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                capabilityRow
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(entry.capabilities.disclosureLines.joined(separator: ". "))
    }

    /// What the plugin does that someone would want to know before turning it
    /// on, as glyphs with the full sentence on hover.
    private var capabilityRow: some View {
        HStack(spacing: 8) {
            if entry.capabilities.isEmpty {
                Label("Stays on your Mac", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(PluginCapability.allCases.filter(entry.capabilities.contains), id: \.self) { capability in
                    Image(systemName: capability.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(capability.disclosure)
                }
            }
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(isSelected ? Brand.accent.opacity(0.08) : Color.primary.opacity(isHovering ? 0.06 : 0.035))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Brand.accent : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
            )
    }
}

/// The last card in the grid: Perch's plugins are compiled in, so "add your
/// own" means asking for one or building one, and the card says so.
struct AddYourOwnCard: View {
    @State private var isHovering = false
    @State private var isShowingOptions = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { isShowingOptions = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Brand.accent.opacity(0.12)))
                Text("Add your own")
                    .font(.headline)
                Text("Request a tool, or build one with PerchKit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 176)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isHovering ? 0.3 : 0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isShowingOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                option(
                    title: "Request a tool",
                    detail: "Tell us what you'd like Perch to do.",
                    symbol: "lightbulb",
                    url: WelcomeLinks.requestPlugin
                )
                Divider().padding(.vertical, 2)
                option(
                    title: "Build your own",
                    detail: "A plugin is a small Swift package.",
                    symbol: "hammer",
                    url: WelcomeLinks.writingAPlugin
                )
            }
            .padding(8)
            .frame(width: 280)
        }
    }

    private func option(title: String, detail: String, symbol: String, url: URL) -> some View {
        Button {
            isShowingOptions = false
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Perch's own teal, taken from the app icon, so the welcome window looks
/// like Perch rather than like whatever accent the system is set to.
enum Brand {
    static let accent = Color(red: 0.10, green: 0.60, blue: 0.60)
}

enum WelcomeLinks {
    static let requestPlugin = URL(
        string: "https://github.com/prasanthsasikumar/perch/issues/new?title=Plugin%20request%3A%20&labels=plugin-request"
    )!
    static let writingAPlugin = URL(
        string: "https://github.com/prasanthsasikumar/perch#writing-a-plugin"
    )!
}
