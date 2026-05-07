import SwiftUI

struct RideView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        TabView {
            metrics
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Time", value: formatDuration(workoutManager.elapsed))
            row("Distance", value: formatDistance(workoutManager.distanceMeters))
            row("Speed", value: String(format: "%.1f km/h", workoutManager.speedKmh))
            if let hr = workoutManager.heartRate {
                row("HR", value: "\(hr) bpm")
            }
        }
        .padding()
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button(workoutManager.isPaused ? "Resume" : "Pause") {
                workoutManager.togglePause()
            }
            .buttonStyle(.bordered)
            Button(role: .destructive) {
                Task {
                    await workoutManager.end()
                    session.send(["kind": "rideControl", "action": "stop"])
                }
            } label: {
                Label("End", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private func row(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
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
