import Foundation

/// 本地持久化：对应安卓 SharedPreferences("qingshipin_prefs")
enum Prefs {
    private static let defaults = UserDefaults.standard

    static var lastUsername: String {
        get { defaults.string(forKey: "last_username") ?? "wangyunte" }
        set { defaults.set(newValue, forKey: "last_username") }
    }

    /// 某剧集最近一次播放的视频 id，供剧场封面续播兜底
    static func lastEpisode(seriesId: Int64) -> Int64? {
        let v = defaults.object(forKey: "last_episode_\(seriesId)") as? Int64
        return (v ?? 0) > 0 ? v : nil
    }

    static func setLastEpisode(seriesId: Int64, videoId: Int64) {
        guard seriesId > 0 else { return }
        defaults.set(videoId, forKey: "last_episode_\(seriesId)")
    }

    /// 记住的服务器地址历史（登录页快速切换）
    static var recentServers: [String] {
        get { defaults.stringArray(forKey: "recent_servers") ?? [] }
        set { defaults.set(Array(newValue.prefix(6)), forKey: "recent_servers") }
    }

    static func rememberServer(_ base: String) {
        let normalized = base.hasSuffix("/") ? base : base + "/"
        var list = recentServers.filter { $0 != normalized }
        list.insert(normalized, at: 0)
        recentServers = list
    }
}

/// 轻量 Toast：对应安卓 Toast，全局可调用
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()
    private var window: UIWindow?

    func show(_ message: String, duration: TimeInterval = 2.0) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let win = window ?? UIWindow(windowScene: scene)
        win.windowLevel = .alert + 1
        win.backgroundColor = .clear
        win.isUserInteractionEnabled = false
        win.rootViewController = UIViewController()
        win.rootViewController?.view.backgroundColor = .clear
        window = win
        if !win.isHidden { win.isHidden = false }

        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = UIView()
        box.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        box.layer.cornerRadius = 14
        box.layer.masksToBounds = true
        box.alpha = 0
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        win.addSubview(box)

        let maxWidth = min(UIScreen.main.bounds.width - 80, 420)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: win.centerXAnchor),
            box.bottomAnchor.constraint(equalTo: win.safeAreaLayoutGuide.bottomAnchor, constant: -110),
            box.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ])

        UIView.animate(withDuration: 0.2) { box.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.25, animations: { box.alpha = 0 }) { _ in
                box.removeFromSuperview()
            }
        }
    }
}

func toast(_ message: String) {
    Task { @MainActor in ToastCenter.shared.show(message) }
}
