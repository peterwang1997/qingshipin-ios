import SwiftUI

/// 首页：全屏竖滑自动播放信息流（1页1视频，随机推荐，上下滑动切换）
struct HomeScreen: View {
    let isActive: Bool
    var onOpenPlayer: (PlaybackRequest) -> Void

    @State private var videos: [VideoItem] = []
    @State private var currentIndex: Int = 0
    @State private var loading = true
    @State private var loadError: String?
    @State private var dragOffset: CGFloat = 0
    @State private var flipping = false

    @StateObject private var engine = PlayerEngine()
    @State private var reporterTask: Task<Void, Never>?
    @State private var didSetup = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if videos.isEmpty {
                    if loading {
                        LoadingIndicator(size: 40)
                    } else if let err = loadError {
                        VStack(spacing: 14) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 34, weight: .light))
                                .foregroundColor(Theme.textSecondary)
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button {
                                Task { await load() }
                            } label: {
                                Text("重试")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 26)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(Theme.primary))
                            }
                        }
                    } else {
                        EmptyStateView(text: "暂无内容")
                    }
                } else {
                    feedLayer(size: geo.size)
                }

                // 顶部渐变 + 品牌标识
                VStack {
                    LinearGradient(colors: [Color.black.opacity(0.55), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .overlay(alignment: .top) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Theme.primary)
                                Text("轻视频")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                if videos.count > 1 {
                                    Text("\(min(currentIndex + 1, videos.count)) / \(videos.count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.14)))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // 右侧操作栏
                if let item = currentVideo {
                    HStack {
                        Spacer()
                        VStack(spacing: 18) {
                            actionButton(icon: "arrow.up.left.and.arrow.down.right",
                                         label: "播放") {
                                open(item)
                            }
                            actionButton(icon: "sparkles", label: "换一个") {
                                shuffleFeed()
                            }
                            actionButton(icon: "arrow.up", label: "上一个") {
                                step(-1)
                            }
                            actionButton(icon: "arrow.down", label: "下一个") {
                                step(1)
                            }
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 110)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .contentShape(Rectangle())
            .gesture(feedGesture(height: geo.size.height))
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            if !didSetup {
                didSetup = true
                if isActive { engine.play() } else { engine.pause() }
                startReporter()
            }
        }
        .task {
            if videos.isEmpty { await load() }
        }
        .onChange(of: isActive) { active in
            if active {
                engine.play()
            } else {
                engine.pause()
                reportProgressNow()
            }
        }
        .onDisappear {
            reportProgressNow()
            engine.pause()
            reporterTask?.cancel()
        }
        .onChange(of: engine.didEnd) { ended in
            if ended && videos.count > 1 { step(1) }
        }
    }

    // MARK: - 信息流层

    private func feedLayer(size: CGSize) -> some View {
        ZStack {
            PlayerLayerView(player: engine.player, gravity: .resizeAspect)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            if engine.isBuffering || engine.failed {
                VStack(spacing: 10) {
                    if engine.failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Theme.accent)
                        Text("当前视频无法播放，向上滑动切换")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    } else {
                        LoadingIndicator(size: 36)
                    }
                }
            }

            if dragOffset != 0 {
                Color.black.opacity(min(0.55, abs(dragOffset) / max(size.height, 1) * 0.9))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()
                bottomInfo
            }
        }
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = currentVideo {
                Text(item.displayTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitleText(item).isEmpty {
                    Text(subtitleText(item))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 5)
                        .lineLimit(1)
                }

                if !metaText(item).isEmpty {
                    Text(metaText(item))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 3)
                        .lineLimit(1)
                }

                HStack(spacing: 14) {
                    Label {
                        Text(timeText)
                            .font(.system(size: 11))
                    } icon: {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.72))

                    Label {
                        Text(engine.isPlaying ? "播放中" : "已暂停")
                            .font(.system(size: 11))
                    } icon: {
                        Image(systemName: engine.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.72))
                }
                .padding(.top, 10)

                if videos.count > 1 {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 44, height: 3)
                            .overlay(alignment: .top) {
                                GeometryReader { g in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: computedProgress * g.size.width, height: 3)
                                }
                            }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 78)
        .padding(.bottom, tabSafeBottom() + 26)
        .padding(.top, 90)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.35), Color.black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
        )
        .contentShape(Rectangle())
        .onTapGesture { engine.togglePlayPause() }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.38))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 手势

    private func feedGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !flipping, videos.count > 1 else { return }
                let dy = value.translation.height
                let dx = value.translation.width
                if abs(dy) > abs(dx) {
                    // 阻尼，越滑越沉
                    dragOffset = dy * 0.45
                }
            }
            .onEnded { value in
                guard !flipping, videos.count > 1 else { dragOffset = 0; return }
                let dy = value.translation.height
                let dx = value.translation.width
                let threshold = min(120, height * 0.16)
                if abs(dy) > abs(dx), abs(dy) > threshold {
                    if dy < 0 { step(1) } else { step(-1) }
                }
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            }
    }

    // MARK: - 数据

    private var currentVideo: VideoItem? {
        guard currentIndex >= 0, currentIndex < videos.count else { return videos.first }
        return videos[currentIndex]
    }

    private var timeText: String {
        guard engine.duration > 0 else { return "--:--" }
        return "\(String.clockText(engine.currentTime)) / \(String.clockText(engine.duration))"
    }

    private var computedProgress: CGFloat {
        guard engine.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, engine.currentTime / engine.duration)))
    }

    private func subtitleText(_ item: VideoItem) -> String {
        var parts: [String] = []
        if let s = item.seriesTitle, !s.isEmpty { parts.append(s) }
        if let ep = item.displayEpisode { parts.append(ep) }
        return parts.joined(separator: " · ")
    }

    private func metaText(_ item: VideoItem) -> String {
        var parts: [String] = []
        if let lib = item.libraryName, !lib.isEmpty { parts.append(lib) }
        if let total = item.totalEpisodes, total > 0 { parts.append("共\(total)集") }
        if parts.isEmpty, let f = item.format, !f.isEmpty { parts.append(f.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let list = try await ApiService.shared.feed(type: "video", limit: 40)
            videos = list.shuffled()
            currentIndex = 0
            loading = false
            if let first = videos.first {
                playCurrent(first)
            } else {
                engine.detach()
            }
        } catch {
            loading = false
            loadError = "加载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func playCurrent(_ item: VideoItem) {
        engine.isBuffering = true
        engine.load(url: ApiClient.shared.streamURL(videoId: item.id), autoplay: isActive)
        Prefs.setLastEpisode(seriesId: item.seriesId ?? 0, videoId: item.id)
        if !isActive { engine.pause() }
    }

    private func step(_ delta: Int) {
        guard !videos.isEmpty else { return }
        let next = (currentIndex + delta + videos.count) % videos.count
        guard next != currentIndex else { return }
        reportProgressNow()
        flipping = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let direction: CGFloat = delta > 0 ? -1 : 1
        let h = max(Screen.height, 600)
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = direction * h * 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            currentIndex = next
            if let v = videos[safe: next] { playCurrent(v) }
            dragOffset = direction * -h * 0.9
            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            flipping = false
        }
    }

    private func shuffleFeed() {
        guard videos.count > 1 else { return }
        videos.shuffle()
        currentIndex = 0
        if let v = videos.first { playCurrent(v) }
        toast("已换一批推荐")
    }

    private func open(_ item: VideoItem) {
        reportProgressNow()
        let sid = item.seriesId ?? 0
        Task { @MainActor in
            var vid = item.id
            if sid > 0, let sp = try? await ApiService.shared.seriesProgress(sid), sp.videoId > 0 {
                vid = sp.videoId
            }
            onOpenPlayer(PlaybackRequest(videoId: vid,
                                         title: item.displayTitle,
                                         seriesId: sid,
                                         resume: sid > 0))
        }
    }

    // MARK: - 进度上报（每 10 秒，对应安卓 startProgressReporter）

    private func startReporter() {
        reporterTask?.cancel()
        reporterTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                reportProgressNow()
            }
        }
    }

    private func reportProgressNow() {
        guard let item = currentVideo else { return }
        let pos = engine.currentTime
        let dur = engine.duration
        guard pos > 0, dur > 0 else { return }
        Task { await ApiService.shared.reportProgress(videoId: item.id, position: pos, duration: dur) }
    }

    private func tabSafeBottom() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first?.safeAreaInsets.bottom ?? 34
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
