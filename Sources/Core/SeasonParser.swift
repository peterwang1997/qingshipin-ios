import Foundation

/// 季号解析：与安卓 SeasonParser 行为保持一致，
/// 把「聚宝仙尊之杂灵根才是真BOSS第十二季」解析成 (根剧名, 12)
enum SeasonParser {
    private static let seasonPattern = "第\\s*([0-9零一二三四五六七八九十]+)\\s*季"
    private static let cnDigits: [Character] = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 返回 (根剧名, 季号)；无季号时季号为 0
    static func parse(_ title: String?) -> (root: String, season: Int) {
        let t = title ?? ""
        guard let regex = try? NSRegularExpression(pattern: seasonPattern),
              let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let numRange = Range(match.range(at: 1), in: t),
              let fullRange = Range(match.range, in: t),
              let num = toNumber(String(t[numRange]))
        else {
            return (t.trimmingCharacters(in: .whitespacesAndNewlines), 0)
        }

        var root = t
        root.removeSubrange(fullRange)
        root = trimTrailingConnectives(root)
        root = trimLeadingConnectives(root)
        root = trimBracketTails(root)
        root = root.trimmingCharacters(in: CharacterSet(charactersIn: "，、。：: ")).trimmingCharacters(in: .whitespaces)
        if root.isEmpty { root = t.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (root, num)
    }

    private static func trimTrailingConnectives(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespaces)
        let tails: [Character] = ["之", "（", "(", " ", "·", "-", "_", "：", ":"]
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
        let pairs: [(Character, Character)] = [("（", "）"), ("(", "）"), ("（", ")"), ("(", ")")]
        var changed = true
        while changed {
            changed = false
            for (open, close) in pairs {
                if r.hasSuffix(String(close)) && r.hasSuffix(String(open) + String(close)) {
                    r.removeLast(2)
                    r = r.trimmingCharacters(in: .whitespaces)
                    changed = true
                }
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
