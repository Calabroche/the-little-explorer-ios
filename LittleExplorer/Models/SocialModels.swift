import Foundation

/// Models for the social layer, mirroring the web API shapes
/// (src/app/api/feed, /api/users, /api/activities/[id]). The shared
/// JSONDecoder does NOT convert snake_case, so every snake_case field is
/// mapped explicitly via CodingKeys.

enum ActivityVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case `public`
    case followers
    case `private`

    var id: String { rawValue }
    var label: String {
        switch self {
        case .public:    return "Public"
        case .followers: return "Abonnés"
        case .private:   return "Moi"
        }
    }
    /// Longer label for the settings picker.
    var longLabel: String {
        switch self {
        case .public:    return "Public (tout le monde + lien)"
        case .followers: return "Abonnés"
        case .private:   return "Moi seul"
        }
    }
}

struct SocialAuthor: Codable, Sendable, Hashable {
    let id: String
    let name: String?
    let image: String?
}

/// A feed / profile card.
struct SocialFeedItem: Codable, Sendable, Identifiable {
    let id: Int
    let author: SocialAuthor
    let isMine: Bool
    let sport: String
    let title: String?
    let date: String
    let distanceKm: Double?
    let elevationM: Int?
    let durationMin: Int?
    let avgSpeedKmh: Double?
    let maxSpeedKmh: Double?
    let gps: [[Double]]
    let visibility: ActivityVisibility
    let likeCount: Int
    let commentCount: Int
    let likedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case id, author, sport, title, date, gps, visibility
        case isMine        = "is_mine"
        case distanceKm    = "distance_km"
        case elevationM    = "elevation_m"
        case durationMin   = "duration_min"
        case avgSpeedKmh   = "avg_speed_kmh"
        case maxSpeedKmh   = "max_speed_kmh"
        case likeCount     = "like_count"
        case commentCount  = "comment_count"
        case likedByMe     = "liked_by_me"
    }

    // Defensive decode: gps / counts may be missing on odd rows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int.self, forKey: .id)
        author       = try c.decode(SocialAuthor.self, forKey: .author)
        isMine       = (try? c.decode(Bool.self, forKey: .isMine)) ?? false
        sport        = (try? c.decode(String.self, forKey: .sport)) ?? "other"
        title        = try? c.decode(String.self, forKey: .title)
        date         = (try? c.decode(String.self, forKey: .date)) ?? ""
        distanceKm   = try? c.decode(Double.self, forKey: .distanceKm)
        elevationM   = try? c.decode(Int.self, forKey: .elevationM)
        durationMin  = try? c.decode(Int.self, forKey: .durationMin)
        avgSpeedKmh  = try? c.decode(Double.self, forKey: .avgSpeedKmh)
        maxSpeedKmh  = try? c.decode(Double.self, forKey: .maxSpeedKmh)
        gps          = (try? c.decode([[Double]].self, forKey: .gps)) ?? []
        visibility   = (try? c.decode(ActivityVisibility.self, forKey: .visibility)) ?? .followers
        likeCount    = (try? c.decode(Int.self, forKey: .likeCount)) ?? 0
        commentCount = (try? c.decode(Int.self, forKey: .commentCount)) ?? 0
        likedByMe    = (try? c.decode(Bool.self, forKey: .likedByMe)) ?? false
    }
}

struct SocialComment: Codable, Sendable, Identifiable {
    let id: String
    let body: String
    let createdAt: String
    let isMine: Bool
    let author: SocialAuthor

    enum CodingKeys: String, CodingKey {
        case id, body, author
        case createdAt = "created_at"
        case isMine    = "is_mine"
    }
}

/// POST /api/activities/[id]/comments wraps the new row under `comment`.
struct PostCommentResponse: Codable, Sendable {
    let comment: SocialComment
}

struct SocialProfile: Codable, Sendable {
    let id: String
    let name: String?
    let image: String?
    let bio: String?
    let isMe: Bool
    let isFollowing: Bool
    let followers: Int
    let following: Int
    let activities: [SocialFeedItem]

    enum CodingKeys: String, CodingKey {
        case id, name, image, bio, followers, following, activities
        case isMe        = "is_me"
        case isFollowing = "is_following"
    }
}

/// Row in a search / followers / following list.
struct SocialUser: Codable, Sendable, Identifiable {
    let id: String
    let name: String?
    let image: String?
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, image
        case isFollowing = "is_following"
    }
}
