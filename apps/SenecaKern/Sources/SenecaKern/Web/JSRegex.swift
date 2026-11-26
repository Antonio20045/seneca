import Foundation

final class JSRegex {
    let re: NSRegularExpression

    init(_ muster: String, _ flags: String = "") {
        var opt: NSRegularExpression.Options = []
        if flags.contains("i") { opt.insert(.caseInsensitive) }
        let mehrzeilig = flags.contains("m")
        if mehrzeilig { opt.insert(.anchorsMatchLines) }
        re = try! NSRegularExpression(pattern: JSRegex.uebersetze(muster, mehrzeilig: mehrzeilig), options: opt)
    }

    static func uebersetze(_ p: String, mehrzeilig: Bool) -> String {
        let wort = "A-Za-z0-9_"
        var out = ""
        var inKlasse = false
        let c = Array(p)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == "\\", i + 1 < c.count {
                let n = c[i + 1]
                switch n {
                case "w": out += inKlasse ? wort : "[\(wort)]"
                case "d": out += inKlasse ? "0-9" : "[0-9]"
                case "b": out += inKlasse ? "\\x08" : "(?:(?<=[\(wort)])(?![\(wort)])|(?<![\(wort)])(?=[\(wort)]))"
                default: out += "\\\(n)"
                }
                i += 2
                continue
            }
            if inKlasse {
                if ch == "]" { inKlasse = false; out.append(ch) }
                else if ch == "[" { out += "\\[" }
                else { out.append(ch) }
                i += 1
                continue
            }
            if ch == "[" { inKlasse = true; out.append(ch); i += 1
                if i < c.count, c[i] == "^" { out.append("^"); i += 1 }
                continue
            }
            if ch == "$", !mehrzeilig { out += "\\z"; i += 1; continue }
            out.append(ch)
            i += 1
        }
        return out
    }

    private static let sperre = NSLock()
    nonisolated(unsafe) private static var ablage: [String: JSRegex] = [:]
    static func hole(_ muster: String, _ flags: String = "") -> JSRegex {
        let key = flags + "/" + muster
        sperre.lock(); defer { sperre.unlock() }
        if let r = ablage[key] { return r }
        let r = JSRegex(muster, flags)
        ablage[key] = r
        return r
    }
}

extension String {
    var jsLaenge: Int { utf16.count }

    func jsSlice(_ von: Int, _ bis: Int? = nil) -> String {
        let u = Array(utf16)
        let a = min(max(von, 0), u.count)
        let b = min(max(bis ?? u.count, a), u.count)
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    var jsTrim: String { trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))) }

    func jsStartsWith(_ s: String) -> Bool { Array(utf16).starts(with: Array(s.utf16)) }
    func jsEndsWith(_ s: String) -> Bool {
        let a = Array(utf16), b = Array(s.utf16)
        return b.count <= a.count && Array(a[(a.count - b.count)...]) == b
    }

    private var voll: NSRange { NSRange(location: 0, length: (self as NSString).length) }

    func passt(_ muster: String, _ flags: String = "") -> Bool {
        JSRegex.hole(muster, flags).re.firstMatch(in: self, range: voll) != nil
    }

    func treffer(_ muster: String, _ flags: String = "") -> [String?]? {
        guard let m = JSRegex.hole(muster, flags).re.firstMatch(in: self, range: voll) else { return nil }
        let ns = self as NSString
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }

    func trefferAnzahl(_ muster: String, _ flags: String = "") -> Int {
        JSRegex.hole(muster, flags).re.numberOfMatches(in: self, range: voll)
    }

    func ersetze(_ muster: String, _ vorlage: String, _ flags: String = "") -> String {
        let re = JSRegex.hole(muster, flags).re
        guard let m = re.firstMatch(in: self, range: voll) else { return self }
        let ns = self as NSString
        let neu = re.replacementString(for: m, in: self, offset: 0, template: vorlage)
        return ns.replacingCharacters(in: m.range, with: neu)
    }

    func ersetzeAlle(_ muster: String, _ vorlage: String, _ flags: String = "") -> String {
        JSRegex.hole(muster, flags).re.stringByReplacingMatches(in: self, range: voll, withTemplate: vorlage)
    }

    func teileNach(_ muster: String, _ flags: String = "") -> [String] {
        let ns = self as NSString
        var out: [String] = []
        var start = 0
        for m in JSRegex.hole(muster, flags).re.matches(in: self, range: voll) {
            if m.range.length == 0 { continue }
            out.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        out.append(ns.substring(from: start))
        return out
    }
}

func jsText(_ v: Any?) -> String {
    switch v {
    case nil, is NSNull: return ""
    case let s as String: return s
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        let d = n.doubleValue
        if d == d.rounded(), abs(d) < 1e15 { return String(n.int64Value) }
        return "\(d)"
    default: return ""
    }
}

func jsWahr(_ v: Any?) -> Bool {
    switch v {
    case nil, is NSNull: return false
    case let s as String: return !s.isEmpty
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        return n.doubleValue != 0 && !n.doubleValue.isNaN
    default: return true
    }
}

func jsErster(_ werte: Any?...) -> Any? {
    for w in werte { if let w, !(w is NSNull) { return w } }
    return nil
}
