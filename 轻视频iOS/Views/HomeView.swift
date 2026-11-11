import SwiftUI
import AVKit
import AVFoundation
import Combine

/// 首页信息流的播放状态：只有「当前这一页」允许播放，翻走的页立刻静音。
/// 不能依赖 onDisappear —— UIPageViewController 预加载的相邻页不会触发它，这正是「划走还在响」的原因。
final class FeedPlayback: ObservableObject {
    @Published var activeIndex: Int = 0
    /// 首页这个标签页是否正显示在屏幕上（切到「剧场」「历史」时要停声）
    @Published var isVisible: Bool = true
    /// 是否被全屏播放器 / 选集页盖住（盖住时也要停声）
    @Published var isCovered: Bool = false
}

/// 首页：全屏自动播放信息流（1 页 1 视频，上下滑动切换，自动播放）
struct HomeView: View {
    @ObservedObject var playback: FeedPlayback
    @State private var videos: [VideoItem] = []
    @State private var loading = true
    @State private var showDetail: VideoItem?
    @State private var detailAutoResume = true
    @State private var showPlayer: VideoItem?
    @State private var retry = 0

    private var currentBinding: Binding<Int> {
        Binding(get: { playback.activeIndex }, set: { playback.activeIndex = $0 })
    }

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
                VerticalPager(pageCount: videos.count, currentIndex: currentBinding) { index in
                    FeedPage(
                        item: videos[index],
                        index: index,
                        playback: playback,
                        onPlay: {
                            if (videos[index].seriesId ?? 0) > 0 {
                                // 剧集：点画面直接进播放器，接着上次那一集播（不在选集页停留）
                                detailAutoResume = true
                                showDetail = videos[index]
                            } else {
                                showPlayer = videos[index]
                            }
                        },
                        onSeries: {
                            if (videos[index].seriesId ?? 0) > 0 {
                                // 主动点「选集」时才停在选集页
                                detailAutoResume = false
                                showDetail = videos[index]
                            }
                        }
                    )
                }
                .ignoresSafeArea()
            }
        }
        .onAppear(perform: load)
        .statusBar(hidden: true)
        .fullScreenCover(item: $showDetail) { item in
            DetailView(seriesId: item.seriesId ?? 0, title: item.title ?? "", autoResume: detailAutoResume)
        }
        .fullScreenCover(item: $showPlayer) { item in
            PlayerHost(episodes: [item], startIndex: 0, title: item.title ?? "")
        }
        .onChange(of: overlayPresented) { presented in
            // 打开全屏播放器 / 选集页时停掉背景声音，关掉再恢复
            playback.isCovered = presented
        }
    }

    private var overlayPresented: Bool { showDetail != nil || showPlayer != nil }

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

/// 单页：铺满整屏自动播放，只有当前页出声；底部标题 + 操作按钮
struct FeedPage: View {
    let item: VideoItem
    let index: Int
    @ObservedObject var playback: FeedPlayback
    let onPlay: () -> Void
    let onSeries: () -> Void

    @State private var player: AVPlayer?

    private var isActive: Bool { playback.activeIndex == index && playback.isVisible && !playback.isCovered }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                // 用 AVPlayerLayer 而不是 VideoPlayer：没有系统控制条，并且能铺满整屏
                VideoLayerView(player: player, gravity: .resizeAspectFill)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            // 点击画面进全屏播放器（续播交给播放器内部的进度逻辑）
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onPlay)
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: UI.size(12)) {
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
                                Label("选集", systemImage: "list.bullet")
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
                .padding(.bottom, UI.size(72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.62)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .onAppear {
            if player == nil {
                // 自绘播放层不会像 VideoPlayer 那样自动激活音频会话，这里显式打开，否则可能没声音
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback,
                                         options: [.allowAirPlay, .allowBluetoothA2DP])
                try? session.setActive(true)
                player = AVPlayer(url: ApiClient.shared.streamUrl(item.id))
            }
            syncPlayback()
        }
        .onDisappear { player?.pause() }
        .onChange(of: playback.activeIndex) { _ in syncPlayback() }
        .onChange(of: playback.isVisible) { _ in syncPlayback() }
        .onChange(of: playback.isCovered) { _ in syncPlayback() }
    }

    private func syncPlayback() {
        if isActive {
            player?.play()
        } else {
            player?.pause()
        }
    }
}
