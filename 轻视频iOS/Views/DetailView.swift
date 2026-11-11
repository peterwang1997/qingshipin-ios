import SwiftUI

/// 剧集详情 / 选集：方块矩阵只显示集数数字，点击播放；自动高亮上次看到的一集。
/// autoResume = true 时（从首页、剧场、历史进入），加载完成后直接进入播放器并续播上次那一集，
/// 不再停在选集页 —— 这正是「点开直接选集、没有进度记忆」的修法。
struct DetailView: View {
    let seriesId: Int
    let title: String
    var autoResume: Bool = true

    @Environment(\.dismiss) var dismiss

    @State private var episodes: [VideoItem] = []
    @State private var loading = true
    @State private var resumeIndex: Int = 0
    @State private var hasResume = false
    @State private var playIndex: Int? = nil
    @State private var didAutoOpen = false

    private let columns = [GridItem(.adaptive(minimum: UI.size(70)), spacing: UI.size(11))]

    var body: some View {
        ZStack {
            if playIndex != nil, !episodes.isEmpty {
                PlayerScreen(episodes: episodes,
                             index: Binding(get: { playIndex ?? 0 }, set: { playIndex = $0 }),
                             fallbackTitle: title,
                             onClose: { playIndex = nil })
            } else {
                seriesList
            }
        }
    }

    private var seriesList: some View {
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
    }

    /// 播放器直接嵌在同一个视图里（不再套一层 fullScreenCover，避免二次弹窗失效）
    private func index() -> Int { max(0, min(resumeIndex, max(0, episodes.count - 1))) }

    private func load() {
        ApiClient.shared.seriesDetail(seriesId) { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let d) = result { episodes = d.episodes ?? [] }
                // 先用本机记录定位（最可靠），再向服务端校正一次
                applyLocalResume()
                loadServerProgress()
                // 服务端进度接口异常时也不能卡在选集页，兜底直接开播
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { autoOpenIfNeeded() }
            }
        }
    }

    /// 本机记录：这部剧上次播到哪一集
    private func applyLocalResume() {
        guard !episodes.isEmpty,
              let idx = ProgressStore.lastEpisodeIndex(seriesId: seriesId, episodes: episodes) else { return }
        resumeIndex = idx
        hasResume = true
    }

    private func loadServerProgress() {
        ApiClient.shared.seriesProgress(seriesId: seriesId) { result in
            DispatchQueue.main.async {
                if case .success(let p) = result, let p = p {
                    if let vid = p.videoId, let idx = episodes.firstIndex(where: { $0.id == vid }) {
                        resumeIndex = idx; hasResume = true
                    } else if let ei = p.episodeIndex,
                              let idx = episodes.firstIndex(where: { ($0.episodeIndex ?? 0) == ei }) {
                        resumeIndex = idx; hasResume = true
                    }
                }
                autoOpenIfNeeded()
            }
        }
    }

    /// 自动进入播放器：起点＝上次那一集，没有记录就是第一集
    private func autoOpenIfNeeded() {
        guard autoResume, !didAutoOpen, !episodes.isEmpty else { return }
        didAutoOpen = true
        let start = hasResume ? resumeIndex : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if playIndex == nil { playIndex = start }
        }
    }
}
