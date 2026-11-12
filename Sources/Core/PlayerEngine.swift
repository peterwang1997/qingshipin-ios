import AVFoundation
import UIKit
import Combine

/// AVPlayer 封装：对应安卓 ExoPlayer 的播放/暂停/倍速/进度上报能力
@MainActor
final class PlayerEngine: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var isPlaying = false
    @Published var isBuffering = true
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var didEnd = false
    @Published var failed: Bool = false

    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var baseRate: Float = 1.0
    private(set) var loadedURL: String?

    init() {
        player.actionAtItemEnd = .pause
        player.volume = 1.0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
                let d = self.player.currentItem?.duration.seconds ?? 0
                if d.isFinite && d > 0 { self.duration = d }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPlaying = playing
                self.isBuffering = buffering
            }
        }
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
    }

    func load(url: String, autoplay: Bool = true) {
        guard let u = URL(string: url) else { return }
        if loadedURL == url, player.currentItem != nil {
            if autoplay { play() }
            return
        }
        clearObservers()
        loadedURL = url
        currentTime = 0
        duration = 0
        didEnd = false
        failed = false
        isBuffering = true

        let asset = AVURLAsset(url: u, options: [AVURLAssetHTTPHeaderFieldsKey: ["User-Agent": "QingShipin-iOS/1.3"]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let dur = item.duration.seconds
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    if dur.isFinite && dur > 0 { self.duration = dur }
                    self.isBuffering = false
                    if self.player.timeControlStatus != .playing { self.play() }
                case .failed:
                    self.isBuffering = false
                    self.failed = true
                default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.didEnd = true
                self?.isPlaying = false
            }
        }

        player.replaceCurrentItem(with: item)
        if autoplay { play() }
    }

    func play() {
        didEnd = false
        player.rate = baseRate
    }

    func pause() { player.pause() }

    func togglePlayPause() {
        if player.timeControlStatus == .paused { play() } else { pause() }
    }

    /// 长按加速：1x ↔ 2x
    func setSpeed(_ speed: Float) {
        baseRate = speed
        if player.timeControlStatus != .paused { player.rate = speed }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let clamped = duration > 0 ? min(seconds, duration) : seconds
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        didEnd = false
    }

    func seekBy(_ delta: Double) { seek(to: currentTime + delta) }

    private func clearObservers() {
        itemStatusObservation = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
    }

    /// 离开时调用：只断流，不销毁 player 实例
    func detach() {
        player.pause()
        clearObservers()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }
}

/// AVPlayerLayer 宿主视图（等比适配，对应 PlayerView resize_mode=fit）
final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = UIColor.black.cgColor
        }
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }
}

/// 让 SwiftUI 使用 AVPlayerLayer
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let v = PlayerSurfaceView()
        v.backgroundColor = .black
        v.player = player
        v.videoGravity = gravity
        return v
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.player !== player { uiView.player = player }
        uiView.videoGravity = gravity
    }
}