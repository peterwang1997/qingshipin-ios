import SwiftUI
import AVKit

/// 全屏播放器容器：AVPlayerViewController + 关闭按钮，支持 AirPlay 投屏
struct PlayerHost: View {
    let url: URL
    let title: String
    var videoId: Int? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlayerScreen(url: url, videoId: videoId).ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(12)
        }
    }
}

/// AVPlayerViewController 封装（自带全屏按钮、AirPlay 投屏、倍速）
/// 进入播放器时读取服务端进度，实现跨端续播
struct PlayerScreen: UIViewControllerRepresentable {
    let url: URL
    var videoId: Int? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 管理定时进度上报的观察者
    final class Coordinator {
        var timeObserver: Any?
        func startReporting(player: AVPlayer, item: AVPlayerItem, videoId: Int) {
            let interval = CMTime(seconds: 10, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let d = item.duration.seconds
                guard d > 0 else { return }
                ApiClient.shared.reportProgress(videoId: videoId, position: time.seconds, duration: d)
            }
        }
        func stopReporting(player: AVPlayer?) {
            if let obs = timeObserver, let player { player.removeTimeObserver(obs) }
            timeObserver = nil
        }
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        if let vid = videoId {
            // 跨端续播：读取服务端上次进度后跳转
            ApiClient.shared.videoStatus(id: vid) { result in
                guard case .success(let st) = result,
                      let p = st.progress, let d = st.duration,
                      p > 8, d > 0, p < d * 0.97 else { return }
                let target = CMTime(seconds: p, preferredTimescale: 600)
                item.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                    DispatchQueue.main.async {
                        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            }
            // 定时上报进度到服务端（每 10 秒）
            context.coordinator.startReporting(player: player, item: item, videoId: vid)
        }
        player.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stopReporting(player: uiViewController.player)
    }
}
