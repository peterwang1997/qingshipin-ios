import Foundation

/// 季号解析：把「聚宝仙尊之杂灵根才是真BOSS第十二季」解析成 (根剧名, 12)
///
/// 实现刻意避开 NSRegularExpression，改用纯字符串扫描，原因：
/// 正则在不同 SDK/运行环境下的行为差异会静默失败（返回 nil 而不是报错），
/// 一旦匹配不到，所有剧都会退化成“无季号”，多季就永远合并不了。
/// 纯字符串扫描的行为是完全确定的，便于推理与验证。
enum SeasonParser {

    /// 返回 (根剧名, 季号)；无季号时季号为 0
    static func parse(_ title: String?) -> (root: String, season: Int) {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ("", 0) }

        // 1) 中文「第N季」——最主要的形态
        if let hit = findChineseSeason(t) {
            var root = t
            root.removeSubrange(hit.range)
            return (cleanRoot(root, fallback: t), hit.season)
        }
        // 2) Season 2 / season2 / S02
        if let hit = findSeasonWord(t) {
            var root = t
            root.removeSubrange(hit.range)
            return (cleanRoot(root, fallback: t), hit.season)
        }
        // 3) 结尾单个数字：「赘婿归来2」
        if let hit = findTrailingNumber(t) {
            var root = t
            root.removeSubrange(hit.range)
            return (cleanRoot(root, fallback: t), hit.season)
        }
        return (t, 0)
    }

    // MARK: - 中文「第N季」

    private static func findChineseSeason(_ t: String) -> (range: Range<String.Index>, season: Int)? {
        let chars = Array(t)
        var i = 0
        while i < chars.count {
            guard chars[i] == "第" else { i += 1; continue }

            // 「第」之后允许空格
            var j = i + 1
            while j < chars.count, chars[j] == " " || chars[j] == "\u{3000}" { j += 1 }

            // 收集数字部分
            var digits = ""
            while j < chars.count, isSeasonDigit(chars[j]) {
                digits.append(chars[j])
                j += 1
            }
            guard !digits.isEmpty else { i += 1; continue }

            // 数字之后允许空格，然后必须是「季」
            while j < chars.count, chars[j] == " " || chars[j] == "\u{3000}" { j += 1 }
            guard j < chars.count, chars[j] == "季" else { i += 1; continue }

            guard let season = toNumber(digits), season > 0 else { i += 1; continue }

            let startIdx = t.index(t.startIndex, offsetBy: i)
            let endIdx = t.index(t.startIndex, offsetBy: j + 1)
            return (startIdx..<endIdx, season)
        }
        return nil
    }

    private static func isSeasonDigit(_ ch: Character) -> Bool {
        if ch.isNumber { return true }
        return cnDigits.contains(ch) || ch == "十"
    }

    // MARK: - Season 2 / season2 / S02

    private static func findSeasonWord(_ t: String) -> (range: Range<String.Index>, season: Int)? {
        let lower = Array(t.lowercased())
        var i = 0
        while i < lower.count {
            // 定位 "season"
            if matchesWord(lower, at: i, word: ["s", "e", "a", "s", "o", "n"]) {
                var j = i + 6
                // 允许间隔符
                while j < lower.count, lower[j] == " " || lower[j] == "-" || lower[j] == "_" { j += 1 }
                var numStr = ""
                while j < lower.count, lower[j].isNumber, numStr.count < 2 {
                    numStr.append(lower[j])
                    j += 1
                }
                if let n = Int(numStr), n > 0 {
                    let startIdx = t.index(t.startIndex, offsetBy: i)
                    let endIdx = t.index(t.startIndex, offsetBy: j)
                    return (startIdx..<endIdx, n)
                }
            }
            // 定位 "s" + 数字，且 s 前面是边界
            if lower[i] == "s", i + 1 < lower.count, lower[i + 1].isNumber {
                let boundaryBefore = i == 0 || !lower[i - 1].isLetter
                if boundaryBefore {
                    var j = i + 1
                    var numStr = ""
                    while j < lower.count, lower[j].isNumber, numStr.count < 2 {
                        numStr.append(lower[j])
                        j += 1
                    }
                    // s 之后必须是结束或非字母
                    let boundaryAfter = j >= lower.count || !lower[j].isLetter
                    if boundaryAfter, let n = Int(numStr), n > 0 {
                        let startIdx = t.index(t.startIndex, offsetBy: i)
                        let endIdx = t.index(t.startIndex, offsetBy: j)
                        return (startIdx..<endIdx, n)
                    }
                }
            }
            i += 1
        }
        return nil
    }

    private static func matchesWord(_ chars: [Character], at index: Int, word: [Character]) -> Bool {
        guard index >= 0, index + word.count <= chars.count else { return false }
        for k in 0..<word.count {
            if chars[index + k] != word[k] { return false }
        }
        return true
    }

    // MARK: - 结尾单个数字

    private static func findTrailingNumber(_ t: String) -> (range: Range<String.Index>, season: Int)? {
        let chars = Array(t)
        guard let last = chars.last, last.isNumber else { return nil }
        // 只接受 1 位数字，避免把「斗罗大陆2024」当成季号
        guard let n = Int(String(last)), n > 0 else { return nil }

        let beforeIndex = chars.count - 2
        // 根名至少 2 个字，且不能以数字/「第」结尾
        guard beforeIndex >= 1 else { return nil }
        let prev = chars[beforeIndex]
        if prev.isNumber { return nil }
        if prev == "第" { return nil }
        // 「第N部/章/回/集」不算季
        if prev == "部" || prev == "章" || prev == "回" || prev == "集" || prev == "话" || prev == "期" || prev == "篇" {
            return nil
        }

        let startIdx = t.index(t.startIndex, offsetBy: chars.count - 1)
        let endIdx = t.endIndex
        return (startIdx..<endIdx, n)
    }

    // MARK: - 根名清理

    private static func cleanRoot(_ raw: String, fallback: String) -> String {
        var root = raw
        root = trimTrailing(root)
        root = trimLeading(root)
        root = trimEmptyBrackets(root)
        root = root.trimmingCharacters(in: CharacterSet(charactersIn: "，、。：:·— "))
        if root.isEmpty { root = fallback }
        return root
    }

    private static func trimTrailing(_ s: String) -> String {
        var r = s
        let tails: [Character] = ["之", "（", "(", " ", "·", "-", "_", "：", ":", "\t", "\n", "\u{3000}"]
        while let last = r.last, tails.contains(last) {
            r.removeLast()
        }
        return r
    }

    private static func trimLeading(_ s: String) -> String {
        var r = s
        let heads: [Character] = ["）", ")", " ", "·", "-", "_", "\u{3000}"]
        while let first = r.first, heads.contains(first) {
            r.removeFirst()
        }
        return r
    }

    private static func trimEmptyBrackets(_ s: String) -> String {
        var r = s
        let pairs = ["（）", "()", "（)", "(）"]
        var changed = true
        while changed {
            changed = false
            for pair in pairs where r.hasSuffix(pair) {
                r.removeLast(2)
                r = r.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
            }
        }
        return r
    }

    // MARK: - 数字转换

    private static let cnDigits: [Character] = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// "12"→12；"十二"→12；"一"→1；无法识别返回 nil
    static func toNumber(_ s: String) -> Int? {
        if s.isEmpty { return nil }
        if s.allSatisfy({ $0.isNumber }) { return Int(s) }

        let chars = Array(s)
        // 找「十」
        if let tenPos = chars.firstIndex(of: "十") {
            let before: Int
            if tenPos == 0 {
                before = 1
            } else {
                guard let idx = cnDigits.firstIndex(of: chars[tenPos - 1]), idx > 0 else { return nil }
                before = idx
            }
            let after: Int
            if tenPos == chars.count - 1 {
                after = 0
            } else {
                guard let idx = cnDigits.firstIndex(of: chars[tenPos + 1]), idx >= 0, idx <= 9 else { return nil }
                after = idx
            }
            return before * 10 + after
        }

        guard chars.count == 1, let idx = cnDigits.firstIndex(of: chars[0]), idx > 0 else { return nil }
        return idx
    }
}
