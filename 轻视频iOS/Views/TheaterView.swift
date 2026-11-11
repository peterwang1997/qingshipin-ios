import SwiftUI

/// 剧场：剧集封面网格，点击进选集
struct TheaterView: View {
    @State private var series: [Series] = []
    @State private var loading = true
    @State private var showDetail: Series?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                if series.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(series) { s in
                                Button { showDetail = s } label: { SeriesCard(s: s) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("剧场")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $showDetail) { s in
            DetailView(seriesId: s.id, title: s.title ?? "")
        }
    }

    private func load() {
        ApiClient.shared.series { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let list) = result { series = list }
            }
        }
    }
}

struct SeriesCard: View {
    let s: Series
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: ApiClient.shared.thumbnail(s.cover)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray
            }
            .frame(height: 150).clipped().cornerRadius(8)

            Text(s.title ?? "")
                .font(.footnote).foregroundColor(.white).lineLimit(2)
            if let t = s.totalEpisodes {
                Text("全\(t)集").font(.caption2).foregroundColor(.gray)
            }
        }
    }
}
