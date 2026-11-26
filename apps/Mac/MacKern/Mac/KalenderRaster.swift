import Foundation

enum KalAnsicht: String, CaseIterable, Sendable {
    case tag, woche, monat

    var name: String {
        switch self { case .tag: "Tag"; case .woche: "Woche"; case .monat: "Monat" }
    }
}

struct KalEreignis: Equatable, Identifiable, Sendable {
    var id: String
    var titel: String
    var start: Date
    var ende: Date
    var ganztags = false
    var kalender: String? = nil
    var kalenderId: String? = nil
    var farbe: UInt32? = nil
    var ort: String? = nil
    var notiz: String? = nil
    var aenderbar = false
    var serie = false
}

struct KalKalender: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var farbe: UInt32? = nil
    var schreibbar = true
}

struct KalEntwurf: Equatable, Sendable {
    var id: String? = nil
    var titel = ""
    var start: Date
    var ende: Date
    var ganztags = false
    var kalenderId: String? = nil
    var ort = ""
    var notiz = ""

    init(start: Date, ende: Date, ganztags: Bool = false, kalenderId: String? = nil) {
        self.start = start; self.ende = ende; self.ganztags = ganztags; self.kalenderId = kalenderId
    }

    init(_ e: KalEreignis) {
        id = e.id; titel = e.titel; start = e.start; ende = e.ende; ganztags = e.ganztags
        kalenderId = e.kalenderId; ort = e.ort ?? ""; notiz = e.notiz ?? ""
    }

    static let maxTitel = 200
    static let maxNotiz = 20_000

    var mangel: String? {
        if titel.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxTitel { return "Der Titel ist zu lang." }
        if ort.count > Self.maxTitel { return "Der Ort ist zu lang." }
        if notiz.count > Self.maxNotiz { return "Die Notizen sind zu lang." }
        if ganztags ? ende < start : ende <= start { return "Das Ende muss nach dem Beginn liegen." }
        return nil
    }

    var titelSauber: String {
        let t = titel.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Neuer Termin" : t
    }

    func angewandt(auf alt: KalEreignis?, kalender: [KalKalender]) -> KalEreignis {
        var e = alt ?? KalEreignis(id: id ?? "neu-\(start.timeIntervalSince1970)", titel: "", start: start, ende: ende, aenderbar: true)
        e.titel = titelSauber; e.start = start; e.ende = ende; e.ganztags = ganztags
        let o = ort.trimmingCharacters(in: .whitespacesAndNewlines), n = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        e.ort = o.isEmpty ? nil : o
        e.notiz = n.isEmpty ? nil : notiz
        if let k = kalender.first(where: { $0.id == kalenderId }) { e.kalenderId = k.id; e.kalender = k.name; e.farbe = k.farbe }
        return e
    }

    func geaendert(gegen e: KalEreignis?) -> Bool {
        guard let e else { return true }
        return self != KalEntwurf(e)
    }
}

struct KalStand: Equatable, Sendable {
    var ansicht: KalAnsicht
    var anker: Date

    init(ansicht: KalAnsicht = .woche, anker: Date, _ cal: Calendar) {
        self.ansicht = ansicht
        self.anker = cal.startOfDay(for: anker)
    }

    mutating func blaettere(_ n: Int, _ cal: Calendar) {
        switch ansicht {
        case .tag: anker = cal.date(byAdding: .day, value: n, to: anker)!
        case .woche: anker = cal.date(byAdding: .day, value: 7 * n, to: anker)!
        case .monat:
            anker = cal.date(byAdding: .month, value: n, to: KalRaster.monatsErster(anker, cal))!
        }
    }

    mutating func heute(_ jetzt: Date, _ cal: Calendar) { anker = cal.startOfDay(for: jetzt) }

    mutating func springe(_ tag: Date, _ cal: Calendar) { anker = cal.startOfDay(for: tag) }

    mutating func wechsle(_ neu: KalAnsicht, jetzt: Date, _ cal: Calendar) {
        guard neu != ansicht else { return }
        let heute = cal.startOfDay(for: jetzt)
        if KalRaster.kern(self, cal).contains(heute) { anker = heute }
        else if ansicht == .monat { anker = KalRaster.monatsErster(anker, cal) }
        else if ansicht == .woche, neu == .tag { anker = KalRaster.wochenStart(anker, cal) }
        ansicht = neu
    }
}

struct KalStueck: Equatable, Sendable {
    var id: String
    var von: Double
    var bis: Double
}

struct KalLage: Equatable, Sendable {
    var spur: Int
    var anzahl: Int
}

struct KalBalken: Equatable, Identifiable, Sendable {
    var id: String
    var von: Int
    var bis: Int
    var zeile: Int
    var davor = false
    var danach = false
}

enum KalRaster {
    static let wochentageKurz = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let wochentageLang = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let monate = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    static func kalender(_ zone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "de_DE")
        return c
    }

    static func wochenStart(_ d: Date, _ cal: Calendar) -> Date {
        let tag = cal.startOfDay(for: d)
        let seitMontag = (cal.component(.weekday, from: tag) + 5) % 7
        return cal.date(byAdding: .day, value: -seitMontag, to: tag)!
    }

    static func monatsErster(_ d: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? cal.startOfDay(for: d)
    }

    static func wochentag(_ d: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: d) + 5) % 7 }

    static func kalenderwoche(_ d: Date, _ cal: Calendar) -> Int { cal.component(.weekOfYear, from: d) }

    static func tage(_ s: KalStand, _ cal: Calendar) -> [Date] {
        switch s.ansicht {
        case .tag: return [s.anker]
        case .woche:
            let m = wochenStart(s.anker, cal)
            return (0..<7).map { cal.date(byAdding: .day, value: $0, to: m)! }
        case .monat:
            let erster = monatsErster(s.anker, cal)
            let naechster = cal.date(byAdding: .month, value: 1, to: erster)!
            var out: [Date] = []
            var w = wochenStart(erster, cal)
            while w < naechster {
                out += (0..<7).map { cal.date(byAdding: .day, value: $0, to: w)! }
                w = cal.date(byAdding: .day, value: 7, to: w)!
            }
            return out
        }
    }

    static func zeitraum(_ s: KalStand, _ cal: Calendar) -> DateInterval {
        let t = tage(s, cal)
        return DateInterval(start: t[0], end: cal.date(byAdding: .day, value: 1, to: t[t.count - 1])!)
    }

    static func kern(_ s: KalStand, _ cal: Calendar) -> DateInterval {
        guard s.ansicht == .monat else { return zeitraum(s, cal) }
        let erster = monatsErster(s.anker, cal)
        return DateInterval(start: erster, end: cal.date(byAdding: .month, value: 1, to: erster)!)
    }

    static func titel(_ s: KalStand, _ cal: Calendar) -> String {
        func t(_ d: Date) -> (tag: Int, monat: String, jahr: Int) {
            (cal.component(.day, from: d), monate[cal.component(.month, from: d) - 1], cal.component(.year, from: d))
        }
        switch s.ansicht {
        case .tag:
            let a = t(s.anker)
            return "\(wochentageLang[wochentag(s.anker, cal)]), \(a.tag). \(a.monat) \(a.jahr)"
        case .woche:
            let tg = tage(s, cal)
            let a = t(tg[0]), b = t(tg[6])
            if a.jahr != b.jahr { return "\(a.tag). \(a.monat) \(a.jahr) bis \(b.tag). \(b.monat) \(b.jahr)" }
            if a.monat != b.monat { return "\(a.tag). \(a.monat) bis \(b.tag). \(b.monat) \(b.jahr)" }
            return "\(a.tag). bis \(b.tag). \(b.monat) \(b.jahr)"
        case .monat:
            let a = t(s.anker)
            return "\(a.monat) \(a.jahr)"
        }
    }

    static func stunde(_ d: Date, _ cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    static func zeit(_ tag: Date, stunde h: Double, _ cal: Calendar) -> Date {
        let tag0 = cal.startOfDay(for: tag)
        let minuten = Int((h * 60).rounded())
        if minuten >= 24 * 60 { return cal.date(byAdding: .day, value: 1, to: tag0)! }
        if minuten <= 0 { return tag0 }
        return cal.date(bySettingHour: minuten / 60, minute: minuten % 60, second: 0, of: tag0, matchingPolicy: .nextTime) ?? tag0.addingTimeInterval(Double(minuten) * 60)
    }

    static func raste(_ h: Double, minuten: Int = 15) -> Double {
        let s = Double(minuten) / 60
        return min(24, max(0, (h / s).rounded() * s))
    }

    static func uhr(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }

    static func uhr(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func liesUhr(_ text: String) -> Double? {
        let t = text.lowercased().replacingOccurrences(of: "uhr", with: "").trimmingCharacters(in: .whitespaces)
        let teile = t.split(whereSeparator: { ":.,h ".contains($0) }).map(String.init)
        var h: Int?, m: Int? = 0
        if teile.count == 1, teile[0].allSatisfy(\.isNumber) {
            let z = teile[0]
            if z.count <= 2 { h = Int(z) } else if z.count <= 4 { h = Int(z.dropLast(2)); m = Int(z.suffix(2)) }
        } else if teile.count == 2 { h = Int(teile[0]); m = Int(teile[1]) }
        guard let h, let m, (0...23).contains(h), (0...59).contains(m) else { return nil }
        return Double(h) + Double(m) / 60
    }

    static func tagKurz(_ d: Date, _ cal: Calendar) -> String {
        "\(wochentageKurz[wochentag(d, cal)])., \(cal.component(.day, from: d)). \(monate[cal.component(.month, from: d) - 1])"
    }

    static func dauer(_ minuten: Int) -> String {
        let h = minuten / 60, m = minuten % 60
        if h == 0 { return "\(m) Min." }
        return m == 0 ? "\(h) Std." : "\(h) Std. \(m) Min."
    }

    static func istBalken(_ e: KalEreignis) -> Bool { e.ganztags || e.ende.timeIntervalSince(e.start) >= 86_400 }

    static func letzterTag(_ e: KalEreignis, _ cal: Calendar) -> Date {
        let s = cal.startOfDay(for: e.start)
        guard e.ende > e.start else { return s }
        return max(s, cal.startOfDay(for: e.ende.addingTimeInterval(-1)))
    }

    static func beruehrt(_ e: KalEreignis, tag: Date, _ cal: Calendar) -> Bool {
        let t = cal.startOfDay(for: tag)
        return cal.startOfDay(for: e.start) <= t && t <= letzterTag(e, cal)
    }

    static func amTag(_ liste: [KalEreignis], tag: Date, _ cal: Calendar) -> [KalEreignis] {
        liste.filter { beruehrt($0, tag: tag, cal) }.sorted {
            let a = istBalken($0), b = istBalken($1)
            if a != b { return a }
            return ($0.start, $0.titel, $0.id) < ($1.start, $1.titel, $1.id)
        }
    }

    static func stueck(_ e: KalEreignis, tag: Date, _ cal: Calendar) -> KalStueck? {
        guard !istBalken(e), beruehrt(e, tag: tag, cal) else { return nil }
        let t0 = cal.startOfDay(for: tag), t1 = cal.date(byAdding: .day, value: 1, to: t0)!
        let von = e.start <= t0 ? 0 : stunde(e.start, cal)
        let bis = e.ende >= t1 ? 24 : max(von, stunde(e.ende, cal))
        return KalStueck(id: e.id, von: von, bis: bis)
    }

    static func spuren(_ stuecke: [KalStueck], mindest: Double = 0.5) -> [String: KalLage] {
        let l = stuecke.map { KalStueck(id: $0.id, von: $0.von, bis: max($0.bis, $0.von + mindest)) }
            .sorted { ($0.von, -$0.bis, $0.id) < ($1.von, -$1.bis, $1.id) }
        var out: [String: KalLage] = [:]
        var gruppe: [(id: String, spur: Int)] = []
        var enden: [Double] = []
        var gruppenEnde = -Double.infinity
        func schliesse() {
            for g in gruppe { out[g.id] = KalLage(spur: g.spur, anzahl: enden.count) }
            gruppe = []; enden = []
        }
        for s in l {
            if s.von >= gruppenEnde { schliesse() }
            if let k = enden.firstIndex(where: { $0 <= s.von }) { enden[k] = s.bis; gruppe.append((s.id, k)) }
            else { gruppe.append((s.id, enden.count)); enden.append(s.bis) }
            gruppenEnde = max(gruppenEnde, s.bis)
        }
        schliesse()
        return out
    }

    static func balken(_ liste: [KalEreignis], tage: [Date], _ cal: Calendar) -> [KalBalken] {
        guard let erster = tage.first, let letzter = tage.last else { return [] }
        func spalte(_ d: Date) -> Int { cal.dateComponents([.day], from: erster, to: d).day ?? 0 }
        let roh = liste.filter(istBalken).compactMap { e -> KalBalken? in
            let a = cal.startOfDay(for: e.start), b = letzterTag(e, cal)
            guard a <= letzter, b >= erster else { return nil }
            return KalBalken(id: e.id, von: max(0, spalte(a)), bis: min(tage.count - 1, spalte(b)), zeile: 0, davor: a < erster, danach: b > letzter)
        }
        .sorted { ($0.von, -($0.bis - $0.von), $0.id) < ($1.von, -($1.bis - $1.von), $1.id) }
        var belegt: [Int] = []
        return roh.map { b in
            var b = b
            if let z = belegt.firstIndex(where: { $0 < b.von }) { b.zeile = z; belegt[z] = b.bis }
            else { b.zeile = belegt.count; belegt.append(b.bis) }
            return b
        }
    }

    static func monatsZeilen(anzahl: Int, platz: Int) -> (zeigen: Int, mehr: Int) {
        if anzahl <= max(0, platz) { return (anzahl, 0) }
        let zeigen = max(0, platz - 1)
        return (zeigen, anzahl - zeigen)
    }

    static func ersteStunde(_ liste: [KalEreignis], tage: [Date], jetzt: Date, sichtbar: Double, _ cal: Calendar) -> Double {
        let heute = cal.startOfDay(for: jetzt)
        var h = 7.0
        if tage.contains(heute) {
            h = stunde(jetzt, cal) - 1
            let offen = liste.compactMap { stueck($0, tag: heute, cal) }.filter { $0.bis > stunde(jetzt, cal) }.map(\.von).min()
            if let o = offen, o - 0.5 < h { h = o - 0.5 }
        } else if let frueh = tage.flatMap({ t in liste.compactMap { stueck($0, tag: t, cal) } }).map(\.von).min() {
            h = min(9, frueh - 0.5)
        }
        return max(0, min(h, 24 - min(24, sichtbar)))
    }

    static func verschoben(_ e: KalEreignis, auf tag: Date, stunde h: Double, _ cal: Calendar) -> (start: Date, ende: Date) {
        let s = zeit(tag, stunde: h, cal)
        return (s, s.addingTimeInterval(e.ende.timeIntervalSince(e.start)))
    }

    static func verschoben(_ e: KalEreignis, umTage n: Int, _ cal: Calendar) -> (start: Date, ende: Date) {
        (cal.date(byAdding: .day, value: n, to: e.start)!, cal.date(byAdding: .day, value: n, to: e.ende)!)
    }

    static func verlaengert(_ e: KalEreignis, tag: Date, bis h: Double, _ cal: Calendar) -> Date {
        max(zeit(tag, stunde: h, cal), e.start.addingTimeInterval(15 * 60))
    }

    static func neu(tag: Date, von a: Double, bis b: Double?, _ cal: Calendar) -> (start: Date, ende: Date) {
        guard let b, abs(b - a) >= 0.25 else {
            let v = min(23, (a * 2).rounded(.down) / 2)
            return (zeit(tag, stunde: v, cal), zeit(tag, stunde: v + 1, cal))
        }
        let v = raste(min(a, b)), bis = max(raste(max(a, b)), v + 0.25)
        return (zeit(tag, stunde: v, cal), zeit(tag, stunde: bis, cal))
    }

    static func links(_ text: String) -> [(bereich: Range<String.Index>, url: URL)] {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return d.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let u = m.url, let r = Range(m.range, in: text) else { return nil }
            return (r, u)
        }
    }
}
