import SwiftUI

/// The panel for whichever source is selected.
///
/// A view of its own rather than a branch in `Analytics.panel`, so the switch
/// is read inside a SwiftUI body and observed: flipping the source in Settings
/// swaps an open dropdown without the host having to rebuild it.
struct AnalyticsRootPanel: View {
    let plugin: Analytics

    var body: some View {
        AnalyticsPanelView(store: plugin.activeStore)
            // A fresh identity per source, so expanded cards and measured
            // heights from one source never leak into the other.
            .id(plugin.source)
    }
}

/// The Settings pane, with the source picker on top of the selected source's
/// own configuration.
struct AnalyticsRootSettings: View {
    @Bindable var plugin: Analytics

    var body: some View {
        AnalyticsSettingsView(
            store: plugin.activeStore,
            source: plugin.postHogStore == nil ? nil : $plugin.source
        )
        // Half-typed fields and open sheets belong to the source they were
        // started for.
        .id(plugin.source)
    }
}
