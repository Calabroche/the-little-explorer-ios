import SwiftUI
import UIKit

// Shared bits for the social layer UI: the GPS trace shape (no map tiles),
// an avatar, a UIActivityViewController wrapper, and small formatters.

/// Aspect-correct polyline of a GPS trace, drawn to fill the given rect.
/// Longitude is scaled by cos(latitude) so the trace isn't stretched.
struct TraceShape: Shape {
    let points: [[Double]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pts = points.filter { $0.count >= 2 }
        guard pts.count >= 2 else { return path }
        let lats = pts.map { $0[0] }, lngs = pts.map { $0[1] }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return path }
        let midLat = (minLat + maxLat) / 2
        let kx = cos(midLat * .pi / 180)
        let spanX = CGFloat(max(1e-6, (maxLng - minLng) * kx))
        let spanY = CGFloat(max(1e-6, maxLat - minLat))
        let pad: CGFloat = 6
        let scale = min((rect.width - pad * 2) / spanX, (rect.height - pad * 2) / spanY)
        let offX = rect.minX + (rect.width - spanX * scale) / 2
        let offY = rect.minY + (rect.height - spanY * scale) / 2
        func project(_ lat: Double, _ lng: Double) -> CGPoint {
            CGPoint(x: offX + CGFloat((lng - minLng) * kx) * scale,
                    y: offY + CGFloat(maxLat - lat) * scale)
        }
        for (i, p) in pts.enumerated() {
            let cp = project(p[0], p[1])
            if i == 0 { path.move(to: cp) } else { path.addLine(to: cp) }
        }
        return path
    }
}

/// Circular avatar: remote image if present, otherwise a terra circle with
/// the first initial.
struct AvatarView: View {
    let url: String?
    let name: String?
    var size: CGFloat = 34

    private var initial: String {
        String((name ?? "?").trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
    }

    /// Custom avatars are stored as `data:image/...;base64,...` URLs which
    /// AsyncImage/URLSession can't fetch — decode those to a UIImage directly.
    private var inlineImage: UIImage? {
        guard let url, url.hasPrefix("data:"),
              let comma = url.firstIndex(of: ","),
              let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        if let inlineImage {
            Image(uiImage: inlineImage)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let url, url.hasPrefix("http"), let u = URL(string: url) {
            AsyncImage(url: u) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                AppColors.creamBorder
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle().fill(AppColors.terra)
                .frame(width: size, height: size)
                .overlay(
                    Text(initial)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// (ShareSheet lives in LittleExplorer/UI/ShareSheet.swift — reused here.)

// ── Formatters ─────────────────────────────────────────────────────────────
enum SocialFmt {
    static func duration(_ min: Int?) -> String {
        guard let m = min else { return "—" }
        let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", mm))" : "\(mm) min"
    }
    static func distance(_ km: Double?) -> String {
        guard let km else { return "—" }
        return String(format: "%.1f km", km)
    }
    static func elevation(_ m: Int?) -> String {
        guard let m else { return "—" }
        return "\(m) m"
    }
    static func speed(_ kmh: Double?) -> String {
        guard let kmh else { return "—" }
        return String(format: "%.1f km/h", kmh)
    }
    static func sportLabel(_ s: String) -> String {
        switch s {
        case "cycling":   return "Vélo"
        case "running":   return "Course à pied"
        case "walking":   return "Marche"
        case "hiking":    return "Randonnée"
        case "swim":      return "Natation"
        case "rowing":    return "Aviron"
        case "ski":       return "Ski"
        case "snowboard": return "Snowboard"
        case "yoga":      return "Yoga"
        case "workout":   return "Renforcement"
        default:          return s.isEmpty ? "Sortie" : s.prefix(1).uppercased() + s.dropFirst()
        }
    }
    static func shortDate(_ iso: String) -> String {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let d = withFrac.date(from: iso) ?? plain.date(from: iso) else { return "" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM yyyy"
        return df.string(from: d)
    }
}
