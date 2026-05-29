import SwiftUI
import WidgetKit

/// Watch face complication = a tappable tile that launches Little
/// Explorer with one tap from the Watch face. Replaces having to swipe
/// to the app grid every time you want to start a ride.
///
/// Single timeline entry (no schedule — the icon never changes), one
/// SwiftUI view, supported in every modern complication family
/// (circular, corner, rectangular, inline). watchOS 10+ exposes
/// complications via the standard WidgetKit API — no separate target.
struct LittleExplorerComplication: Widget {
    let kind = "LittleExplorerComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName("Little Explorer")
        .description("Lance une sortie en un tap.")
        .supportedFamilies([
            .accessoryCircular,    // round face slot (top / bottom)
            .accessoryCorner,      // corner slot
            .accessoryInline,      // single-line text slot
            .accessoryRectangular, // wide slot (subdial / Modular)
        ])
    }
}

/// Trivial provider — there's nothing to refresh, the complication
/// just shows the app icon + label. Returning a single-entry timeline
/// that never expires keeps WidgetKit from polling us pointlessly.
private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

private struct Entry: TimelineEntry {
    let date: Date
}

/// Rendering — the system picks the layout based on family. The
/// `.widgetAccentable()` modifier lets watchOS tint the bike glyph
/// with the user's chosen accent colour for accessory widgets, which
/// keeps the look native across faces.
private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "bicycle")
                    .font(.system(size: 18, weight: .semibold))
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "bicycle")
                .font(.system(size: 16, weight: .semibold))
                .widgetAccentable()
        case .accessoryInline:
            Label("Little Explorer", systemImage: "bicycle")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "bicycle")
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Little Explorer").font(.headline)
                    Text("Tap pour rouler").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            // Future-proofing: any new family WidgetKit adds gets a
            // sensible fallback rather than a blank tile.
            Image(systemName: "bicycle")
                .widgetAccentable()
        }
    }
}

/// Widget bundle = the entry point WidgetKit looks for. We only ship
/// one complication for now; if we add live activities later they go
/// in here too.
///
/// `@main` lives in this file so this is the entry point for the
/// `LittleExplorerWatchWidgets` app-extension target. The main app
/// target (`LittleExplorerWatchApp`) has its own `@main` — both
/// coexist because they're in *different* targets, each compiled into
/// its own bundle (`.app` vs `.appex`).
@main
struct LittleExplorerWidgets: WidgetBundle {
    var body: some Widget {
        LittleExplorerComplication()
    }
}
