import Foundation
import UIKit

// MARK: - 内网 / 外网地址
enum ServerEnv: String, CaseIterable {
    case internalNet = "http://192.168.0.138:8092"
    case externalNet = "http://wym.peterw.top:8092"

    /// 界面上展示的名字
    var title: String {
        switch self {
        case .internalNet: return "内网（家里）"
        case .externalNet: return "外网（远程）"
        }
    }

    static func match(_ url: String) -> ServerEnv? {
        ServerEnv.allCases.first { url.hasPrefix($0.rawValue) }
    }
}

// MARK: - 网络层（URLSession，无第三方依赖）
final class ApiClient {
    static let shared = ApiClient()
    private init() {}

    private let session = URLSession(configuration: .ephemeral)

    var baseUrl = ServerEnv.internalNet.rawValue
    var token = ""
    private(set) var user: User?

    /// 当前实际使用的环境
    private(set) var currentEnv: ServerEnv = .internalNet

    // MARK: - 内外网自动识别

    /// 串行探测：先试内网（1.5 秒超时），不通再试外网（3.5 秒超时）。
    /// 两个都不通时沿用上次可用的地址，避免把用户已经能用的配置改坏。
    func refreshEnvironment(completion: ((ServerEnv) -> Void)? = nil) {
        let fallback = ServerEnv.match(baseUrl) ?? UserDefaults.standard
            .string(forKey: "qs_server").flatMap(ServerEnv.match) ?? .internalNet

        probe(ServerEnv.internalNet.rawValue, timeout: 1.5) { [weak self] okInternal in
            guard let self = self else { return }
            if okInternal {
                self.apply(.internalNet, completion: completion)
                return
            }
            self.probe(ServerEnv.externalNet.rawValue, timeout: 3.5) { [weak self] okExternal in
                guard let self = self else { return }
                self.apply(okExternal ? .externalNet : fallback, completion: completion)
            }
        }
    }

    /// 手动指定环境
    func switchTo(_ env: ServerEnv) {
        apply(env, completion: nil)
    }

    private func apply(_ env: ServerEnv, completion: ((ServerEnv) -> Void)?) {
        currentEnv = env
        baseUrl = env.rawValue
        UserDefaults.standard.set(env.rawValue, forKey: "qs_server")
        DispatchQueue.main.async { completion?(env) }
    }

    private func probe(_ base: String, timeout: TimeInterval, done: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(base)/api/series?page=1&limit=1") else { done(false); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout

        var finished = false
        let lock = NSLock()
        func finish(_ ok: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            done(ok)
        }

        session.dataTask(with: req) { _, resp, err in
            if err != nil { finish(false); return }
            if let h = resp as? HTTPURLResponse {
                finish(h.statusCode < 500)
            } else {
                finish(false)
            }
        }.resume()

        // 兜底：URLSession 的请求超时不一定准时，这里再加一道保险
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 0.6) {
            finish(false)
        }
    }

    // MARK: - 认证
    func login(username: String, password: String, completion: @escaping (Result<LoginResponse, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "\(baseUrl)/api/auth/login")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(LoginRequest(username: username, password: password))
        session.dataTask(with: req) { data, _, err in
            guard let data = data, err == nil else {
                completion(.failure(err ?? NSError(domain: "login", code: -1)))
                return
            }
            do {
                let r = try JSONDecoder().decode(LoginResponse.self, from: data)
                if let t = r.token { self.token = t; self.user = r.user }
                completion(.success(r))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    // MARK: - 通用 GET
    func get<T: Decodable>(_ path: String, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: baseUrl + path) else {
            completion(.failure(NSError(domain: "url", code: -1))); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { data, _, err in
            guard let data = data, err == nil else {
                completion(.failure(err ?? NSError(domain: "get", code: -1))); return
            }
            do { completion(.success(try JSONDecoder().decode(T.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    // MARK: - 业务接口
    func series(page: Int = 1, limit: Int = 40, completion: @escaping (Result<[Series], Error>) -> Void) {
        get("/api/series?page=\(page)&limit=\(limit)", completion: completion)
    }

    func seriesDetail(_ id: Int, completion: @escaping (Result<SeriesDetail, Error>) -> Void) {
        get("/api/series/\(id)/episodes", completion: completion)
    }

    func feed(type: String = "video", limit: Int = 40, completion: @escaping (Result<FeedResponse, Error>) -> Void) {
        get("/api/feed?limit=\(limit)&type=\(type)&exclude=", completion: completion)
    }

    func watched(limit: Int = 40, completion: @escaping (Result<FeedResponse, Error>) -> Void) {
        get("/api/feed/watched?limit=\(limit)", completion: completion)
    }

    // MARK: - 播放地址 / 缩略图
    func streamUrl(_ id: Int) -> URL {
        let s = "\(baseUrl)/stream/\(id)?token=\(token)&codec_hevc=1&codec_av1=1&codec_vp9=1&codec_ac3=0&codec_eac3=0&codec_dts=0"
        return URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)!
    }

    func thumbnail(_ name: String?) -> URL? {
        guard let name = name, !name.isEmpty else { return nil }
        let s = "\(baseUrl)/thumbnails/\(name)?token=\(token)"
        return URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)
    }

    // MARK: - 进度上报（字段 progress/duration，单位秒）
    func reportProgress(videoId: Int, position: Double, duration: Double) {
        guard let url = URL(string: "\(baseUrl)/api/video/\(videoId)/progress") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(["progress": position, "duration": duration])
        session.dataTask(with: req).resume()
    }

    // MARK: - 跨端进度查询（续播）
    /// 单视频播放状态（含服务端进度）
    func videoStatus(id: Int, completion: @escaping (Result<VideoStatus, Error>) -> Void) {
        get("/api/video/\(id)/status", completion: completion)
    }

    /// 剧集级最近观看进度；无历史时返回 nil
    func seriesProgress(seriesId: Int, completion: @escaping (Result<SeriesProgress?, Error>) -> Void) {
        guard let url = URL(string: "\(baseUrl)/api/history/series/\(seriesId)") else {
            completion(.success(nil)); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { data, _, err in
            guard let data = data, err == nil else { completion(.success(nil)); return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                guard obj["video_id"] != nil, obj["video_id"] is Int || obj["video_id"] is Double else {
                    completion(.success(nil)); return
                }
                completion(.success(try? JSONDecoder().decode(SeriesProgress.self, from: data)))
            } else {
                completion(.success(nil))
            }
        }.resume()
    }
}
