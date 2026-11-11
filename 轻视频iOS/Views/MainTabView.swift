import SwiftUI

enum AppTab: Hashable {
    case home, theater, history, favorites, profile
}

struct MainTabView: View {
    @State private var selected: AppTab = .home
    @StateObject private var feedPlayback = FeedPlayback()

    var body: some View {
        TabView(selection: $selected) {
            HomeView(playback: feedPlayback)
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppTab.home)
            TheaterView()
                .tabItem { Label("剧场", systemImage: "film.fill") }
                .tag(AppTab.theater)
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.fill") }
                .tag(AppTab.history)
            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star.fill") }
                .tag(AppTab.favorites)
            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
        .tint(.orange)
        .onChange(of: selected) { tab in
            // 切到别的标签页时，首页必须停声
            feedPlayback.isVisible = (tab == .home)
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var detecting = false

    private var currentEnv: ServerEnv? { ServerEnv.match(auth.server) }

    var body: some View {
        NavigationView {
            VStack(spacing: UI.size(18)) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: UI.size(80)))
                    .foregroundColor(.gray)

                Text(auth.username)
                    .font(.system(size: UI.title, weight: .semibold))

                VStack(spacing: UI.size(10)) {
                    Text("服务器：\(auth.server)")
                        .font(.system(size: UI.fine))
                        .foregroundColor(.gray)

                    Text(detecting ? "正在检测网络…" : "当前网络：\(currentEnv?.title ?? "未识别")")
                        .font(.system(size: UI.note))
                        .foregroundColor(.orange)

                    HStack(spacing: UI.size(12)) {
                        Button("重新检测") { redetect() }
                            .padding(.horizontal, UI.size(20))
                            .padding(.vertical, UI.size(11))
                            .background(Color.white.opacity(0.14))
                            .foregroundColor(.white)
                            .cornerRadius(UI.size(10))
                            .disabled(detecting)

                        Menu {
                            Button("内网（家里）") { switchTo(.internalNet) }
                            Button("外网（远程）") { switchTo(.externalNet) }
                        } label: {
                            Text("手动切换")
                                .padding(.horizontal, UI.size(20))
                                .padding(.vertical, UI.size(11))
                                .background(Color.orange.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(UI.size(10))
                        }
                    }
                    .font(.system(size: UI.note))
                }
                .padding(.top, UI.size(6))

                Button("退出登录") { auth.logout() }
                    .font(.system(size: UI.note))
                    .padding(.horizontal, UI.size(32))
                    .padding(.vertical, UI.size(14))
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(UI.size(10))
                    .padding(.top, UI.size(10))
            }
            .padding(.horizontal, UI.hPad)
            .padding(.top, UI.size(28))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("我的")
        }
    }

    private func redetect() {
        detecting = true
        ApiClient.shared.refreshEnvironment { env in
            auth.updateServer(env.rawValue)
            detecting = false
        }
    }

    private func switchTo(_ env: ServerEnv) {
        ApiClient.shared.switchTo(env)
        auth.updateServer(env.rawValue)
    }
}
