import SwiftUI

/// Root of the Analyses tab. Acts as a hub for the secondary screens
/// the web exposes via the sidebar (Stats, FTP, Compare, Wrapped,
/// Photos, Carte). Pushes each as a destination so the surface stays
/// shallow on iPhone.
struct AnalyticsHubView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment
        NavigationStack {
            VStack(spacing: 0) {
                BrandHeader()
                List {
                    Section("Données") {
                        NavigationLink(value: AnalyticsRoute.map) {
                            row(symbol: "map.fill", title: "Carte des parcours", subtitle: "Toutes les sorties superposées", color: AppColors.green)
                        }
                        NavigationLink(value: AnalyticsRoute.photos) {
                            row(symbol: "photo.on.rectangle.angled", title: "Galerie photos", subtitle: "Vos souvenirs de sortie", color: AppColors.blue)
                        }
                    }
                    Section("Performances") {
                        NavigationLink(value: AnalyticsRoute.performance) {
                            row(symbol: "trophy.fill", title: "Records & charge", subtitle: "Meilleures perfs + programme TSS", color: AppColors.terra)
                        }
                    }
                    Section("Cyclisme") {
                        NavigationLink(value: AnalyticsRoute.ftp) {
                            row(symbol: "bolt.fill", title: "FTP", subtitle: "Power-duration & évolution", color: AppColors.terra)
                        }
                        NavigationLink(value: AnalyticsRoute.compare) {
                            row(symbol: "arrow.left.arrow.right.square", title: "Comparer", subtitle: "Deux sorties, métrique par métrique", color: AppColors.blue)
                        }
                    }
                    Section("Année") {
                        NavigationLink(value: AnalyticsRoute.wrapped) {
                            row(symbol: "sparkles", title: "Bilan annuel", subtitle: "Vos chiffres en 8 cartes", color: AppColors.green)
                        }
                    }
                }
            }
            .background(AppColors.cream)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AnalyticsRoute.self) { route in
                switch route {
                case .map:         AllRoutesMapView()
                case .photos:      PhotosView()
                case .performance: PerformanceView()
                case .ftp:         FtpView()
                case .compare:     CompareView()
                case .wrapped:     WrappedView()
                }
            }
            .task { await env.activityStore.load(user: env.currentUser) }
            .onChange(of: env.currentUser) { _, newUser in
                Task { await env.activityStore.load(user: newUser) }
            }
        }
    }

    private func row(symbol: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(AppColors.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            }
        }
        .padding(.vertical, 4)
    }
}

enum AnalyticsRoute: Hashable {
    case map, photos, performance, ftp, compare, wrapped
}
