import Foundation

/// 本机记录的剧集播放位置。
/// 服务端 `/api/history/series/{id}` 的返回字段并不稳定（可能只给行数据、也可能不带 video_id），
/// 所以续播以本机记录为主、服务端为兜底：这样即使接口拿不到字段，也一定记得上次看到第几集。
enum ProgressStore {

    private static func key(_ seriesId: Int) -> String { "qs_last_series_\(seriesId)" }

    /// 记录某剧最近播放的那一集
    static func saveEpisode(_ videoId: Int, seriesId: Int) {
        guard seriesId > 0, videoId > 0 else { return }
        UserDefaults.standard.set(videoId, forKey: key(seriesId))
    }

    /// 读取某剧最近播放的那一集 videoId
    static func lastEpisode(_ seriesId: Int) -> Int? {
        let v = UserDefaults.standard.integer(forKey: key(seriesId))
        return v > 0 ? v : nil
    }

    /// 在剧集列表里定位上次那一集的序号
    static func lastEpisodeIndex(seriesId: Int, episodes: [VideoItem]) -> Int? {
        guard let vid = lastEpisode(seriesId) else { return nil }
        return episodes.firstIndex { $0.id == vid }
    }
}
