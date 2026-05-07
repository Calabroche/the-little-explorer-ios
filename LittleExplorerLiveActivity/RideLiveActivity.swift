import ActivityKit
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen / banner.
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.7))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(formatDistance(context.state.distanceKm), systemImage: "bicycle")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(formatDuration(context.state.durationSec), systemImage: "clock")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("SPEED").font(.caption2).foregroundStyle(.secondary)
                            Text(formatSpeed(context.state.speedKmh)).font(.title3.weight(.bold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("ELEV").font(.caption2).foregroundStyle(.secondary)
                            Text("\(Int(context.state.elevationGainM)) m").font(.title3.weight(.bold)).monospacedDigit()
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(.tint)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceKm)).monospacedDigit()
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(.tint)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.RideState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.sportLabel, systemImage: "bicycle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(state.durationSec))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            HStack(spacing: 16) {
                metric("Distance", formatDistance(state.distanceKm))
                metric("Speed", formatSpeed(state.speedKmh))
                metric("Elev", "\(Int(state.elevationGainM)) m")
            }
            if let next = state.nextManeuver, let dist = state.nextManeuverDistanceM {
                HStack(spacing: 8) {
                    Image(systemName: state.nextManeuverSymbol ?? "arrow.up")
                    Text(next).lineLimit(1)
                    Spacer()
                    Text(formatMeters(dist)).monospacedDigit()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Formatting (kept local — Formatters.swift lives in Shared but
// importing the iOS module from a widget extension isn't free in xcodegen).

private func formatDistance(_ km: Double) -> String {
    String(format: "%.2f km", km)
}

private func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d", m, s % 60)
}

private func formatSpeed(_ kmh: Double) -> String {
    String(format: "%.1f km/h", kmh)
}

private func formatMeters(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
}
