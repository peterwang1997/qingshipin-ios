import SwiftUI

@main
struct QingShipinApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(auth)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var ready = false

    var body: some View {
        Group {
            if !ready {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.white)
                        Text("正在连接服务器…")
                            .font(.system(size: UI.note))
                            .foregroundColor(.gray)
                    }
                }
            } else if auth.loggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .onAppear(perform: detect)
        .onChange(of: scenePhase) { phase in
            // 回到前台时重新判断一次内网 / 外网
            if phase == .active { detect() }
        }
    }

    private func detect() {
        ApiClient.shared.refreshEnvironment { env in
            auth.updateServer(env.rawValue)
            ready = true
        }
    }
}
