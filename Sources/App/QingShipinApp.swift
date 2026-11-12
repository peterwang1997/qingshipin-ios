import SwiftUI
import UIKit
import AVFoundation

@main
struct QingShipinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .background(Theme.background)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 播放器需要在静音键打开时也能出声
        try? Self.configureAudioSession()
        return true
    }

    private static func configureAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try AVAudioSession.sharedInstance().setActive(true)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationManager.shared.mask
    }
}

/// 全局方向控制：播放器全屏时允许横屏，其余页面仅竖屏
final class OrientationManager {
    static let shared = OrientationManager()
    private(set) var mask: UIInterfaceOrientationMask = .portrait

    func lockPortrait() {
        mask = .portrait
        requestUpdate()
    }

    func allowAllButUpsideDown() {
        mask = .allButUpsideDown
        requestUpdate()
    }

    /// iOS 15 只能靠 setValue 触发方向刷新，iOS 16+ 用官方几何更新 API
    private func requestUpdate() {
        if #available(iOS 16.0, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            return
        }
        UIDevice.current.setValue(mask == .portrait ? UIInterfaceOrientation.portrait.rawValue
                                                   : UIInterfaceOrientation.landscapeRight.rawValue,
                                  forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

/// 全局应用状态：登录态、服务器探测结果
@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case launching
        case login
        case main
    }

    @Published var phase: Phase = .launching
    @Published var user: User?
    @Published var serverURL: String = ApiClient.shared.baseURL

    init() { }

    /// 启动时：自动探测内网/外网 → 判断登录态
    func bootstrap() async {
        OrientationManager.shared.lockPortrait()
        // 短暂停留让启动动画不突兀（对应安卓 delay(300)）
        try? await Task.sleep(nanoseconds: 320_000_000)
        let best = await ApiClient.shared.autoDetectBase()
        serverURL = best

        if ApiClient.shared.isLoggedIn {
            phase = .main
            Task { await refreshUser() }
        } else {
            phase = .login
        }
    }

    func refreshUser() async {
        guard ApiClient.shared.isLoggedIn else { return }
        if let me = try? await ApiService.shared.me() {
            user = me
        }
    }

    func didLogin(user: User?) {
        self.user = user
        serverURL = ApiClient.shared.baseURL
        phase = .main
    }

    func logout() {
        ApiClient.shared.clearAuth()
        user = nil
        phase = .login
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch appState.phase {
            case .launching:
                SplashScreen()
                    .transition(.opacity)
            case .login:
                LoginScreen()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .task {
            if appState.phase == .launching { await appState.bootstrap() }
        }
    }
}
