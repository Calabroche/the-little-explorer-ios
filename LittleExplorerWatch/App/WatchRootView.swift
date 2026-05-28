import SwiftUI

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workoutManager

    var body: some View {
        if workoutManager.isActive {
            RideView()
        } else {
            StartView()
        }
    }
}

/// Pre-ride home screen.
///
/// Shows the big "Start ride" CTA, a "N en attente" pill when there
/// are unsynced rides on disk (Phase 2 will surface a real sync UI),
/// and a friendly warning if location permission was refused (no GPS
/// = no useful ride trace).
private struct StartView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PendingRideStore.self) private var pending

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "bicycle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("Little Explorer")
                    .font(.headline)

                Button {
                    Task { await workoutManager.start() }
                } label: {
                    Label("Start ride", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if workoutManager.locationDenied {
                    LocationDeniedHint()
                }

                if !pending.pending.isEmpty {
                    PendingPill(count: pending.pending.count)
                }
            }
            .padding()
        }
    }
}

/// Surfaced under the Start button when the user has denied location
/// access at the system prompt. Without GPS we can still log a HR-only
/// ride, but the user almost certainly *wants* the trace — better to
/// surface the misconfiguration explicitly than record a blank ride.
private struct LocationDeniedHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.orange)
            Text("Localisation refusée")
                .font(.caption2).bold()
            Text("Active la localisation depuis Réglages pour enregistrer le tracé.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
    }
}

/// Surfaced when the local store has unsynced rides. Static for v1
/// (just a counter); Phase 2 will add tap-to-trigger-sync interactivity.
private struct PendingPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 11))
            Text("\(count) sortie\(count > 1 ? "s" : "") en attente")
                .font(.system(size: 11).weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.18), in: Capsule())
    }
}
