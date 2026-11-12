import Foundation

/// 轻视频后端接口集合：路径与参数与安卓 ApiService 完全对齐
final class ApiService {
    static let shared = ApiService()
    private let client = ApiClient.shared
    private init() {}

    // MARK: - 认证

    func login(server: String, username: String, password: String) async throws -> LoginResponse {
        client.baseURL = server
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        return try await client.request(LoginResponse.self, path: "api/auth/login",
                                        method: "POST", body: body, authorized: false)
    }

    func me() async throws -> User {
        try await client.request(User.self, path: "api/auth/me")
    }

    // MARK: - 内容

    func feed(type: String, limit: Int = 40, exclude: String = "") async throws -> [VideoItem] {
        let resp = try await client.request(FeedResponse.self, path: "api/feed",
                                            query: ["limit": "\(limit)", "exclude": exclude, "type": type])
        return resp.videos ?? []
    }

    func watched(limit: Int = 100) async throws -> [VideoItem] {
        let resp = try await client.request(FeedResponse.self, path: "api/feed/watched",
                                            query: ["limit": "\(limit)"])
        return resp.videos ?? []
    }

    func series(page: Int = 1, limit: Int = 200) async throws -> [Series] {
        try await client.request([Series].self, path: "api/series",
                                 query: ["page": "\(page)", "limit": "\(limit)"])
    }

    func seriesDetail(_ id: Int64) async throws -> SeriesDetailResponse {
        try await client.request(SeriesDetailResponse.self, path: "api/series/\(id)/episodes")
    }

    func folders() async throws -> [Folder] {
        try await client.request([Folder].self, path: "api/folders")
    }

    func settings() async throws -> SettingsPublic {
        try await client.request(SettingsPublic.self, path: "api/settings/public", authorized: false)
    }

    /// 单视频状态（含服务端进度，用于跨端续播）
    func videoStatus(_ id: Int64) async throws -> VideoStatus {
        try await client.request(VideoStatus.self, path: "api/video/\(id)/status")
    }

    /// 剧集级最近观看进度；无历史返回 nil
    func seriesProgress(_ seriesId: Int64) async throws -> SeriesProgress? {
        do {
            let data = try await client.rawData(path: "api/history/series/\(seriesId)")
            let trimmed = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty || trimmed == "null" || trimmed == "{}" { return nil }
            let sp = try? JSONDecoder().decode(SeriesProgress.self, from: data)
            if let sp = sp, sp.videoId > 0 { return sp }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - 播放进度与互动

    /// 进度上报：后端字段为 progress/duration，单位秒
    func reportProgress(videoId: Int64, position: Double, duration: Double) async {
        let body: [String: Any] = ["progress": max(0, position), "duration": max(0, duration)]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        _ = try? await client.rawData(path: "api/video/\(videoId)/progress", method: "POST", body: data)
    }

    @discardableResult
    func toggleFavorite(_ id: Int64, favorite: Bool) async -> Bool {
        let data = (try? JSONSerialization.data(withJSONObject: ["favorite": favorite])) ?? Data()
        do {
            _ = try await client.rawData(path: "api/video/\(id)/favorite", method: "POST", body: data)
            return true
        } catch { return false }
    }

    @discardableResult
    func toggleLike(_ id: Int64, like: Bool) async -> Bool {
        let data = (try? JSONSerialization.data(withJSONObject: ["like": like])) ?? Data()
        do {
            _ = try await client.rawData(path: "api/video/\(id)/like", method: "POST", body: data)
            return true
        } catch { return false }
    }

    // MARK: - 管理后台

    func adminPaths() async throws -> [AdminPath] {
        try await client.request([AdminPath].self, path: "api/admin/paths")
    }

    func createPath(name: String, path: String, type: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "path": path, "type": type])
        _ = try await client.rawData(path: "api/admin/paths", method: "POST", body: body)
    }

    func deletePath(_ id: Int64) async throws {
        _ = try await client.rawData(path: "api/admin/paths/\(id)", method: "DELETE")
    }

    func scanPath(_ id: Int64) async throws {
        _ = try await client.rawData(path: "api/admin/paths/\(id)/scan", method: "POST")
    }

    func stopScan(_ id: Int64) async throws {
        _ = try await client.rawData(path: "api/admin/paths/\(id)/stop-scan", method: "POST")
    }

    func adminUsers() async throws -> [AdminUserRow] {
        let data = try await client.rawData(path: "api/admin/users")
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { row in
            guard let id = JSONAny.int64(row, "id") else { return nil }
            return AdminUserRow(id: id,
                                username: JSONAny.string(row, "username") ?? "?",
                                role: JSONAny.string(row, "role") ?? "user")
        }
    }

    func deleteUser(_ id: Int64) async throws {
        _ = try await client.rawData(path: "api/admin/users/\(id)", method: "DELETE")
    }

    func resetPassword(_ id: Int64, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["password": password])
        _ = try await client.rawData(path: "api/admin/users/\(id)/reset-password", method: "POST", body: body)
    }

    func adminStats() async throws -> [String: Any] {
        let data = try await client.rawData(path: "api/admin/stats")
        return JSONAny.decode(data)
    }
}
