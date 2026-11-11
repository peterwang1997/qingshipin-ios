import SwiftUI

/// 剧场：同一部剧的不同季汇总成一张卡片，点开后先选季，再选集
struct TheaterView: View {
    @State private var groups: [SeriesGroup] = []
    @State private var loading = true
    @State private var showDetail: Series? = nil
    @State private var showSeasons: SeriesGroup? = nil

    private let columns = [GridItem(.adaptive(minimum: UI.size(125)), spacing: UI.size(15))]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                if groups.isEmpty {
                    if loading { ProgressView("加载中…").tint(.white) }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: UI.size(19)) {
                            ForEach(groups) { g in
                                Button {
                                    if g.seasons.count > 1 {
                                        showSeasons = g
                                    } else if let s = g.seasons.first {
                                        showDetail = s
                                    }
                                } label: {
                                    GroupCard(g: g)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(UI.hPad)
                    }
                }
            }
            .navigationTitle("剧场")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .sheet(item: $showSeasons) { g in
            SeasonPickerView(group: g) { s in
                showSeasons = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showDetail = s }
            }
        }
        .fullScreenCover(item: $showDetail) { s in
            DetailView(seriesId: s.id, title: s.title ?? "")
        }
    }

    private func load() {
        ApiClient.shared.series { result in
            DispatchQueue.main.async {
                loading = false
                if case .success(let list) = result { groups = Self.group(list) }
            }
        }
    }

    // MARK: - 分季聚合

    static func group(_ list: [Series]) -> [SeriesGroup] {
        var buckets: [String: [(Series, Int)]] = [:]
        for s in list {
            let info = parseSeason(s.title ?? "未命名")
            buckets[info.base, default: []].append((s, info.season))
        }
        return buckets.map { (base, items) in
            let sorted = items.sorted { $0.1 < $1.1 }.map { $0.0 }
            return SeriesGroup(id: base, base: base, cover: sorted.first?.cover, seasons: sorted)
        }
        .sorted { $0.base.localizedCompare($1.base) == .orderedAscending }
    }

    /// 解析剧名里的季号，例如「规则怪谈：我百无禁忌第一季」→ (规则怪谈：我百无禁忌, 1)
    static func parseSeason(_ title: String) -> (base: String, season: Int) {
        var base = title
        var season = 1
        if let r = title.range(of: "第([一二三四五六七八九十0-9]+)季", options: .regularExpression) {
            let token = String(title[r])
                .replacingOccurrences(of: "第", with: "")
                .replacingOccurrences(of: "季", with: "")
            season = chineseToInt(token) ?? (Int(token) ?? 1)
            base = title.replacingCharacters(in: r, with: "")
        } else if let r = title.range(of: "[Ss]eason\\s*([0-9]+)", options: .regularExpression) {
            let token = String(title[r]).filter { $0.isNumber }
            season = Int(token) ?? 1
            base = title.replacingCharacters(in: r, with: "")
        } else if let r = title.range(of: "\\s*[Ss][0-9]+$", options: .regularExpression) {
            let token = String(title[r]).filter { $0.isNumber }
            season = Int(token) ?? 1
            base = title.replacingCharacters(in: r, with: "")
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? title : base, season)
    }

    static func chineseToInt(_ s: String) -> Int? {
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                                     "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        let chars = Array(s)
        if chars.count == 1, let v = map[chars[0]] { return v }
        if chars.count == 2, chars[0] == "十", let v = map[chars[1]] { return 10 + v }
        if chars.count == 2, chars[1] == "十", let v = map[chars[0]] { return v * 10 }
        if chars.count == 3, chars[1] == "十", let a = map[chars[0]], let b = map[chars[2]] {
            return a * 10 + b
        }
        return Int(s)
    }
}

struct SeriesGroup: Identifiable {
    let id: String
    let base: String
    let cover: String?
    let seasons: [Series]
}

struct GroupCard: View {
    let g: SeriesGroup

    var body: some View {
        VStack(alignment: .leading, spacing: UI.size(7)) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: ApiClient.shared.thumbnail(g.cover)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(height: UI.size(165)).clipped().cornerRadius(UI.size(9))

                if g.seasons.count > 1 {
                    Text("\(g.seasons.count) 季")
                        .font(.system(size: UI.fine)).foregroundColor(.white)
                        .padding(.horizontal, UI.size(7)).padding(.vertical, UI.size(4))
                        .background(Color.orange).cornerRadius(UI.size(6))
                        .padding(UI.size(7))
                }
            }

            Text(g.base)
                .font(.system(size: UI.font(16))).foregroundColor(.white).lineLimit(2)
            if let t = g.seasons.first?.totalEpisodes, g.seasons.count == 1 {
                Text("全\(t)集").font(.system(size: UI.fine)).foregroundColor(.gray)
            } else if g.seasons.count > 1 {
                Text("共 \(g.seasons.count) 季").font(.system(size: UI.fine)).foregroundColor(.gray)
            }
        }
    }
}

// MARK: - 季选择

struct SeasonPickerView: View {
    let group: SeriesGroup
    let onPick: (Series) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                List {
                    ForEach(Array(group.seasons.enumerated()), id: \.element.id) { i, s in
                        Button { onPick(s) } label: {
                            HStack {
                                Text("第 \(i + 1) 季")
                                    .font(.system(size: UI.body))
                                    .foregroundColor(.white)
                                Text(s.title ?? "")
                                    .font(.system(size: UI.fine)).foregroundColor(.gray).lineLimit(1)
                                Spacer()
                                if let t = s.totalEpisodes {
                                    Text("\(t) 集").font(.system(size: UI.fine)).foregroundColor(.gray)
                                }
                                Image(systemName: "chevron.right").foregroundColor(.gray)
                            }
                            .padding(.vertical, UI.size(8))
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(group.base)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}
