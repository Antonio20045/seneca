import Foundation

enum Menschlich {
    static let tag: Double = 86_400_000
    static let monatKurz = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
    static let monatLang = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let wochentag = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let wochentagKurz = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    private static func datum(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

    static func tagStart(_ ms: Double, _ cal: Calendar = .current) -> Double {
        cal.startOfDay(for: datum(ms)).timeIntervalSince1970 * 1000
    }
    static func addTage(_ ms: Double, _ n: Int, _ cal: Calendar = .current) -> Double {
        let start = cal.startOfDay(for: datum(ms))
        return (cal.date(byAdding: .day, value: n, to: start) ?? start).timeIntervalSince1970 * 1000
    }
    static func isoTag(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: datum(ms))
        return "\(c.year ?? 1970)-\(pad(c.month ?? 1))-\(pad(c.day ?? 1))"
    }
    static func ausIso(_ s: String, _ cal: Calendar = .current) -> Double {
        guard let m = s.range(of: #"^(\d{4})-(\d{2})-(\d{2})"#, options: .regularExpression) else { return .nan }
        let t = s[m].split(separator: "-").compactMap { Int($0) }
        guard t.count == 3, let d = cal.date(from: DateComponents(year: t[0], month: t[1], day: t[2])) else { return .nan }
        return d.timeIntervalSince1970 * 1000
    }
    static func hhmm(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.hour, .minute], from: datum(ms))
        return "\(pad(c.hour ?? 0)):\(pad(c.minute ?? 0))"
    }
    static func minuteDesTages(_ ms: Double, _ cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: datum(ms))
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    static func datumKurz(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.day, .month], from: datum(ms))
        return "\(c.day ?? 1). \(monatKurz[(c.month ?? 1) - 1])"
    }
    static func datumLang(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.weekday, .day, .month], from: datum(ms))
        return "\(wochentag[(c.weekday ?? 1) - 1]), \(c.day ?? 1). \(monatLang[(c.month ?? 1) - 1])"
    }
    static func tageZwischen(_ von: Double, _ bis: Double, _ cal: Calendar = .current) -> Int {
        Int(((tagStart(bis, cal) - tagStart(von, cal)) / tag).rounded())
    }

    static func vorText(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        let min = Int(((jetzt - ms) / 60_000).rounded())
        if min < 1 { return "gerade eben" }
        if min < 60 { return "vor \(min) Min." }
        let h = Int((Double(min) / 60).rounded())
        if h < 24 && tagStart(ms, cal) == tagStart(jetzt, cal) { return "vor \(h) Std." }
        let t = tageZwischen(ms, jetzt, cal)
        if t == 1 { return "gestern, \(hhmm(ms, cal))" }
        if t < 7 { return "vor \(t) Tagen" }
        return datumKurz(ms, cal)
    }

    static func tagText(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        let t = tageZwischen(jetzt, ms, cal)
        if t == 0 { return "heute" }
        if t == 1 { return "morgen" }
        if t == -1 { return "gestern" }
        if t > 1 && t < 7 { return wochentag[cal.component(.weekday, from: datum(ms)) - 1] }
        return datumKurz(ms, cal)
    }

    static func ohnePfade(_ t: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(?:~|/Users/[^\s/]+)(?:/[^\s/),;]+)+"#) else { return t }
        var out = t
        let ns = t as NSString
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            let p = ns.substring(with: m.range)
            out = (out as NSString).replacingCharacters(in: m.range, with: p.split(separator: "/").last.map(String.init) ?? p)
        }
        return out
    }

    static func kuerzen(_ t: String, _ max: Int) -> String {
        let u = Array(t.utf16)
        if u.count <= max { return t }
        let cut = String(decoding: u[0..<max], as: UTF16.self)
        let sp = (cut as NSString).range(of: " ", options: .backwards)
        let m = Double(max) * 0.6
        let basis = (sp.location != NSNotFound && Double(sp.location) > m) ? (cut as NSString).substring(to: sp.location) : cut
        let ende = CharacterSet(charactersIn: " \t\n,;:–—-")
        var s = Substring(basis)
        while let l = s.unicodeScalars.last, ende.contains(l) { s = s.dropLast() }
        return String(s) + " …"
    }

    static func saetze(_ t: String) -> [String] {
        let eins = ersetze(t, #"\s+"#, " ")
        guard let re = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+"#) else { return [eins] }
        let ns = eins as NSString
        var teile: [String] = [], start = 0
        for m in re.matches(in: eins, range: NSRange(location: 0, length: ns.length)) {
            teile.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        teile.append(ns.substring(from: start))
        return teile.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func ersetze(_ s: String, _ muster: String, _ durch: String = "", ignoriereGross: Bool = false) -> String {
        s.replacingOccurrences(of: muster, with: durch, options: ignoriereGross ? [.regularExpression, .caseInsensitive] : .regularExpression)
    }

    static func klartext(_ t: String?) -> String {
        var s = ersetze(t ?? "", #"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, ignoriereGross: true)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = ersetze(s, #"^\[[^\]]*\]\s*"#)
        s = ersetze(s, #"^(Entscheidung|Aufgabe|Vorschlag|Idee)\s+[A-Z]{1,3}-\d+[a-z]?\s*[:–—-]\s*"#, ignoriereGross: true)
        s = ersetze(s, #"^[A-Z]{1,3}-\d+[a-z]?\s*[:–—]\s*"#)
        s = ersetze(s, #"^Entscheidung\s*:\s*"#, ignoriereGross: true)
        s = ersetze(s, #"^\(\s*[A-Z]{1,3}-\d+[a-z]?\s*\)\s*"#)
        s = ersetze(s, #"\s*[\(\[](?:[A-Z]{1,3}-\d+[a-z]?(?:[,/ ]+)?)+[\)\]]\s*$"#)
        s = ersetze(s, #"\s+[–—-]\s+[A-Z]{1,3}-\d+[a-z]?\s*$"#)
        s = ersetze(s, #"\s{2,}"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let erst = s.first else { return "" }
        return String(erst).uppercased() + s.dropFirst()
    }

    static func cleanName(_ s: String?) -> String {
        var rest = Substring(s ?? "")
        while let c = rest.unicodeScalars.first, c.properties.isEmojiPresentation || c.properties.isEmoji && c.value > 0x2000 || c == "\u{FE0F}" || c == "\u{200D}" || c == "·" || CharacterSet.whitespacesAndNewlines.contains(c) {
            rest = rest.dropFirst()
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func labelWert(_ labels: [String], _ praefix: String) -> String? {
        labels.first { $0.hasPrefix(praefix + ":") }.map { String($0.dropFirst(praefix.count + 1)) }
    }
    static func labelsMit(_ labels: [String], _ praefix: String, wert: String?) -> [String] {
        labels.filter { !$0.hasPrefix(praefix + ":") } + ((wert ?? "").isEmpty ? [] : ["\(praefix):\(wert!)"])
    }
    static func planVon(_ labels: [String]) -> Double? {
        guard let v = labelWert(labels, "plan") else { return nil }
        let ms = ausIso(v)
        return ms.isNaN ? nil : ms
    }
    static func fristVon(_ labels: [String]) -> Double? {
        guard let v = labelWert(labels, "frist") else { return nil }
        let ms = ausIso(v)
        return ms.isNaN ? nil : ms
    }
}
