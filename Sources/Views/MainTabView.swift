import SwiftUI

/// 主框架：底部四个标签，对应安卓 MainActivity + BottomNavigationView
struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case home, theater, favorites, profile
        var title: String {
            switch self {
            case .home: return "首页"
            case .theater: return "剧场"
            case .favorites: return "收藏"
            case .profile: return "我的"
            }
        }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .theater: return "film.stack.fill"
            case .favorites: return "heart.fill"
            case .profile: return "person.fill"
            }
        }
    }

    @State private var selected: Tab = .home
    @State private var hasVisitedTheater = false
    @State private var hasVisitedFavorites = false
    @State private var hasVisitedProfile = false
    @State private var playerSession: PlaybackSession?
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ZStack {
                HomeScreen(isActive: selected == .home,
                           onOpenPlayer: { openPlayer($0) })
                    .opacity(selected == .home ? 1 : 0)
                    .allowsHitTesting(selected == .home)

                if hasVisitedTheater {
                    TheaterScreen(onOpenPlayer: { openPlayer($0) })
                        .opacity(selected == .theater ? 1 : 0)
                        .allowsHitTesting(selected == .theater)
                } else if selected == .theater {
                    Color.clear.onAppear { hasVisitedTheater = true }
                }

                if hasVisitedFavorites {
                    FavoritesScreen(onOpenPlayer: { openPlayer($0) })
                        .opacity(selected == .favorites ? 1 : 0)
                        .allowsHitTesting(selected == .favorites)
                } else if selected == .favorites {
                    Color.clear.onAppear { hasVisitedFavorites = true }
                }

                if hasVisitedProfile {
                    ProfileScreen(onOpenPlayer: { openPlayer($0) })
                        .opacity(selected == .profile ? 1 : 0)
                        .allowsHitTesting(selected == .profile)
                } else if selected == .profile {
                    Color.clear.onAppear { hasVisitedProfile = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Spacer()
                tabBar
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .fullScreenCover(item: $playerSession) { session in
            PlayerScreen(session: session)
        }
    }

    private func openPlayer(_ req: PlaybackRequest) {
        playerSession = PlaybackSession(request: req)
    }

    // MARK: - 底部标签栏

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                Button {
                    if selected != tab {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selected = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .regular))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selected == tab ? Theme.primary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, safeBottom())
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.divider).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func safeBottom() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first?.safeAreaInsets.bottom ?? 34
    }
}

/// 播放请求：需要播放的视频与剧集上下文
struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    var videoId: Int64
    var title: String
    var seriesId: Int64
    /// 续播标记：true 时进播放器自动跳到服务端最后观看集
    var resume: Bool
    /// 已知剧集列表（剧场进入时直接带入，省一次请求）
    var episodes: [VideoItem] = []
    var currentIndex: Int = -1
}

final class PlaybackSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var request: PlaybackRequest
    init(request: PlaybackRequest) { self.request = request }
}
