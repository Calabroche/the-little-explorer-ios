import SwiftUI

/// In-progress ride screen.
///
/// Layout: scrollable single page (Digital Crown native) with the four
/// live metrics on top + Pause + End buttons always visible at the
/// bottom. Previously the controls lived on a second vertical page of
/// a TabView — too easy to miss on a Watch screen, especially without
/// hardware to discover the page indicator.
struct RideView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row("Time",     value: formatDuration(workoutManager.elapsed))
                row("Distance", value: formatDistance(workoutManager.distanceMeters))
                row("Speed",    value: String(format: "%.1f km/h", workoutManager.speedKmh))
                if let hr = workoutManager.heartRate {
                    row("HR", value: "\(hr) bpm")
                } else {
                    row("HR", value: "—")
                }

                Divider().padding(.vertical, 6)

                Button {
                    workoutManager.togglePause()
                } label: {
                    Label(
                        workoutManager.isPaused ? "Resume" : "Pause",
                        systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill",
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task {
                        await workoutManager.end()
                        session.send(["kind": "rideControl", "action": "stop"])
                    }
                } label: {
                    Label("End ride", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }
}
