import Foundation

/// 视频/剧集条目：字段与后端 VideoItem 逐项对应
struct VideoItem: Identifiable, Decodable, Equatable, Hashable {
    let id: Int64
    var title: String?
    var filename: String?
    var path: String?
    var type: String?
    var episodeIndex: Int?
    var thumbnail: String?
    var cover: String?
    var artist: String?
    var album: String?
    var lyrics: String?
    var bitrate: Int64?
    var format: String?
    var duration: Double?
    var width: Int?
    var height: Int?
    var size: Int64?
    var createdAt: String?
    var seriesId: Int64?
    var seriesTitle: String?
    var totalEpisodes: Int?
    var seriesCover: String?
    var likes: Int
    var favorites: Int
    var isLiked: Int
    var isFavorited: Int
    var authorId: Int64?
    var authorName: String?
    var authorAvatar: String?
    var libraryName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, filename, path, type, thumbnail, cover, artist, album, lyrics
        case bitrate, format, duration, width, height, size, likes, favorites
        case episodeIndex = "episode_index"
        case createdAt = "created_at"
        case seriesId = "series_id"
        case seriesTitle = "series_title"
        case totalEpisodes = "total_episodes"
        case seriesCover = "series_cover"
        case isLiked = "isLiked"
        case isFavorited = "isFavorited"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case libraryName = "library_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? Int64((try? c.decode(String.self, forKey: .id)) ?? "0") ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        filename = try? c.decodeIfPresent(String.self, forKey: .filename)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        episodeIndex = Self.flexInt(c, .episodeIndex)
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        artist = try? c.decodeIfPresent(String.self, forKey: .artist)
        album = try? c.decodeIfPresent(String.self, forKey: .album)
        lyrics = try? c.decodeIfPresent(String.self, forKey: .lyrics)
        bitrate = Self.flexInt64(c, .bitrate)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        duration = Self.flexDouble(c, .duration)
        width = Self.flexInt(c, .width)
        height = Self.flexInt(c, .height)
        size = Self.flexInt64(c, .size)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        seriesId = Self.flexInt64(c, .seriesId)
        seriesTitle = try? c.decodeIfPresent(String.self, forKey: .seriesTitle)
        totalEpisodes = Self.flexInt(c, .totalEpisodes)
        seriesCover = try? c.decodeIfPresent(String.self, forKey: .seriesCover)
        likes = Self.flexInt(c, .likes) ?? 0
        favorites = Self.flexInt(c, .favorites) ?? 0
        isLiked = Self.flexInt(c, .isLiked) ?? 0
        isFavorited = Self.flexInt(c, .isFavorited) ?? 0
        authorId = Self.flexInt64(c, .authorId)
        authorName = try? c.decodeIfPresent(String.self, forKey: .authorName)
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        libraryName = try? c.decodeIfPresent(String.self, forKey: .libraryName)
    }

    /// 没有标题时退回文件名
    var displayTitle: String { (title?.isEmpty == false ? title! : (filename ?? "未命名")) }
    var displayEpisode: String? {
        guard let n = episodeIndex, n > 0 else { return nil }
        return "第\(n)集"
    }

    static func flexInt(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(v) }
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return Int(v) }
        return nil
    }
    static func flexInt64(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int64? {
        if let v = try? c.decodeIfPresent(Int64.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return Int64(v) }
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return Int64(v) }
        return nil
    }
    static func flexDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Int64.self, forKey: k) { return Double(v) }
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return Double(v) }
        return nil
    }
}

/// 剧集系列
struct Series: Identifiable, Decodable, Equatable, Hashable {
    let id: Int64
    var title: String?
    var path: String?
    var cover: String?
    var totalEpisodes: Int?
    var description: String?
    var createdAt: String?
    var episodeCount: Int?
    var totalLikes: Int
    var firstEpisodeThumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, path, cover, description
        case totalEpisodes = "total_episodes"
        case createdAt = "created_at"
        case episodeCount = "episode_count"
        case totalLikes = "total_likes"
        case firstEpisodeThumbnail = "first_episode_thumbnail"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? Int64((try? c.decode(String.self, forKey: .id)) ?? "0") ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        totalEpisodes = (try? c.decodeIfPresent(Int.self, forKey: .totalEpisodes))
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        episodeCount = (try? c.decodeIfPresent(Int.self, forKey: .episodeCount))
        totalLikes = (try? c.decodeIfPresent(Int.self, forKey: .totalLikes)) ?? 0
        firstEpisodeThumbnail = try? c.decodeIfPresent(String.self, forKey: .firstEpisodeThumbnail)
    }

    var displayTitle: String { (title?.isEmpty == false ? title! : "未命名剧集") }
    var coverName: String? { cover ?? firstEpisodeThumbnail }
    var episodeTotal: Int? { episodeCount ?? totalEpisodes }
}

struct SeriesDetailResponse: Decodable {
    var series: Series?
    var episodes: [VideoItem]?
}

struct FeedResponse: Decodable {
    var videos: [VideoItem]?
}

struct User: Decodable, Equatable {
    var id: Int64
    var username: String?
    var nickname: String?
    var role: String?
    var avatar: String?
    var permissions: [String]?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, role, avatar, permissions
        case createdAt = "created_at"
    }

    var isAdmin: Bool { role == "admin" }
    var displayName: String {
        if let n = nickname, !n.isEmpty { return n }
        return username ?? "未登录"
    }
    var roleText: String { role == "admin" ? "管理员" : "用户" }
}

struct LoginResponse: Decodable {
    var token: String?
    var user: User?
}

struct Folder: Identifiable, Decodable {
    var id: Int64
    var name: String?
    var videoCount: Int
    var cover: String?

    enum CodingKeys: String, CodingKey {
        case id, name, cover
        case videoCount = "video_count"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        videoCount = (try? c.decodeIfPresent(Int.self, forKey: .videoCount)) ?? 0
        cover = try? c.decodeIfPresent(String.self, forKey: .cover)
    }
}

/// 管理后台媒体库路径
struct AdminPath: Identifiable, Decodable, Equatable {
    var id: Int64
    var path: String?
    var type: String?
    var name: String?
    var enabled: Int
    var lastScan: String?
    var fileCount: Int
    var scanning: Bool

    enum CodingKeys: String, CodingKey {
        case id, path, type, name, enabled, scanning
        case lastScan = "last_scan"
        case fileCount = "file_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        enabled = (try? c.decodeIfPresent(Int.self, forKey: .enabled)) ?? 1
        lastScan = try? c.decodeIfPresent(String.self, forKey: .lastScan)
        fileCount = (try? c.decodeIfPresent(Int.self, forKey: .fileCount)) ?? 0
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .scanning) {
            scanning = b
        } else {
            scanning = ((try? c.decodeIfPresent(Int.self, forKey: .scanning)) ?? 0) != 0
        }
    }

    var displayName: String { (name?.isEmpty == false ? name! : "未命名") }
    var typeText: String { type == "series" ? "短剧" : "视频" }
}

/// 用户管理行
struct AdminUserRow: Identifiable, Equatable {
    var id: Int64
    var username: String
    var role: String
    var roleText: String { role == "admin" ? "管理员" : "用户" }
}

/// 单视频播放状态（含服务端进度，用于跨端续播）
struct VideoStatus: Decodable {
    var progress: Double
    var duration: Double
    var liked: Bool
    var favorited: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        progress = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? 0
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0
        liked = (try? c.decodeIfPresent(Bool.self, forKey: .liked)) ?? false
        favorited = (try? c.decodeIfPresent(Bool.self, forKey: .favorited)) ?? false
    }

    enum CodingKeys: String, CodingKey { case progress, duration, liked, favorited }
}

/// 剧集级最近观看进度（服务端，用于跨端跳集续播）
struct SeriesProgress: Decodable {
    var videoId: Int64
    var episodeIndex: Int?
    var progress: Double
    var duration: Double
    var title: String?
    var thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case progress, duration, title, thumbnail
        case videoId = "video_id"
        case episodeIndex = "episode_index"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = (try? c.decodeIfPresent(Int64.self, forKey: .videoId)) ?? 0
        episodeIndex = try? c.decodeIfPresent(Int.self, forKey: .episodeIndex)
        progress = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? 0
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
    }
}

struct SettingsPublic: Decodable {
    var allowRegister: Bool
    var requireLogin: Bool

    enum CodingKeys: String, CodingKey {
        case allowRegister = "allow_register"
        case requireLogin = "require_login"
    }
}
