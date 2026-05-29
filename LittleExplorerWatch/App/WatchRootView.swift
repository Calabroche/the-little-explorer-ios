import SwiftUI

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workoutManager

    var body: some View {
        NavigationStack {
            if workoutManager.isActive {
                RideView()
            } else {
                StartView()
            }
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
    @Environment(ItineraryCache.self) private var itineraries

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

                if !itineraries.items.isEmpty {
                    NavigationLink {
                        ItineraryPickerView()
                    } label: {
                        Label(
                            "Itinéraires (\(itineraries.items.count))",
                            systemImage: "map.fill",
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if workoutManager.locationDenied {
                    LocationDeniedHint()
                }

                if let snap = workoutManager.pendingRecovery {
                    RecoveryCard(snapshot: snap)
                }

                if !pending.pending.isEmpty {
                    PendingPill(count: pending.pending.count)
                }
            }
            .padding()
        }
    }
}

/// List view for the itineraries pushed from the iPhone via
/// WCSession (Phase B). Tap one → starts a workout with the
/// itinerary attached as context (Phase C minimal).
private struct ItineraryPickerView: View {
    @Environment(ItineraryCache.self) private var cache
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if cache.items.isEmpty {
                ContentUnavailableView(
                    "Pas encore d'itinéraires",
                    systemImage: "map",
                    description: Text("Crée un itinéraire sur l'app iPhone ou sur le web. Il apparaîtra ici dès que l'iPhone et la Watch peuvent se parler."),
                )
            } else {
                ForEach(cache.items) { itinerary in
                    Button {
                        // Start with the chosen itinerary so the
                        // resulting PendingRide carries its id and the
                        // backend later knows which route was followed.
                        Task {
                            await workoutManager.start(itinerary: itinerary)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(itinerary.name)
                                .font(.body.weight(.semibold))
                                .lineLimit(2)
                            if let km = itinerary.distanceKm {
                                Text("\(km, format: .number.precision(.fractionLength(1))) km")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Itinéraires")
    }
}

/// Surfaced when the previous launch crashed mid-ride and left an
/// in-progress snapshot on disk. Two actions:
///   • Récupérer — turn the orphan into a complete PendingRide
///     (shipped to iPhone like any other ended ride).
///   • Ignorer — drop it. User decides the data isn't worth saving.
private struct RecoveryCard: View {
    @Environment(WorkoutManager.self) private var workoutManager
    let snapshot: InProgressSnapshot

    private var distanceKm: Double { snapshot.distanceM / 1000 }
    private var minutes: Int { Int(snapshot.elapsed / 60) }

    var body: some View {
        VStack(spacing: 6) {
            Text("Sortie interrompue")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text("\(minutes) min · \(distanceKm, format: .number.precision(.fractionLength(2))) km")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("Récupérer") {
                    workoutManager.finalizeRecovery()
                }
                .buttonStyle(.bordered)
                .tint(.green)
                Button("Ignorer") {
                    workoutManager.discardRecovery()
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .font(.caption2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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
