import SwiftUI
import AVKit

/// 首页：全屏自动播放信息流（1 页 1 视频，上下滑动切换，自动播放）
struct HomeView: View {
    @State private var videos: [VideoItem] = []
    @State private var current = 0
    @State private var loading = true
    @State private var showDetail: VideoItem?
    @State private var showPlayer: VideoItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if videos.isEmpty {
                if loading { ProgressView("加载中…").tint(.white) }
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
            PlayerHost(url: ApiClient.shared.streamUrl(item.id), title: item.title ?? "", videoId: item.id)
        }
    }

    private func load() {
        ApiClient.shared.feed { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let f) = result { videos = (f.videos ?? []).shuffled() }
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
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title ?? item.filename ?? "")
                        .font(.headline).foregroundColor(.white).lineLimit(2)
                    HStack(spacing: 12) {
                        Button(action: onPlay) {
                            Label("播放", systemImage: "play.circle.fill")
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(Color.orange).cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        if (item.seriesId ?? 0) > 0 {
                            Button(action: onSeries) {
                                Label("进剧集", systemImage: "list.bullet")
                                    .padding(.horizontal, 18).padding(.vertical, 8)
                                    .background(Color.white.opacity(0.25)).cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding()
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
