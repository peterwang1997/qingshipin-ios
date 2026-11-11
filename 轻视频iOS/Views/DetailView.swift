import SwiftUI

/// 剧集详情 / 选集：方块矩阵只显示集数数字，点击播放
struct DetailView: View {
    let seriesId: Int
    let title: String
    @Environment(\.dismiss) var dismiss
    @State private var episodes: [VideoItem] = []
    @State private var loading = true
    @State private var play: VideoItem?

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 10)]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                if episodes.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                    else { Text("暂无选集").foregroundColor(.gray) }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                                Button { play = e } label: {
                                    Text(String(format: "%03d", e.episodeIndex ?? (i + 1)))
                                        .frame(maxWidth: .infinity).frame(height: 52)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $play) { e in
            PlayerHost(url: ApiClient.shared.streamUrl(e.id), title: e.title ?? title, videoId: e.id)
        }
    }

    private func load() {
        ApiClient.shared.seriesDetail(seriesId) { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let d) = result { episodes = d.episodes ?? [] }
            }
        }
    }
}
