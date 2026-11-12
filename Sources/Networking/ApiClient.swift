import Foundation

/// 网络与鉴权状态：对应安卓 ApiClient（服务器地址、JWT、候选地址探测）
final class ApiClient {
    static let shared = ApiClient()

    /// 内网优先、外网兜底
    /// 注意：外网必须用 wym.peterw.top（根域 peterw.top 没有 A 记录，解析会直接失败）
    static let serverCandidates = [
        "http://192.168.0.138:8092/",
        "http://wym.peterw.top:8092/"
    ]
    static let defaultBase = "http://192.168.0.138:8092/"

    private let defaults = UserDefaults.standard
    private let keyBase = "server_base"
    private let keyToken = "token"

    private let session: URLSession
    private let probeSession: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)

        let probe = URLSessionConfiguration.ephemeral
        // 请求级 timeoutInterval 只能小于该值才生效，这里放宽到 10 秒，
        // 具体单次超时由 probe() 里的 req.timeoutInterval 控制（内网 3s / 外网 8s）
        probe.timeoutIntervalForRequest = 10
        probe.timeoutIntervalForResource = 12
        probe.waitsForConnectivity = false
        probe.requestCachePolicy = .reloadIgnoringLocalCacheData
        probeSession = URLSession(configuration: probe)
    }

    // MARK: - 服务器地址

    var baseURL: String {
        get {
            let raw = defaults.string(forKey: keyBase) ?? Self.defaultBase
            return Self.normalize(raw)
        }
        set { defaults.set(Self.normalize(newValue), forKey: keyBase) }
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = Self.defaultBase }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        if !s.hasSuffix("/") { s += "/" }
        return s
    }

    // MARK: - 令牌

    var token: String? {
        get { defaults.string(forKey: keyToken) }
        set {
            if let v = newValue, !v.isEmpty {
                defaults.set(v, forKey: keyToken)
            } else {
                defaults.removeObject(forKey: keyToken)
            }
        }
    }

    var isLoggedIn: Bool { !(token ?? "").isEmpty }

    func clearAuth() { token = nil }

    // MARK: - 服务器探测

    /// 探测结果：成功地址 + 每个候选的失败原因（便于定位）
    struct ProbeResult {
        var best: String?
        var failures: [String]
    }

    /// 并行探测所有候选地址，按优先级返回第一个可用的（内网优先）
    /// 并行而非串行：外网在移动网络下握手较慢，串行会让启动等待翻倍
    func detectBestBaseDetailed() async -> ProbeResult {
        var failures: [String] = []

        let results = await withTaskGroup(of: (Int, String, Bool).self) { group -> [(Int, String, Bool)] in
            for (index, base) in Self.serverCandidates.enumerated() {
                group.addTask { (index, base, await self.probe(base)) }
            }
            var collected: [(Int, String, Bool)] = []
            for await item in group { collected.append(item) }
            return collected
        }

        let ordered = results.sorted { $0.0 < $1.0 }
        for (_, base, ok) in ordered {
            if ok { return ProbeResult(best: base, failures: failures) }
            failures.append("\(base) 不可达")
        }
        return ProbeResult(best: nil, failures: failures)
    }

    func detectBestBase() async -> String? {
        await detectBestBaseDetailed().best
    }

    private func probe(_ base: String) async -> Bool {
        guard let url = URL(string: base + "api/settings/public") else { return false }
        var req = URLRequest(url: url)
        // 内网通常秒回；外网在 4G/5G 下握手可能超过 3 秒，给足 8 秒
        req.timeoutInterval = base.contains("192.168.") ? 3.0 : 8.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("QingShipin-iOS/1.4", forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await probeSession.data(for: req)
            if let http = resp as? HTTPURLResponse {
                // 200 与 401（需要登录）都说明服务端活着
                return (200...399).contains(http.statusCode) || http.statusCode == 401
            }
            return false
        } catch {
            return false
        }
    }

    /// 自动检测并切换服务器地址
    @discardableResult
    func autoDetectBase() async -> String {
        if let best = await detectBestBase() {
            baseURL = best
            return best
        }
        return baseURL
    }

    // MARK: - 请求

    enum ApiError: LocalizedError {
        case badURL
        case http(Int, String?)
        case decoding(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "服务器地址无效"
            case let .http(code, msg):
                if let msg = msg, !msg.isEmpty { return msg }
                if code == 401 { return "登录已过期，请重新登录" }
                return "服务端返回 \(code)"
            case let .decoding(msg): return "数据解析失败：\(msg)"
            case let .network(msg): return msg
            }
        }
    }

    private func makeRequest(path: String, method: String, query: [String: String] = [:],
                            body: Data? = nil, authorized: Bool = true) throws -> URLRequest {
        let base = baseURL
        var comps = URLComponents(string: base + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw ApiError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("QingShipin-iOS/1.3", forHTTPHeaderField: "User-Agent")
        if let body = body {
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if authorized, let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func rawData(path: String, method: String = "GET", query: [String: String] = [:],
                 body: Data? = nil, authorized: Bool = true) async throws -> Data {
        let req = try makeRequest(path: path, method: method, query: query, body: body, authorized: authorized)
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.network("无响应") }
            if !(200...299).contains(http.statusCode) {
                throw ApiError.http(http.statusCode, Self.errorMessage(from: data))
            }
            return data
        } catch let e as ApiError {
            throw e
        } catch let e as URLError {
            throw ApiError.network(Self.message(for: e))
        } catch {
            throw ApiError.network(error.localizedDescription)
        }
    }

    func request<T: Decodable>(_ type: T.Type, path: String, method: String = "GET",
                               query: [String: String] = [:], body: Data? = nil,
                               authorized: Bool = true) async throws -> T {
        let data = try await rawData(path: path, method: method, query: query, body: body, authorized: authorized)
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ApiError.decoding(error.localizedDescription)
        }
    }

    static func errorMessage(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "msg", "detail"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text = text, !text.isEmpty, text.count < 200, !text.hasPrefix("<") { return text }
        return nil
    }

    static func message(for error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost:
            return "无法连接服务器，请检查地址与网络"
        case .timedOut:
            return "连接超时，请检查服务器地址"
        case .notConnectedToInternet:
            return "当前无网络连接"
        case .networkConnectionLost:
            return "网络中断，请重试"
        case .appTransportSecurityRequiresSecureConnection:
            return "系统拦截了明文连接"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "HTTPS 证书校验失败"
        default:
            return error.localizedDescription
        }
    }

    // MARK: - 媒体地址

    /// 播放流地址：带鉴权 token 与解码协商参数（安卓 streamUrl 同款）
    func streamURL(videoId: Int64) -> String {
        let t = token ?? ""
        return "\(baseURL)stream/\(videoId)?token=\(t)&codec_hevc=1&codec_av1=1&codec_vp9=1&codec_ac3=0&codec_eac3=0&codec_dts=0"
    }

    /// 缩略图/封面地址
    func thumbnailURL(_ name: String?, width: Int? = nil) -> URL? {
        guard var n = name, !n.isEmpty else { return nil }
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("http://") || n.hasPrefix("https://") { return URL(string: n) }
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let t = (token ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var s = "\(baseURL)thumbnails/\(n)?token=\(t)"
        if let w = width { s += "&w=\(w)" }
        return URL(string: s)
    }

    /// 绝对地址（后端可能返回 /xxx 相对路径）
    func absoluteURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") { return URL(string: p) }
        return URL(string: baseURL + p.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// 后端大量接口返回裸 Map，这里统一解析为 [String: Any]
enum JSONAny {
    static func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let s = dict[key] as? String { return s }
        if let n = dict[key] as? NSNumber { return n.stringValue }
        return nil
    }
    static func int64(_ dict: [String: Any], _ key: String) -> Int64? {
        if let n = dict[key] as? NSNumber { return n.int64Value }
        if let s = dict[key] as? String { return Int64(s) }
        return nil
    }
    static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let n = dict[key] as? NSNumber { return n.intValue }
        if let s = dict[key] as? String { return Int(s) }
        return nil
    }
    static func bool(_ dict: [String: Any], _ key: String) -> Bool {
        if let b = dict[key] as? Bool { return b }
        if let n = dict[key] as? NSNumber { return n.intValue != 0 }
        if let s = dict[key] as? String { return s == "true" || s == "1" }
        return false
    }
}
