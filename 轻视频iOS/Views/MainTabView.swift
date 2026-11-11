import SwiftUI

enum AppTab: Hashable {
    case home, theater, history, favorites, profile
}

struct MainTabView: View {
    @State private var selected: AppTab = .home

    var body: some View {
        TabView(selection: $selected) {
            HomeView()
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
    }
}

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 72)).foregroundColor(.gray)
                Text(auth.username).font(.title2)
                Text("服务器：\(auth.server)").font(.footnote).foregroundColor(.gray)
                Button("退出登录") { auth.logout() }
                    .padding(.horizontal, 30).padding(.vertical, 12)
                    .background(Color.red.opacity(0.8)).foregroundColor(.white)
                    .cornerRadius(10)
            }
            .navigationTitle("我的")
        }
    }
}
