import SwiftUI
import AVFoundation

/// 播放器：内置播放 + 全屏 + DLNA 投屏
/// 手势与安卓完全一致：
///  - 左右滑动拖动进度
///  - 上下滑动换集
///  - 长按 2x 加速
///  - 双击播放/暂停
///  - 单击切换顶栏
struct PlayerScreen: View {
    @ObservedObject var session: PlaybackSession
    @Environment(\.dismiss) private var dismiss

    // 播放上下文
    @State private var videoId: Int64 = 0
    @State private var title: String = ""
    @State private var seriesId: Int64 = 0
    @State private var episodes: [VideoItem] = []
    @State private var currentIndex: Int = -1
    @State private var resumePlay = false

    @StateObject private var engine = PlayerEngine()

    // UI 状态
    @State private var showTopBar = true
    @State private var isFullscreen = false
    @State private var showEpisodes = false
    @State private var showCast = false
    @State private var seeking = false
    @State private var seekPreview: Double = 0
    @State private var seekBasePos: Double = 0
    @State private var seekBaseX: CGFloat = 0
    @State private var pressStartTime: Double = 0

    // 手势状态
    @State private var dragGestureHandled = false
    @State private var accelerating = false
    @State private var lastTapTime: Double = 0
    @State private var pendingSingleTap: DispatchWorkItem?

    // 投屏
    @State private var castingDevices: [DlnaDevice] = []
    @State private var castingSearching = false
    @State private var castDevice: DlnaDevice?
    @State private var castPollTask: Task<Void, Never>?

    @State private var progressTask: Task<Void, Never>?
    @State private var resumeSeekMs: Double = -1
    @State private var didBootstrap = false

    private let normalSpeed: Float = 1.0
    private let fastSpeed: Float = 2.0
    private let doubleTapWindow: Double = 0.3

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // 视频层
                PlayerLayerView(player: engine.player, gravity: .resizeAspect)
                    .ignoresSafeArea()

                // 手势层
                gestureSurface(size: geo.size)

                // 缓冲指示
                if engine.isBuffering && !seeking {
                    LoadingIndicator(size: 42)
                }
                if engine.failed {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Theme.accent)
                        Text("视频加载失败，试试切集或退出重进")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                // 加速提示
                if accelerating {
                    VStack {
                        HStack(spacing: 5) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("2x 加速中")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent.opacity(0.92)))
                        Spacer()
                    }
                    .padding(.top, 70)
                    .allowsHitTesting(false)
                }

                // 拖动进度提示
                if seeking {
                    VStack(spacing: 6) {
                        Text("\(String.clockText(seekPreview)) / \(String.clockText(engine.duration))")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(Theme.primary)
                                    .frame(width: g.size.width * CGFloat(min(1, max(0, engine.duration > 0 ? seekPreview / engine.duration : 0))))
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 26)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 16)
                    .frame(width: min(geo.size.width - 80, 380))
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.72)))
                }

                // 顶部栏
                if showTopBar {
                    VStack {
                        topBar
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // 底部进度条（常驻，便于观察）
                VStack {
                    Spacer()
                    bottomProgress
                }
                .allowsHitTesting(false)

                // 切换集的上下提示
                if episodesCount > 1 {
                    VStack {
                        if currentIndex > 0 {
                            hintChevron(up: true)
                        }
                        Spacer()
                        if currentIndex < episodes.count - 1 {
                            hintChevron(up: false)
                        }
                    }
                    .padding(.vertical, 92)
                    .allowsHitTesting(false)
                    .opacity(showTopBar ? 1 : 0.35)
                }
            }
        }
        .statusBarHidden(isFullscreen)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEpisodes) { episodesSheet }
        .sheet(isPresented: $showCast) { castSheet }
        .onAppear { bootstrapIfNeeded() }
        .onDisappear { teardown() }
        .onChange(of: engine.didEnd) { ended in
            if ended { autoNext() }
        }
        .onChange(of: engine.duration) { _ in
            // 播放器就绪后立刻应用续播位置
            applyResumeSeek()
        }
    }

    private var episodesCount: Int { episodes.count }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await searchAndCast() }
            } label: {
                Image(systemName: castDevice == nil ? "airplayvideo" : "airplayvideo.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(castDevice == nil ? .white : Theme.primary)
                    .frame(width: 42, height: 46)
                    .contentShape(Rectangle())
            }

            if !episodes.isEmpty {
                Button {
                    showEpisodes = true
                } label: {
                    Text("选集")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(height: 46)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
            }

            Button {
                toggleFullscreen()
            } label: {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 46)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 52)
        .background(Color.black.opacity(0.6))
        .padding(.top, UIApplication.shared.keyWindowTopInset())
    }

    // MARK: - 底部进度

    private var bottomProgress: some View {
        VStack(spacing: 0) {
            if castDevice != nil {
                HStack(spacing: 6) {
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 10, weight: .semibold))
                    Text("正在投屏到 \(castDevice?.displayName ?? "")")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(Theme.primary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.22))
                    Rectangle().fill(Theme.primary)
                        .frame(width: g.size.width * progressRatio)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 0)
        }
        .padding(.bottom, 0)
    }

    private var progressRatio: CGFloat {
        let pos = seeking ? seekPreview : engine.currentTime
        guard engine.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, pos / engine.duration)))
    }

    private func hintChevron(up: Bool) -> some View {
        Image(systemName: up ? "chevron.up" : "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white.opacity(0.5))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black.opacity(0.3)))
    }

    // MARK: - 手势层

    private func gestureSurface(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value, size: size)
                    }
                    .onEnded { value in
                        handleDragEnded(value, size: size)
                    }
            )
            .onTapGesture(count: 2) {
                cancelPendingTap()
                lastTapTime = 0
                engine.togglePlayPause()
            }
            .onTapGesture(count: 1) {
                let now = Date().timeIntervalSince1970
                if now - lastTapTime < doubleTapWindow {
                    // 双击已由 count:2 处理
                    return
                }
                lastTapTime = now
                cancelPendingTap()
                let work = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTopBar.toggle()
                    }
                }
                pendingSingleTap = work
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
            }
    }

    private func cancelPendingTap() {
        pendingSingleTap?.cancel()
        pendingSingleTap = nil
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        let dx = value.translation.width
        let dy = value.translation.height
        let adx = abs(dx)
        let ady = abs(dy)

        // 长按加速：按住不动超过 0.42 秒触发 2x（对应安卓 onLongPress）
        if !accelerating && !seeking && adx < 12 && ady < 12 {
            if pressStartTime == 0 { pressStartTime = Date().timeIntervalSince1970 }
            if Date().timeIntervalSince1970 - pressStartTime > 0.42 {
                accelerating = true
                engine.setSpeed(fastSpeed)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                toast("长按加速 2x")
            }
            return
        }
        if accelerating { return }
        if adx > 12 || ady > 12 { pressStartTime = 0 }

        // 横向主导 → 拖动进度（跟随手指，实时快进/快退）
        if !seeking && !dragGestureHandled && adx > 18 && adx > ady * 1.15 {
            seeking = true
            seekBasePos = engine.currentTime
            seekBaseX = value.startLocation.x
            seekPreview = engine.currentTime
            dragGestureHandled = true
        }
        if seeking {
            let secondsPerPoint = 0.4
            let delta = Double(dx) * secondsPerPoint
            let target = max(0, min(engine.duration > 0 ? engine.duration : seekBasePos + delta, seekBasePos + delta))
            seekPreview = target
            return
        }
        // 纵向主导 → 换集（单次手势只换一次）
        if !dragGestureHandled && ady > 70 && ady > adx * 1.4 {
            dragGestureHandled = true
            if dy < 0 { nextEpisode() } else { prevEpisode() }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        if seeking {
            engine.seek(to: seekPreview)
            seeking = false
        }
        if accelerating {
            accelerating = false
            engine.setSpeed(normalSpeed)
        }
        pressStartTime = 0
        dragGestureHandled = false
    }

    // MARK: - 启动与拆解

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let req = session.request
        videoId = req.videoId
        title = req.title
        seriesId = req.seriesId
        resumePlay = req.resume
        episodes = req.episodes
        currentIndex = req.currentIndex
        if currentIndex < 0, !episodes.isEmpty {
            currentIndex = episodes.firstIndex(where: { $0.id == videoId }) ?? 0
        }

        UIApplication.shared.isIdleTimerDisabled = true
        OrientationManager.shared.lockPortrait()

        startPlayback(videoId: req.videoId, newTitle: req.title, autoplay: true)

        if seriesId > 0 {
            loadEpisodes()
        } else {
            Task { await resumeFromServer() }
        }
        startProgressReporter()
    }

    private func teardown() {
        reportProgress()
        progressTask?.cancel()
        castPollTask?.cancel()
        engine.detach()
        UIApplication.shared.isIdleTimerDisabled = false
        OrientationManager.shared.lockPortrait()
        if let dev = castDevice {
            Task { _ = await DlnaManager.shared.stop(device: dev) }
        }
    }

    private func close() {
        reportProgress()
        if isFullscreen { toggleFullscreen() }
        dismiss()
    }

    // MARK: - 播放

    private func startPlayback(videoId id: Int64, newTitle: String, autoplay: Bool) {
        videoId = id
        title = newTitle
        engine.load(url: ApiClient.shared.streamURL(videoId: id), autoplay: autoplay)
        Prefs.setLastEpisode(seriesId: seriesId, videoId: id)

        // 若正在投屏，同步切换到新一集
        if let dev = castDevice {
            Task {
                _ = await DlnaManager.shared.play(device: dev,
                                                  videoURL: ApiClient.shared.streamURL(videoId: id),
                                                  title: newTitle)
                _ = await presetNext(dev)
            }
            startCastPoll()
        }
    }

    private func loadEpisodes() {
        Task { @MainActor in
            do {
                let detail = try await ApiService.shared.seriesDetail(seriesId)
                let list = detail.episodes ?? []
                guard !list.isEmpty else { return }
                episodes = list

                var target = list.firstIndex(where: { $0.id == videoId }) ?? 0
                if resumePlay, let sp = try? await ApiService.shared.seriesProgress(seriesId),
                   sp.videoId > 0, let idx = list.firstIndex(where: { $0.id == sp.videoId }) {
                    target = idx
                }
                let item = list[target]
                currentIndex = target
                if item.id != videoId {
                    startPlayback(videoId: item.id, newTitle: item.displayTitle, autoplay: true)
                }
                Prefs.setLastEpisode(seriesId: seriesId, videoId: videoId)
                await resumeFromServer()
            } catch {
                // 剧集加载失败不阻塞播放
            }
        }
    }

    private func nextEpisode() {
        guard seriesId > 0, !episodes.isEmpty else {
            toast("该视频无剧集信息")
            return
        }
        if !switchEpisode(currentIndex + 1) {
            toast("已经是最后一集")
        }
    }

    private func prevEpisode() {
        guard seriesId > 0, !episodes.isEmpty else {
            toast("该视频无剧集信息")
            return
        }
        if !switchEpisode(currentIndex - 1) {
            toast("已经是第一集")
        }
    }

    @discardableResult
    private func switchEpisode(_ target: Int) -> Bool {
        guard seriesId > 0, !episodes.isEmpty else { return false }
        guard target >= 0, target < episodes.count else { return false }
        let item = episodes[target]
        currentIndex = target
        startPlayback(videoId: item.id, newTitle: item.displayTitle, autoplay: true)
        return true
    }

    private func autoNext() {
        guard seriesId > 0, !episodes.isEmpty else { return }
        if currentIndex + 1 < episodes.count {
            switchEpisode(currentIndex + 1)
        }
    }

    /// 从服务端读取进度续播（>8 秒且 <97% 才跳，避免从头/刚看完又重播）
    private func resumeFromServer() async {
        guard videoId > 0 else { return }
        guard let st = try? await ApiService.shared.videoStatus(videoId) else { return }
        let p = st.progress
        let d = st.duration
        guard p > 8, (d <= 0 || p < d * 0.97) else { return }
        resumeSeekMs = p
        applyResumeSeek()
    }

    private func applyResumeSeek() {
        guard resumeSeekMs > 0, engine.duration > 0 || !engine.isBuffering else { return }
        engine.seek(to: resumeSeekMs)
        engine.play()
        resumeSeekMs = -1
    }

    // MARK: - 进度上报

    private func startProgressReporter() {
        progressTask?.cancel()
        progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                reportProgress()
            }
        }
    }

    private func reportProgress() {
        guard videoId > 0 else { return }
        let pos = engine.currentTime
        let dur = engine.duration
        guard pos > 0 || dur > 0 else { return }
        Task { await ApiService.shared.reportProgress(videoId: videoId, position: pos, duration: dur) }
    }

    // MARK: - 全屏

    private func toggleFullscreen() {
        isFullscreen.toggle()
        if isFullscreen {
            OrientationManager.shared.allowAllButUpsideDown()
            withAnimation(.easeInOut(duration: 0.2)) { showTopBar = false }
        } else {
            OrientationManager.shared.lockPortrait()
            withAnimation(.easeInOut(duration: 0.2)) { showTopBar = true }
        }
    }

    // MARK: - 选集

    private var episodesSheet: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("选集")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(episodes.count) 集")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Button {
                        showEpisodes = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.surfaceLight))
                    }
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                  spacing: 10) {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, ep in
                                episodeCell(ep, index: idx)
                                    .id(idx)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 26)
                    }
                    .onAppear {
                        if currentIndex >= 0 {
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func episodeCell(_ ep: VideoItem, index: Int) -> some View {
        let num = ep.episodeIndex ?? (index + 1)
        let selected = index == currentIndex
        return Button {
            showEpisodes = false
            if !switchEpisode(index) {
                toast("切换失败")
            }
        } label: {
            Text(String(format: "%03d", num))
                .font(.system(size: 16, weight: selected ? .bold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Theme.episodeSelected : Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Theme.episodeSelected : Color.white.opacity(0.16), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 投屏

    private var castSheet: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("投屏")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if castDevice != nil {
                        Button {
                            Task { await disconnectCast() }
                        } label: {
                            Text("断开")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.danger)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(Theme.danger.opacity(0.14)))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

                if castingSearching {
                    VStack(spacing: 12) {
                        LoadingIndicator(size: 30)
                        Text("正在搜索投屏设备…")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if castingDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(Theme.textSecondary.opacity(0.6))
                        Text("未发现投屏设备")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                        Text("请确认手机与电视处于同一局域网")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary.opacity(0.7))
                        Button {
                            Task { await searchAndCast() }
                        } label: {
                            Text("重新搜索")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .frame(height: 40)
                                .background(Capsule().fill(Theme.primary))
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(castingDevices) { dev in
                                Button {
                                    Task { await cast(to: dev) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "tv")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Theme.primary)
                                            .frame(width: 38, height: 38)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primary.opacity(0.12)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dev.displayName)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(Theme.textPrimary)
                                                .lineLimit(1)
                                            Text("DLNA / UPnP")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        Spacer()
                                        if castDevice?.udn == dev.udn {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(Theme.primary)
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private func searchAndCast() async {
        showCast = true
        castingSearching = true
        castingDevices = []
        let list = await DlnaManager.shared.discover(timeout: 5)
        castingDevices = list
        castingSearching = false
        if list.isEmpty { toast("未发现投屏设备") }
    }

    private func cast(to dev: DlnaDevice) async {
        let ok = await DlnaManager.shared.play(device: dev,
                                               videoURL: ApiClient.shared.streamURL(videoId: videoId),
                                               title: title)
        if ok {
            castDevice = dev
            engine.pause()
            showCast = false
            toast("已投屏到 \(dev.displayName)")
            startCastPoll()
            _ = await presetNext(dev)
        } else {
            toast("投屏失败")
        }
    }

    private func disconnectCast() async {
        guard let dev = castDevice else { return }
        _ = await DlnaManager.shared.stop(device: dev)
        castDevice = nil
        castPollTask?.cancel()
        castPollTask = nil
        engine.play()
        showCast = false
        toast("已断开投屏")
    }

    /// 预置下一集，电视支持则无缝连播
    @discardableResult
    private func presetNext(_ dev: DlnaDevice) async -> Bool {
        let next = currentIndex + 1
        guard seriesId > 0, next >= 0, next < episodes.count else { return false }
        let item = episodes[next]
        return await DlnaManager.shared.setNext(device: dev,
                                                videoURL: ApiClient.shared.streamURL(videoId: item.id),
                                                title: item.displayTitle)
    }

    /// 轮询电视播放状态，一集播完自动推下一集
    private func startCastPoll() {
        castPollTask?.cancel()
        castPollTask = Task {
            var prev = ""
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if Task.isCancelled { break }
                guard let dev = castDevice else { break }
                guard let state = await DlnaManager.shared.transportState(device: dev) else { continue }
                let wasActive = ["PLAYING", "TRANSITIONING", "PAUSED"].contains(prev)
                if wasActive && state == "STOPPED" {
                    await castNextEpisode(dev)
                    prev = ""
                    continue
                }
                prev = state
            }
        }
    }

    private func castNextEpisode(_ dev: DlnaDevice) async {
        let next = currentIndex + 1
        guard seriesId > 0, next >= 0, next < episodes.count else { return }
        let item = episodes[next]
        let ok = await DlnaManager.shared.play(device: dev,
                                               videoURL: ApiClient.shared.streamURL(videoId: item.id),
                                               title: item.displayTitle)
        if ok {
            currentIndex = next
            title = item.displayTitle
            Prefs.setLastEpisode(seriesId: seriesId, videoId: item.id)
            _ = await presetNext(dev)
            startCastPoll()
        }
    }
}
