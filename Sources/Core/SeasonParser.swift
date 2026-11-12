import Foundation

/// 季号解析：把「聚宝仙尊之杂灵根才是真BOSS第十二季」解析成 (根剧名, 12)
/// 支持多种后端实际存在的命名形态：
///   第十二季 / 第12季 / 第 12 季 / （第一季）/ 之第二季
///   Season 2 / season2 / S02 / S2 / EP… 以外的尾缀数字（如「赘婿归来2」）
enum SeasonParser {
    private static let seasonPattern = "第\\s*([0-9零一二三四五六七八九十]+)\\s*季"
    private static let seasonWordPattern = "(?i)\\bseason\\s*([0-9]{1,2})\\b"
    private static let sPrefixPattern = "(?i)(?:^|[\\s·\\-_.\\[（(])s(\\d{1,2})(?:$|[\\s·\\-_.\\]）)])"
    /// 纯数字尾缀：「赘婿归来2」「闪婚老伴是豪门 2」
    private static let trailingNumberPattern = "^(.+?)[\\s·\\-_]*(\\d{1})$"
    /// 第 N 部 / 第 N 章 等非季号后缀，避免误判
    private static let nonSeasonUnits = ["部", "章", "回", "集", "话", "期", "篇"]

    private static let cnDigits: [Character] = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 返回 (根剧名, 季号)；无季号时季号为 0
    static func parse(_ title: String?) -> (root: String, season: Int) {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ("", 0) }

        if let result = matchChineseSeason(t) { return result }
        if let result = matchWordSeason(t) { return result }
        if let result = matchTrailingNumber(t) { return result }
        return (t, 0)
    }

    // MARK: - 中文「第N季」

    private static func matchChineseSeason(_ t: String) -> (String, Int)? {
        guard let regex = try? NSRegularExpression(pattern: seasonPattern),
              let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let numRange = Range(match.range(at: 1), in: t),
              let fullRange = Range(match.range, in: t),
              let num = toNumber(String(t[numRange]))
        else { return nil }
        var root = t
        root.removeSubrange(fullRange)
        return (cleanRoot(root, fallback: t), num)
    }

    // MARK: - Season 2 / season2 / S02

    private static func matchWordSeason(_ t: String) -> (String, Int)? {
        for pattern in [seasonWordPattern, sPrefixPattern] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let numRange = Range(match.range(at: 1), in: t),
                  let fullRange = Range(match.range, in: t),
                  let num = Int(t[numRange]), num > 0
            else { continue }
            var root = t
            root.removeSubrange(fullRange)
            return (cleanRoot(root, fallback: t), num)
        }
        return nil
    }

    // MARK: - 尾缀纯数字

    private static func matchTrailingNumber(_ t: String) -> (String, Int)? {
        // 「第 12 部」这类不是季，直接排除
        for unit in nonSeasonUnits where t.contains("第") && t.contains(unit) { return nil }
        guard let regex = try? NSRegularExpression(pattern: trailingNumberPattern),
              let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let rootRange = Range(match.range(at: 1), in: t),
              let numRange = Range(match.range(at: 2), in: t),
              let num = Int(t[numRange]), num > 0
        else { return nil }
        let root = String(t[rootRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // 根名太短时不当作季号
        guard root.count >= 2 else { return nil }
        // 根名以「第」结尾（第2部）或本身以数字结尾（斗罗大陆2024）时不当作季号
        if root.hasSuffix("第") { return nil }
        if let last = root.last, last.isNumber { return nil }
        return (root, num)
    }

    private static func cleanRoot(_ raw: String, fallback: String) -> String {
        var root = raw
        root = trimTrailingConnectives(root)
        root = trimLeadingConnectives(root)
        root = trimBracketTails(root)
        root = root.trimmingCharacters(in: CharacterSet(charactersIn: "，、。：:·-—"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if root.isEmpty { root = fallback }
        return root
    }

    private static func trimTrailingConnectives(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        let tails: [Character] = ["之", "（", "(", " ", "·", "-", "_", "：", ":", "\t", "\n"]
        while let last = r.last, tails.contains(last) {
            r.removeLast()
            r = r.trimmingCharacters(in: .whitespaces)
        }
        return r
    }

    private static func trimLeadingConnectives(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        let heads: [Character] = ["（", "(", " ", "·", "-", "_"]
        while let first = r.first, heads.contains(first) {
            r.removeFirst()
            r = r.trimmingCharacters(in: .whitespaces)
        }
        return r
    }

    /// 清掉悬空括号，如「天灾末世，她囤满物资后所向披靡（）」
    private static func trimBracketTails(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for pair in ["（）", "()", "（)", "()"] where r.hasSuffix(pair) {
                r.removeLast(2)
                r = r.trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return r
    }

    /// "12"→12；"十二"→12；"一"→1；无法识别返回 nil
    static func toNumber(_ s: String) -> Int? {
        if s.allSatisfy({ $0.isNumber }) { return Int(s) }
        guard let tenIndex = s.firstIndex(of: "十") else {
            guard s.count == 1, let ch = s.first else { return nil }
            guard let d = cnDigits.firstIndex(of: ch), d > 0 else { return nil }
            return d
        }
        let before: Int
        if tenIndex == s.startIndex {
            before = 1
        } else {
            let prev = s[s.index(before: tenIndex)]
            guard let idx = cnDigits.firstIndex(of: prev), idx > 0 else { return nil }
            before = idx
        }
        let afterStart = s.index(after: tenIndex)
        let after: Int
        if afterStart == s.endIndex {
            after = 0
        } else {
            let ch = s[afterStart]
            guard let idx = cnDigits.firstIndex(of: ch), idx > 0 else { return nil }
            after = idx
        }
        return before * 10 + after
    }
}
