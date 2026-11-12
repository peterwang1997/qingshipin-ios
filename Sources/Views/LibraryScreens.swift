import SwiftUI

/// 通用视频卡片列表项（收藏/历史复用，对应 item_video.xml）
struct VideoRowCard: View {
    let item: VideoItem
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(url: ApiClient.shared.thumbnailURL(item.thumbnail ?? item.seriesCover ?? item.cover, width: 640),
                                placeholderIcon: "film")
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))

                    if let d = item.duration, d > 0 {
                        Text(Theme.clock(d))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
                            .padding(7)
                    }

                    if let ep = item.displayEpisode {
                        VStack {
                            HStack {
                                Text(ep)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.primary.opacity(0.9)))
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(7)
                    }
                }

                Text(item.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 9)
                    .padding(.horizontal, 12)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous)
                    .fill(Theme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))

            if let trailing = trailing { trailing }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let s = item.seriesTitle, !s.isEmpty {
            if let total = item.totalEpisodes, total > 0 {
                parts.append("\(s) · 全\(total)集")
            } else {
                parts.append(s)
            }
        } else if let ep = item.displayEpisode {
            parts.append(ep)
        } else if let lib = item.libraryName, !lib.isEmpty {
            parts.append(lib)
        }
        return parts.joined(separator: " · ")
    }
}

/// 收藏页：feed?type=favorites
struct FavoritesScreen: View {
    var onOpenPlayer: (PlaybackRequest) -> Void

    @State private var videos: [VideoItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if loading && videos.isEmpty {
                    LoadingIndicator(size: 34).frame(maxHeight: .infinity)
                } else if videos.isEmpty {
                    EmptyStateView(text: error ?? "暂无收藏")
                        .padding(.bottom, tabBottomInset())
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(videos) { v in
                                Button {
                                    open(v)
                                } label: {
                                    VideoRowCard(item: v)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, tabBottomInset() + 12)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task { if videos.isEmpty { await load() } }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("收藏")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(videos.isEmpty ? "喜欢的视频都会出现在这里" : "\(videos.count) 个视频")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surface))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            videos = try await ApiService.shared.feed(type: "favorites", limit: 100)
        } catch {
            self.error = "加载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        loading = false
    }

    private func open(_ item: VideoItem) {
        onOpenPlayer(PlaybackRequest(videoId: item.id,
                                     title: item.displayTitle,
                                     seriesId: item.seriesId ?? 0,
                                     resume: false))
    }

    private func tabBottomInset() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bottom = scene?.windows.first?.safeAreaInsets.bottom ?? 34
        return bottom + 49
    }
}

/// 观看历史页：feed/watched（含接口异常容错）
struct HistoryScreen: View {
    var onOpenPlayer: (PlaybackRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var videos: [VideoItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                NavBar(title: "观看历史", onBack: { dismiss() })
                if loading && videos.isEmpty {
                    LoadingIndicator(size: 34).frame(maxHeight: .infinity)
                } else if videos.isEmpty {
                    EmptyStateView(text: error ?? "暂无观看记录")
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(videos) { v in
                                Button {
                                    onOpenPlayer(PlaybackRequest(videoId: v.id,
                                                                 title: v.displayTitle,
                                                                 seriesId: v.seriesId ?? 0,
                                                                 resume: false))
                                } label: {
                                    VideoRowCard(item: v)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            videos = try await ApiService.shared.watched(limit: 100)
        } catch {
            self.error = "观看历史暂不可用：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        loading = false
    }
}
