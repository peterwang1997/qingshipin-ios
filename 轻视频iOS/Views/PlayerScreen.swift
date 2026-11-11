import SwiftUI
import UIKit
import AVKit
import AVFoundation

// MARK: - 播放器宿主（由各页面调用）

/// 全屏播放器：传入剧集列表与起始集，支持换集、自动连播、投屏、续播
struct PlayerHost: View {
    let episodes: [VideoItem]
    let startIndex: Int
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int

    init(episodes: [VideoItem], startIndex: Int = 0, title: String) {
        self.episodes = episodes
        self.startIndex = startIndex
        self.title = title
        let safe = max(0, min(startIndex, max(0, episodes.count - 1)))
        _index = State(initialValue: safe)
    }

    var body: some View {
        PlayerScreen(episodes: episodes, index: $index, fallbackTitle: title, onClose: { dismiss() })
    }
}

// MARK: - 播放器内核

final class PlayerEngine: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1
    @Published var loaded = false

    var onEpisodeEnd: (() -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var videoId: Int = 0
    private var lastReport: Double = 0

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            // 每 10 秒上报一次进度
            if self.currentTime - self.lastReport >= 10, self.videoId > 0, self.duration > 0 {
                self.lastReport = self.currentTime
                ApiClient.shared.reportProgress(videoId: self.videoId, position: self.currentTime, duration: self.duration)
            }
            self.isPlaying = self.player.rate > 0
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // 收尾上报
            if self.videoId > 0, self.duration > 0 {
                ApiClient.shared.reportProgress(videoId: self.videoId, position: self.duration, duration: self.duration)
            }
            self.onEpisodeEnd?()
        }
    }

    deinit {
        if let o = timeObserver { player.removeTimeObserver(o) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
    }

    /// 加载一集；videoId 用于续播与进度上报
    func load(url: URL, videoId: Int) {
        self.videoId = videoId
        self.lastReport = 0
        self.currentTime = 0
        self.duration = 0
        self.loaded = false
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.rate = rate

        // 跨端续播
        ApiClient.shared.videoStatus(id: videoId) { [weak self] result in
            guard let self, case .success(let st) = result,
                  let p = st.progress, let d = st.duration, p > 8, d > 0, p < d * 0.97 else {
                DispatchQueue.main.async { self?.loaded = true; self?.player.play() }
                return
            }
            let target = CMTime(seconds: p, preferredTimescale: 600)
            DispatchQueue.main.async {
                self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    self.loaded = true
                    self.player.play()
                }
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        let d = duration > 0 ? duration : seconds
        let target = max(0, min(seconds, d))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        if videoId > 0, duration > 0 {
            ApiClient.shared.reportProgress(videoId: videoId, position: target, duration: duration)
        }
    }

    func setRate(_ r: Float) {
        rate = r
        if player.rate > 0 { player.rate = r }
    }
}

// MARK: - AVPlayerLayer 封装

final class PlayerLayerContainer: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainer {
        let v = PlayerLayerContainer()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ uiView: PlayerLayerContainer, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - 播放器界面

struct PlayerScreen: View {
    let episodes: [VideoItem]
    @Binding var index: Int
    let fallbackTitle: String
    let onClose: () -> Void

    @StateObject private var engine = PlayerEngine()

    @State private var controlsVisible = true
    @State private var autoHide: Task<Void, Never>? = nil

    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var seekPreview: Double? = nil
    @State private var longPressing = false

    @State private var showEpisodeSheet = false
    @State private var showCastSheet = false
    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private enum DragMode { case none, horizontal, vertical }

    private var currentEpisode: VideoItem? {
        guard episodes.indices.contains(index) else { return nil }
        return episodes[index]
    }

    private var displayTitle: String {
        let t = currentEpisode?.title ?? fallbackTitle
        if episodes.count > 1 {
            return "\(t)（第 \(index + 1) / \(episodes.count) 集）"
        }
        return t
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoLayerView(player: engine.player)
                .ignoresSafeArea()

            // 手势层
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                .onLongPressGesture(minimumDuration: 0.28, pressing: { pressing in
                    longPressing = pressing
                    if pressing {
                        engine.setRate(2)
                        showToast("2× 倍速播放中")
                    } else {
                        engine.setRate(1)
                        hideToast()
                    }
                }, perform: {})
                .gesture(dragGesture)
                .ignoresSafeArea()

            if engine.loaded == false {
                ProgressView().tint(.white)
            }

            // 顶栏
            if controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                .transition(.opacity)
            }

            // 底部控制条
            if controlsVisible {
                VStack {
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }

            // 拖动进度预览
            if let p = seekPreview {
                VStack(spacing: 6) {
                    Text(timeText(p))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("松手跳转")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(20)
                .background(Color.black.opacity(0.65))
                .cornerRadius(14)
            }

            // 上下滑换集提示
            if dragMode == .vertical {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.up")
                        Text("上下滑动切换集数")
                        Image(systemName: "chevron.down")
                    }
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                    Spacer().frame(height: 90)
                }
            }

            // 轻提示
            if let t = toast {
                VStack {
                    Spacer().frame(height: 60)
                    Text(t)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    Spacer()
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            engine.onEpisodeEnd = { goNext(auto: true) }
            loadCurrent()
            scheduleAutoHide()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            engine.pause()
            autoHide?.cancel()
            toastTask?.cancel()
        }
        .sheet(isPresented: $showEpisodeSheet) {
            EpisodeMatrixView(episodes: episodes, currentIndex: index) { idx in
                showEpisodeSheet = false
                switchTo(idx)
            }
        }
        .sheet(isPresented: $showCastSheet) {
            CastSheet(url: ApiClient.shared.streamUrl(episodes.indices.contains(index) ? episodes[index].id : 0),
                      title: displayTitle,
                      onCasted: { engine.pause() })
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }
            Text(displayTitle)
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            if episodes.count > 1 {
                Button { showEpisodeSheet = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
            }
            Button { showCastSheet = true } label: {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: 底部控制条

    private var bottomBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.orange)
                        .frame(width: max(0, CGFloat(engine.duration > 0 ? engine.currentTime / engine.duration : 0)) * geo.size.width, height: 4)
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard engine.duration > 0 else { return }
                            let ratio = min(max(v.location.x / geo.size.width, 0), 1)
                            seekPreview = ratio * engine.duration
                        }
                        .onEnded { v in
                            guard engine.duration > 0 else { return }
                            let ratio = min(max(v.location.x / geo.size.width, 0), 1)
                            engine.seek(to: ratio * engine.duration)
                            seekPreview = nil
                        }
                )
            }
            .frame(height: 18)

            HStack {
                Text(timeText(engine.currentTime))
                    .font(.caption).foregroundColor(.white.opacity(0.85))
                Spacer()
                Button {
                    engine.isPlaying ? engine.pause() : engine.play()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text(timeText(engine.duration))
                    .font(.caption).foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 22)
            .onChanged { v in
                if dragMode == .none {
                    let horizontal = abs(v.translation.width) > abs(v.translation.height)
                    dragMode = horizontal ? .horizontal : .vertical
                    dragStartTime = engine.currentTime
                    controlsVisible = true
                }
                if dragMode == .horizontal, engine.duration > 0 {
                    // 每个屏幕宽度约对应 90 秒
                    let secondsPerWidth = 90.0
                    let delta = Double(v.translation.width / 320) * secondsPerWidth
                    let target = min(max(dragStartTime + delta, 0), engine.duration)
                    seekPreview = target
                }
            }
            .onEnded { v in
                if dragMode == .horizontal, let t = seekPreview {
                    engine.seek(to: t)
                    seekPreview = nil
                } else if dragMode == .vertical {
                    if v.translation.height < -80 { goNext(auto: false) }
                    else if v.translation.height > 80 { goPrev() }
                }
                dragMode = .none
                scheduleAutoHide()
            }
    }

    // MARK: 换集 / 连播

    private func loadCurrent() {
        guard let e = currentEpisode else { return }
        engine.load(url: ApiClient.shared.streamUrl(e.id), videoId: e.id)
    }

    private func switchTo(_ idx: Int) {
        guard episodes.indices.contains(idx) else { return }
        index = idx
        loadCurrent()
        showToast("已切换到第 \(idx + 1) 集")
    }

    private func goNext(auto: Bool) {
        guard index + 1 < episodes.count else {
            if auto { showToast("已是最后一集") }
            return
        }
        index += 1
        loadCurrent()
        if auto { showToast("自动连播：第 \(index + 1) 集") }
    }

    private func goPrev() {
        guard index - 1 >= 0 else {
            showToast("已是第一集")
            return
        }
        index -= 1
        loadCurrent()
        showToast("已切换到第 \(index + 1) 集")
    }

    // MARK: 控制条显隐

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() } else { autoHide?.cancel() }
    }

    private func scheduleAutoHide() {
        autoHide?.cancel()
        autoHide = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
                }
            }
        }
    }

    private func showToast(_ s: String) {
        toastTask?.cancel()
        toast = s
        if s.contains("倍速") { return }   // 长按期间保持显示
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { await MainActor.run { toast = nil } }
        }
    }

    private func hideToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func timeText(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - 选集矩阵（只显示集数数字）

struct EpisodeMatrixView: View {
    let episodes: [VideoItem]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                            Button {
                                onSelect(i)
                            } label: {
                                Text(String(format: "%03d", e.episodeIndex ?? (i + 1)))
                                    .font(.system(size: 14, weight: i == currentIndex ? .bold : .regular))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(i == currentIndex ? Color.orange : Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}
