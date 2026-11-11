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
                            HStack(spacing: 12) {
                                AsyncImage(url: ApiClient.shared.thumbnail(v.cover)) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Color.gray }
                                .frame(width: 90, height: 60).clipped().cornerRadius(6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(v.title ?? v.filename ?? "")
                                        .font(.subheadline).foregroundColor(.white).lineLimit(2)
                                    if (v.seriesId ?? 0) > 0 {
                                        Text("剧集").font(.caption2).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
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
            PlayerHost(url: ApiClient.shared.streamUrl(e.id), title: e.title ?? "", videoId: e.id)
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
                            HStack(spacing: 12) {
                                AsyncImage(url: ApiClient.shared.thumbnail(v.cover)) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Color.gray }
                                .frame(width: 90, height: 60).clipped().cornerRadius(6)

                                Text(v.title ?? v.filename ?? "")
                                    .font(.subheadline).foregroundColor(.white).lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, 4)
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
            PlayerHost(url: ApiClient.shared.streamUrl(e.id), title: e.title ?? "", videoId: e.id)
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
