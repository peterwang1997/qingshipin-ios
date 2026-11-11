import Foundation

// MARK: - 数据模型（对应轻视频后端 API 返回结构）

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable {
    let token: String?
    let user: User?
}

struct User: Decodable {
    let id: Int?
    let username: String?
    let role: String?
    let nickname: String?
    let avatar: String?
}

struct Series: Identifiable, Decodable {
    let id: Int
    let title: String?
    let cover: String?
    let totalEpisodes: Int?
    let updatedAt: String?
}

struct SeriesDetail: Decodable {
    let id: Int?
    let title: String?
    let cover: String?
    let episodes: [VideoItem]?
}

struct VideoItem: Identifiable, Decodable {
    let id: Int
    let title: String?
    let filename: String?
    let episodeIndex: Int?
    let seriesId: Int?
    let cover: String?
    let duration: Double?
}

struct FeedResponse: Decodable {
    let videos: [VideoItem]?
}

// MARK: - 观看进度（跨端同步）

/// 单视频播放状态（含服务端进度，用于续播）
struct VideoStatus: Decodable {
    let progress: Double?
    let duration: Double?
    let liked: Bool?
    let favorited: Bool?
}

/// 剧集级最近观看进度（服务端，用于跳集续播）
struct SeriesProgress: Decodable {
    let videoId: Int?
    let episodeIndex: Int?
    let progress: Double?
    let duration: Double?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case episodeIndex = "episode_index"
        case progress
        case duration
        case title
    }
}
