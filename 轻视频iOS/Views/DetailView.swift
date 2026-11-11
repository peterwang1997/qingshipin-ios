import SwiftUI

/// 剧集详情 / 选集：方块矩阵只显示集数数字，点击播放；自动高亮上次看到的一集
struct DetailView: View {
    let seriesId: Int
    let title: String
    @Environment(\.dismiss) var dismiss

    @State private var episodes: [VideoItem] = []
    @State private var loading = true
    @State private var resumeIndex: Int = 0
    @State private var hasResume = false
    @State private var playIndex: Int? = nil

    private let columns = [GridItem(.adaptive(minimum: UI.size(70)), spacing: UI.size(11))]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()

                if episodes.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                    else { Text("暂无选集").foregroundColor(.gray) }
                } else {
                    VStack(spacing: 0) {
                        if hasResume {
                            Button {
                                playIndex = resumeIndex
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: UI.font(20)))
                                    Text("继续观看 第 \(index() + 1) 集")
                                        .font(.system(size: UI.body))
                                    Spacer()
                                    Text("上次看到这里")
                                        .font(.system(size: UI.fine))
                                        .opacity(0.8)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, UI.size(16)).padding(.vertical, UI.size(14))
                                .background(Color.orange.opacity(0.85))
                                .cornerRadius(UI.size(11))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, UI.hPad)
                            .padding(.top, UI.size(10))
                        }

                        ScrollView {
                            LazyVGrid(columns: columns, spacing: UI.size(11)) {
                                ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                                    Button { playIndex = i } label: {
                                        Text(String(format: "%03d", e.episodeIndex ?? (i + 1)))
                                            .font(.system(size: UI.font(15.5), weight: i == resumeIndex ? .bold : .regular))
                                            .frame(maxWidth: .infinity).frame(height: UI.size(54))
                                            .background(i == resumeIndex ? Color.orange : Color.white.opacity(0.08))
                                            .cornerRadius(UI.size(9))
                                            .foregroundColor(.white)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: UI.size(9))
                                                    .stroke(i == resumeIndex ? Color.orange : Color.clear, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(UI.hPad)
                        }
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
        .fullScreenCover(isPresented: Binding(get: { playIndex != nil },
                                              set: { if !$0 { playIndex = nil } })) {
            PlayerHost(episodes: episodes,
                       startIndex: playIndex ?? 0,
                       title: title)
        }
    }

    private func index() -> Int { max(0, min(resumeIndex, max(0, episodes.count - 1))) }

    private func load() {
        ApiClient.shared.seriesDetail(seriesId) { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let d) = result { episodes = d.episodes ?? [] }
                loadProgress()
            }
        }
    }

    private func loadProgress() {
        ApiClient.shared.seriesProgress(seriesId: seriesId) { result in
            guard case .success(let p) = result, let p = p else { return }
            DispatchQueue.main.async {
                if let vid = p.videoId, let idx = episodes.firstIndex(where: { $0.id == vid }) {
                    resumeIndex = idx; hasResume = true
                } else if let ei = p.episodeIndex,
                          let idx = episodes.firstIndex(where: { ($0.episodeIndex ?? 0) == ei }) {
                    resumeIndex = idx; hasResume = true
                }
            }
        }
    }
}
