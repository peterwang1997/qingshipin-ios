import SwiftUI

/// 剧场列表项：单季剧直接续播，多季折叠成文件夹
enum TheaterItem: Identifiable, Equatable {
    case single(Series)
    case multi(rootTitle: String, seasons: [Series])

    var id: String {
        switch self {
        case let .single(s): return "s-\(s.id)"
        case let .multi(root, _): return "m-\(root)"
        }
    }

    var title: String {
        switch self {
        case let .single(s): return s.displayTitle
        case let .multi(root, _): return root
        }
    }

    var coverName: String? {
        switch self {
        case let .single(s): return s.coverName
        case let .multi(_, seasons): return seasons.first?.coverName
        }
    }

    var episodeText: String {
        switch self {
        case let .single(s):
            if let n = s.episodeTotal { return "全\(n)集" }
            return ""
        case let .multi(_, seasons): return "共\(seasons.count)季"
        }
    }

    var isMulti: Bool {
        if case .multi = self { return true }
        return false
    }

    /// 单季时返回该季 id；多季返回 nil（多季不显示单项加载态）
    var seriesId: Int64? {
        if case let .single(s) = self { return s.id }
        return nil
    }

    /// 按根剧名分组：单季 → single，多季 → multi（季号升序）
    /// 归一化后再比较，避免全角/半角括号、空格、标点差异导致同一部剧被拆成多个条目
    static func group(_ list: [Series]) -> [TheaterItem] {
        var order: [String] = []
        var buckets: [String: (root: String, items: [(series: Series, season: Int)])] = [:]

        for s in list {
            let parsed = SeasonParser.parse(s.title)
            let key = normalizeKey(parsed.root)
            if buckets[key] == nil {
                buckets[key] = (parsed.root, [])
                order.append(key)
            }
            buckets[key]?.items.append((s, parsed.season))
        }

        return order.compactMap { key -> TheaterItem? in
            guard let bucket = buckets[key], !bucket.items.isEmpty else { return nil }

            // 后端存在「无季号标题」= 第一季的情况（如“咱家剑宗团宠小师妹”配“...第二季”）
            // 该组已有真实季号且缺第 1 季时，把无季号那条视为第一季
            let hasSeasonOne = bucket.items.contains { $0.season == 1 }
            let hasRealSeason = bucket.items.contains { $0.season > 0 }
            var entries = bucket.items
            if hasRealSeason && !hasSeasonOne {
                entries = entries.map { entry in
                    entry.season == 0 ? (entry.series, 1) : entry
                }
            }

            // 同季号重复（如“...第二季”与“...之第二季”）只保留一条
            var seenSeasons = Set<Int>()
            var deduped: [(series: Series, season: Int)] = []
            for entry in entries {
                if seenSeasons.insert(entry.season).inserted {
                    deduped.append(entry)
                }
            }

            // 季号 0 视为未知，排在最后
            let sorted = deduped
                .enumerated()
                .sorted { a, b in
                    let sa = a.element.season == 0 ? Int.max : a.element.season
                    let sb = b.element.season == 0 ? Int.max : b.element.season
                    if sa != sb { return sa < sb }
                    return a.offset < b.offset
                }
                .map { $0.element.series }

            if sorted.count <= 1 {
                return .single(sorted[0])
            }
            let title = hasRealSeason ? bucket.root : (sorted.first?.displayTitle ?? bucket.root)
            return .multi(rootTitle: title, seasons: sorted)
        }
    }

    /// 

    /// 分组键归一化：去空白、统一括号与标点、全角转半角、忽略大小写
    static func normalizeKey(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "（", "(", "【", "[", "〔":
                out.append("(")
            case "）", ")", "】", "]", "〕":
                out.append(")")
            case "：":
                out.append(":")
            case "，":
                out.append(",")
            case "、", "·", "•", "・", "-", "—", "_", ".", "。", " ":
                continue
            default:
                out.append(ch)
            }
        }
        return out.lowercased().trimmingCharacters(in: .whitespaces)
    }
}


/// 剧场：短剧库网格，点击封面直接续播
struct TheaterScreen: View {
    var onOpenPlayer: (PlaybackRequest) -> Void

    @State private var items: [TheaterItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var seasonPicker: SeasonPickerTarget?
    @State private var openingId: Int64?
    @State private var diagnoseText: String = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GeometryReader { geo in
            let cardWidth = (geo.size.width - 16 - 10) / 2
            let coverHeight = Screen.coverHeight(forColumnWidth: cardWidth)
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        if loading && items.isEmpty {
                            LoadingIndicator(size: 34)
                                .frame(height: 240)
                        } else if items.isEmpty {
                            EmptyStateView(text: error ?? "暂无剧集")
                                .frame(height: 360)
                        } else {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(items) { item in
                                    card(item, coverHeight: coverHeight)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .padding(.bottom, tabBottomInset() + 16)
                        }
                    }
                }
                .refreshable { await load() }

                if openingId != nil {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    LoadingIndicator(size: 30)
                }
            }
        }
        .task { if items.isEmpty { await load() } }
        .sheet(item: $seasonPicker) { target in
            SeasonPickerSheet(rootTitle: target.rootTitle,
                              seasons: target.seasons,
                              onPlay: { series, resumeVideoId in
                seasonPicker = nil
                openSeries(series, resumeVideoId: resumeVideoId)
            })
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("剧场")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(items.isEmpty ? "短剧库" : "\(items.count) 部作品")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .onLongPressGesture {
                        if !diagnoseText.isEmpty { toast(diagnoseText) }
                    }
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surface))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func card(_ item: TheaterItem, coverHeight: CGFloat) -> some View {
        Button {
            tapped(item)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RemoteImage(url: ApiClient.shared.thumbnailURL(item.coverName, width: 360),
                                placeholderIcon: "film")
                        .frame(height: coverHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous))

                    if item.isMulti {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(item.episodeText)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.55)))
                            }
                            Spacer()
                        }
                        .padding(7)
                    }

                    if openingId != nil, openingId == item.seriesId {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous)
                                .fill(Color.black.opacity(0.45))
                            LoadingIndicator(size: 24)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 0.6)
                )

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 7)
                    .padding(.horizontal, 2)

                Text(item.episodeText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous)
                    .fill(Theme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 交互

    private func tapped(_ item: TheaterItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch item {
        case let .single(series):
            openSeries(series, resumeVideoId: nil)
        case let .multi(root, seasons):
            seasonPicker = SeasonPickerTarget(rootTitle: root, seasons: seasons)
        }
    }

    /// 点封面：读服务端该剧最近观看集并续播；无历史则播第 1 集
    private func openSeries(_ series: Series, resumeVideoId: Int64?) {
        openingId = series.id
        Task { @MainActor in
            defer { openingId = nil }
            do {
                var videoId: Int64 = 0
                var episodes: [VideoItem] = []

                if let vid = resumeVideoId, vid > 0 {
                    videoId = vid
                }
                if let sp = try? await ApiService.shared.seriesProgress(series.id), sp.videoId > 0 {
                    videoId = sp.videoId
                }

                let detail = try await ApiService.shared.seriesDetail(series.id)
                episodes = detail.episodes ?? []

                if videoId == 0 {
                    if let local = Prefs.lastEpisode(seriesId: series.id),
                       episodes.contains(where: { $0.id == local }) {
                        videoId = local
                    } else if let first = episodes.first {
                        videoId = first.id
                    } else {
                        toast("该剧集暂无内容")
                        return
                    }
                }

                let index = episodes.firstIndex(where: { $0.id == videoId }) ?? -1
                let title: String
                if index >= 0 {
                    title = episodes[index].displayTitle
                } else {
                    title = series.displayTitle
                }

                onOpenPlayer(PlaybackRequest(videoId: videoId,
                                             title: title,
                                             seriesId: series.id,
                                             resume: true,
                                             episodes: episodes,
                                             currentIndex: index))
            } catch {
                toast("加载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            // 分页拉全：同一部剧的不同季可能落在不同页，只取第一页会导致多季合并失效
            var all: [Series] = []
            var seen = Set<Int64>()
            var page = 1
            let pageSize = 200
            while page <= 50 {
                let chunk = try await ApiService.shared.series(page: page, limit: pageSize)
                let fresh = chunk.filter { seen.insert($0.id).inserted }
                all.append(contentsOf: fresh)
                if chunk.count < pageSize || fresh.isEmpty { break }
                page += 1
            }
            let grouped = TheaterItem.group(all)
            items = grouped
            // 诊断：记录原始条数 / 聚合后条目数 / 多季组数，供长按标题查看
            let multiCount = grouped.filter { $0.isMulti }.count
            diagnoseText = "原始 \(all.count) 条 → 聚合 \(grouped.count) 项 · 多季 \(multiCount) 组"
            if items.isEmpty {
                self.error = "暂无剧集"
            }
        } catch {
            self.error = "加载失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        loading = false
    }

    private func tabBottomInset() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bottom = scene?.windows.first?.safeAreaInsets.bottom ?? 34
        return bottom + 49
    }
}

struct SeasonPickerTarget: Identifiable {
    let id = UUID()
    var rootTitle: String
    var seasons: [Series]
}

/// 选季页：某部剧的所有季，点击某季从上次观看位置续播
struct SeasonPickerSheet: View {
    var rootTitle: String
    var seasons: [Series]
    var onPlay: (Series, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var progressMap: [Int64: (videoId: Int64, episode: Int?)] = [:]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(rootTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.surfaceLight))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(seasons.enumerated()), id: \.element.id) { idx, s in
                            seasonCard(s, ordinal: idx + 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 26)
                }
            }
        }
        .task {
            // 逐季读取服务端进度（数量有限，避免并发上下文传递模型）
            for s in seasons {
                guard let sp = try? await ApiService.shared.seriesProgress(s.id) else { continue }
                if sp.videoId > 0 {
                    progressMap[s.id] = (sp.videoId, sp.episodeIndex)
                }
            }
        }
    }

    private func seasonCard(_ s: Series, ordinal: Int) -> some View {
        Button {
            onPlay(s, progressMap[s.id]?.videoId)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: ApiClient.shared.thumbnailURL(s.coverName, width: 360),
                                placeholderIcon: "film")
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous))

                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous))

                    HStack(spacing: 6) {
                        Text(seasonLabel(s, ordinal: ordinal))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.primary.opacity(0.9)))

                        if let p = progressMap[s.id] {
                            Text(p.episode.map { "看到第\($0)集" } ?? "有进度")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                        }
                    }
                    .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerCover, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 0.6)
                )

                Text(s.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous)
                    .fill(Theme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func seasonLabel(_ s: Series, ordinal: Int) -> String {
        let parsed = SeasonParser.parse(s.title)
        if parsed.season > 0 { return "第\(parsed.season)季" }
        return "第\(ordinal)季"
    }
}
