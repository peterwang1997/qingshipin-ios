import SwiftUI
import AVKit

/// 首页：全屏自动播放信息流（1 页 1 视频，上下滑动切换，自动播放）
struct HomeView: View {
    @State private var videos: [VideoItem] = []
    @State private var current = 0
    @State private var loading = true
    @State private var showDetail: VideoItem?
    @State private var showPlayer: VideoItem?
    @State private var retry = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if videos.isEmpty {
                if loading {
                    ProgressView("加载中…")
                        .tint(.white)
                        .font(.system(size: UI.note))
                }
            } else {
                VerticalPager(pageCount: videos.count, currentIndex: $current) { index in
                    FeedPage(
                        item: videos[index],
                        onPlay: { showPlayer = videos[index] },
                        onSeries: { if (videos[index].seriesId ?? 0) > 0 { showDetail = videos[index] } }
                    )
                }
                .ignoresSafeArea()
            }
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $showDetail) { item in
            DetailView(seriesId: item.seriesId ?? 0, title: item.title ?? "")
        }
        .fullScreenCover(item: $showPlayer) { item in
            PlayerHost(episodes: [item], startIndex: 0, title: item.title ?? "")
        }
    }

    private func load() {
        ApiClient.shared.feed { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let f) = result {
                    videos = (f.videos ?? []).shuffled()
                } else if retry < 1 {
                    // 首个请求可能落在网络环境还没判定完的时刻，失败后自动重试一次
                    retry += 1
                    loading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { load() }
                }
            }
        }
    }
}

/// 单页：出现自动播放，离开自动暂停；底部标题 + 操作按钮
struct FeedPage: View {
    let item: VideoItem
    let onPlay: () -> Void
    let onSeries: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: UI.size(13)) {
                    Text(item.title ?? item.filename ?? "")
                        .font(.system(size: UI.headline, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: UI.size(12)) {
                        Button(action: onPlay) {
                            Label("播放", systemImage: "play.circle.fill")
                                .font(.system(size: UI.note))
                                .padding(.horizontal, UI.size(20))
                                .padding(.vertical, UI.size(10))
                                .background(Color.orange)
                                .cornerRadius(UI.size(10))
                                .foregroundColor(.white)
                        }
                        if (item.seriesId ?? 0) > 0 {
                            Button(action: onSeries) {
                                Label("进剧集", systemImage: "list.bullet")
                                    .font(.system(size: UI.note))
                                    .padding(.horizontal, UI.size(20))
                                    .padding(.vertical, UI.size(10))
                                    .background(Color.white.opacity(0.25))
                                    .cornerRadius(UI.size(10))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, UI.hPad)
                .padding(.top, UI.size(14))
                .padding(.bottom, UI.size(18))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.5))
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: ApiClient.shared.streamUrl(item.id))
            }
            player?.play()
        }
        .onDisappear { player?.pause() }
    }
}
