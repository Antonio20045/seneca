import Foundation

enum Formate {
    static let wochentageLang = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let monate = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

    static func hhmm(_ ms: Double, kalender: Calendar = .current) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        return "\(pad(kalender.component(.hour, from: d))):\(pad(kalender.component(.minute, from: d)))"
    }

    static func hhmmss(_ ms: Double, kalender: Calendar = .current) -> String {
        hhmm(ms, kalender: kalender) + ":" + pad(kalender.component(.second, from: Date(timeIntervalSince1970: ms / 1000)))
    }

    static func tagesLabel(_ ms: Double, jetzt: Date = Date(), kalender: Calendar = .current) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let tage = kalender.dateComponents([.day], from: kalender.startOfDay(for: d), to: kalender.startOfDay(for: jetzt)).day ?? 0
        if tage == 0 { return "Heute" }
        if tage == 1 { return "Gestern" }
        let c = kalender.dateComponents([.weekday, .day, .month], from: d)
        return "\(wochentageLang[(c.weekday ?? 1) - 1]), \(c.day ?? 1). \(monate[(c.month ?? 1) - 1])"
    }

    static func trenner(_ ms: Double, vorher: Double?, jetzt: Date = Date(), kalender: Calendar = .current) -> String? {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let neuerTag = vorher.map { !kalender.isDate(Date(timeIntervalSince1970: $0 / 1000), inSameDayAs: d) } ?? true
        guard neuerTag || ms - (vorher ?? ms) > 3 * stunde else { return nil }
        let c = kalender.dateComponents([.weekday, .day, .month], from: d)
        let lang = "\(wochentageLang[(c.weekday ?? 1) - 1]), \(c.day ?? 1). \(kalender.monthSymbols[(c.month ?? 1) - 1])"
        let heute = kalender.isDate(d, inSameDayAs: jetzt)
        return (neuerTag ? (heute ? "Heute · " : "") + lang : hhmm(ms, kalender: kalender)).uppercased()
    }

    static let wochentageKurz = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    private static let stunde: Double = 3_600_000

    static func ago(_ ms: Double?, jetzt: Double = Date().timeIntervalSince1970 * 1000, kalender: Calendar = .current) -> String {
        guard let ms, ms != 0 else { return "" }
        let diff = jetzt - ms
        if diff < 60_000 { return "gerade eben" }
        if diff < stunde { return "vor \(jsRunde(diff / 60_000)) Min." }
        if diff < 24 * stunde { return "vor \(jsRunde(diff / stunde)) Std." }
        if diff < 48 * stunde { return "gestern" }
        let c = kalender.dateComponents([.day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        return "\(c.day ?? 1). \(monate[(c.month ?? 1) - 1])"
    }

    static func when(_ ms: Double, jetzt: Double = Date().timeIntervalSince1970 * 1000, kalender: Calendar = .current) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let tage = jsRunde((Menschlich.tagStart(ms, kalender) - Menschlich.tagStart(jetzt, kalender)) / (24 * stunde))
        if tage == 0 { return hhmm(ms, kalender: kalender) }
        if tage == 1 { return "morgen \(hhmm(ms, kalender: kalender))" }
        return "\(wochentageKurz[kalender.component(.weekday, from: d) - 1]) \(hhmm(ms, kalender: kalender))"
    }

    static func dayLabel(_ ms: Double, jetzt: Double = Date().timeIntervalSince1970 * 1000, kalender: Calendar = .current) -> String {
        tagesLabel(ms, jetzt: Date(timeIntervalSince1970: jetzt / 1000), kalender: kalender)
    }

    static func jsRunde(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    static func uhrzeit(_ ms: Double) -> String {
        let s = max(0, Int((ms / 1000).rounded()))
        return s < 60 ? "\(s) Sek." : "\(s / 60):\(pad(s % 60)) Min."
    }
}
