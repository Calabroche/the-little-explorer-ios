import SwiftUI

/// Masonry-ish photo gallery, one tile per photo across all rides.
/// Uses AsyncImage for loading. Empty state mirrors the web app
/// (Strava sync hasn't dropped photos for any ride yet).
struct PhotosView: View {
    @Environment(AppEnvironment.self) private var environment

    private struct Photo: Identifiable, Hashable {
        let id: String
        let url: URL
        let title: String
    }

    var body: some View {
        let photos: [Photo] = environment.activityStore.activities.flatMap { activity -> [Photo] in
            (activity.photos ?? []).compactMap { urlString in
                guard let url = URL(string: urlString) else { return nil }
                return Photo(id: "\(activity.id)-\(urlString)", url: url, title: activity.title)
            }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headline(count: photos.count)
                if photos.isEmpty {
                    emptyState
                } else {
                    grid(photos: photos)
                }
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("Galerie photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headline(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count) photos.")
                .font(.system(.largeTitle, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("Des souvenirs.")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
                .foregroundStyle(AppColors.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(AppColors.inkLight)
            Text("Les photos apparaîtront ici une fois synchronisées depuis Strava.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkLight)
                .lineSpacing(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func grid(photos: [Photo]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(photos) { photo in
                tile(photo: photo)
            }
        }
    }

    private func tile(photo: Photo) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: photo.url) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(AppColors.creamDark).overlay(ProgressView())
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(AppColors.creamDark).overlay(
                        Image(systemName: "photo").foregroundStyle(AppColors.inkLight),
                    )
                @unknown default:
                    Rectangle().fill(AppColors.creamDark)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom,
            )
            Text(photo.title.uppercased())
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .lineLimit(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
