import CoreLocation
import SwiftUI

/// Under the village search: a "Ma position" button (live current location) and
/// the user's favorite places (synced via /api/me/places) as tappable chips —
/// one tap drops a saved start point into the route.
struct StepExtrasView: View {
    @Environment(AppEnvironment.self) private var env
    var onPick: (Waypoint) -> Void

    @State private var favs: [FavoritePlace] = []
    @State private var locating = false
    @State private var showSave = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { locate() } label: {
                    chip("location.fill", locating ? "Localisation…" : "Ma position", AppColors.terra)
                }
                .disabled(locating)

                ForEach(favs) { f in
                    HStack(spacing: 4) {
                        Button { onPick(f.toWaypoint()) } label: {
                            chip("star.fill", f.city ?? f.name, AppColors.inkMid)
                        }
                        Button { delete(f) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(AppColors.inkLight)
                        }
                    }
                }

                Button { showSave = true } label: {
                    chip("plus", "Enregistrer un lieu", AppColors.inkMid)
                }
            }
            .padding(.vertical, 2)
        }
        .task { favs = (try? await APIClient.shared.favoritePlaces()) ?? [] }
        .sheet(isPresented: $showSave) {
            NavigationStack {
                VStack {
                    VillageSearchView(placeholder: "Adresse à mettre en favori") { result in
                        Task {
                            if let row = try? await APIClient.shared.addFavoritePlace(result.toWaypoint()) {
                                await MainActor.run { favs.insert(row, at: 0) }
                            }
                            await MainActor.run { showSave = false }
                        }
                    }
                    .padding()
                    Spacer()
                }
                .navigationTitle("Nouveau favori")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showSave = false } } }
            }
        }
    }

    private func chip(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(AppColors.cream))
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func locate() {
        locating = true
        env.location.requestOneShotLocation()
        Task {
            // Poll for a fresh fix (requestOneShotLocation refreshes lastLocation).
            for _ in 0..<25 {
                if let loc = env.location.lastLocation, loc.timestamp.timeIntervalSinceNow > -20 {
                    await addPosition(loc)
                    await MainActor.run { locating = false }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run { locating = false }
        }
    }

    private func addPosition(_ loc: CLLocation) async {
        let name = (try? await CLGeocoder().reverseGeocodeLocation(loc))?.first?.locality ?? "Ma position"
        let w = Waypoint(name: name, code: "pos-\(Int(loc.timestamp.timeIntervalSince1970))", postal: nil,
                         lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                         label: nil, city: name, kind: nil)
        await MainActor.run { onPick(w) }
    }

    private func delete(_ f: FavoritePlace) {
        favs.removeAll { $0.id == f.id }
        Task { try? await APIClient.shared.deleteFavoritePlace(id: f.id) }
    }
}
