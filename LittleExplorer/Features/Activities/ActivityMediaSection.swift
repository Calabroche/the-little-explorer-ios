import PhotosUI
import SwiftUI

/// Photos on an activity (Strava-style). Viewers see the grid; the owner can
/// add (via PhotosPicker, resized) or delete. Photos live in Supabase Storage;
/// this view talks to /api/activities/<id>/media.
struct ActivityMediaSection: View {
    let activityId: Int
    let canEdit: Bool

    @State private var media: [ActivityMedia] = []
    @State private var loaded = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var error: String?

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        Group {
            if !media.isEmpty || canEdit {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("PHOTOS").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(AppColors.terra)
                        Spacer()
                        if canEdit {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text(busy ? "Ajout…" : "＋ Ajouter").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.terra)
                            }
                            .disabled(busy)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    if !media.isEmpty {
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(media) { m in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: URL(string: m.url)) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { AppColors.creamBorder }
                                    .frame(height: 104).frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    if canEdit {
                                        Button { remove(m) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.white, .black.opacity(0.5))
                                        }
                                        .padding(5)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(AppColors.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.creamBorder, lineWidth: 1))
            }
        }
        .task { if !loaded { await load() } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func load() async {
        media = (try? await APIClient.shared.activityMedia(activityId: activityId)) ?? []
        loaded = true
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true; error = nil
        defer { busy = false; pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let dataUrl = Self.jpegDataUrl(image, maxDim: 1280) else {
            error = "Image illisible."; return
        }
        do {
            let m = try await APIClient.shared.addActivityPhoto(activityId: activityId, imageDataUrl: dataUrl)
            media.append(m)
        } catch { self.error = "Échec de l'ajout." }
    }

    private func remove(_ m: ActivityMedia) {
        media.removeAll { $0.id == m.id }
        Task { try? await APIClient.shared.deleteActivityMedia(activityId: activityId, mediaId: m.id) }
    }

    /// Downscale to `maxDim` (longest edge) and return a JPEG data URL.
    static func jpegDataUrl(_ image: UIImage, maxDim: CGFloat) -> String? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDim / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = out.jpegData(compressionQuality: 0.82) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
