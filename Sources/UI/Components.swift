import SwiftUI
import UIKit

/// 简易远程图片组件（替代 Coil），带内存缓存与占位
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]

    private init() { cache.countLimit = 240 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let running = tasks[url] { return await running.value }
        let task = Task<UIImage?, Never> { [weak self] in
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("QingShipin-iOS/1.3", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let img = UIImage(data: data) else { return nil }
            await MainActor.run { self?.cache.setObject(img, forKey: url as NSURL) }
            return img
        }
        tasks[url] = task
        let result = await task.value
        tasks[url] = nil
        return result
    }
}

/// 网络图片：失败时显示占位图标
struct RemoteImage: View {
    let url: URL?
    var placeholderIcon: String = "tv"
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var loadedKey: String?

    var body: some View {
        ZStack {
            Theme.surfaceLight
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(Theme.textSecondary.opacity(0.5))
            }
        }
        .clipped()
        .task(id: url?.absoluteString) {
            guard let url = url else { image = nil; return }
            if loadedKey == url.absoluteString, image != nil { return }
            if let hit = ImageCache.shared.cached(url) {
                image = hit
                loadedKey = url.absoluteString
                return
            }
            let fetched = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                image = fetched
                loadedKey = url.absoluteString
            }
        }
    }
}

/// 圆形头像占位（首字母）
struct AvatarView: View {
    let name: String
    var size: CGFloat = 60

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Theme.primary, Theme.primaryDark],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 通用加载指示器
struct LoadingIndicator: View {
    var size: CGFloat = 32
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(Theme.primary)
            .scaleEffect(size / 20)
    }
}

/// 空状态
struct EmptyStateView: View {
    var text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.textSecondary.opacity(0.55))
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 胶囊小标签（对应 bg_badge）
struct BadgeLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.primary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.primary.opacity(0.9), lineWidth: 0.6)
            )
    }
}

/// 页面顶部导航条（替代 MaterialToolbar）
struct NavBar: View {
    let title: String
    var onBack: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = trailing { trailing }
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
    }
}

extension UIApplication {
    /// 顶部安全区高度（播放器顶栏需要避开灵动岛/刘海）
    func keyWindowTopInset() -> CGFloat {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top
            ?? scene?.windows.first?.safeAreaInsets.top
            ?? 47
    }

    /// 底部安全区高度（iPhone 15 Pro Max 为 34pt）
    func keyWindowBottomInset() -> CGFloat {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom
            ?? scene?.windows.first?.safeAreaInsets.bottom
            ?? 34
    }
}