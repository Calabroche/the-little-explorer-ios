import Foundation

enum AppUser: String, CaseIterable, Identifiable, Codable, Sendable {
    case florian
    case helena

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
