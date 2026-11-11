import SwiftUI

/// 观看历史
struct HistoryView: View {
    @State private var videos: [VideoItem] = []
    @State private var loading = true
    @State private var play: VideoItem?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                if videos.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                    else { Text("暂无观看历史").foregroundColor(.gray) }
                } else {
                    List(videos) { v in
                        Button { play = v } label: {
                            HStack(spacing: UI.size(13)) {
                                AsyncImage(url: ApiClient.shared.thumbnail(v.cover)) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Color.gray }
                                .frame(width: UI.size(98), height: UI.size(66)).clipped().cornerRadius(UI.size(7))

                                VStack(alignment: .leading, spacing: UI.size(5)) {
                                    Text(v.title ?? v.filename ?? "")
                                        .font(.system(size: UI.body)).foregroundColor(.white).lineLimit(2)
                                    if (v.seriesId ?? 0) > 0 {
                                        Text("剧集").font(.system(size: UI.fine)).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, UI.size(5))
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("观看历史")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $play) { e in
            PlayerHost(episodes: [e], startIndex: 0, title: e.title ?? "")
        }
    }

    private func load() {
        ApiClient.shared.watched { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let f) = result { videos = f.videos ?? [] }
            }
        }
    }
}

/// 收藏
struct FavoritesView: View {
    @State private var videos: [VideoItem] = []
    @State private var loading = true
    @State private var play: VideoItem?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                if videos.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                    else { Text("暂无收藏").foregroundColor(.gray) }
                } else {
                    List(videos) { v in
                        Button { play = v } label: {
                            HStack(spacing: UI.size(13)) {
                                AsyncImage(url: ApiClient.shared.thumbnail(v.cover)) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Color.gray }
                                .frame(width: UI.size(98), height: UI.size(66)).clipped().cornerRadius(UI.size(7))

                                Text(v.title ?? v.filename ?? "")
                                    .font(.system(size: UI.body)).foregroundColor(.white).lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, UI.size(5))
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $play) { e in
            PlayerHost(episodes: [e], startIndex: 0, title: e.title ?? "")
        }
    }

    private func load() {
        ApiClient.shared.feed(type: "favorites") { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let f) = result { videos = f.videos ?? [] }
            }
        }
    }
}
