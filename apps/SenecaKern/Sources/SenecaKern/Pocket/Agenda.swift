import Foundation

struct AgendaInput {
    var now: Date
    var calendar: Calendar
    var termine: [KalenderTermin]
    var vergangen: [KalenderTermin]? = nil
    var vergangenAb: Date? = nil
    var jobs: [AgentJob] = []
    var termineBis: Date? = nil
}

enum AgendaLogic {
    static func items(on day: Date, _ input: AgendaInput) -> [KalenderItem] {
        let cal = input.calendar
        let start = cal.startOfDay(for: day)
        if start < cal.startOfDay(for: input.now) {
            guard let vergangen = input.vergangen, deckt(start, input) else { return [] }
            return KalenderLogic.items(on: start, termine: vergangen, jobs: [], cal)
        }
        return KalenderLogic.items(on: start, termine: input.termine, jobs: input.jobs, cal)
    }

    static func laeuft(_ input: AgendaInput) -> KalenderItem? {
        items(on: input.now, input).filter { KalenderLogic.isRunning($0, now: input.now) }.max { $0.start < $1.start }
    }

    static func alsNaechstes(_ input: AgendaInput, nurHeute: Bool = true) -> KalenderItem? {
        let cal = input.calendar
        let tage = nurHeute ? 1 : 7
        for offset in 0..<tage {
            let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: input.now))!
            if let next = items(on: day, input).first(where: { $0.isTimed && $0.start > input.now }) { return next }
        }
        return nil
    }

    static func deckt(_ dayStart: Date, _ input: AgendaInput) -> Bool {
        if dayStart >= input.calendar.startOfDay(for: input.now) { return true }
        guard input.vergangen != nil, let ab = input.vergangenAb else { return false }
        return dayStart >= input.calendar.startOfDay(for: ab)
    }

    static func bekannt(_ dayStart: Date, _ input: AgendaInput) -> Bool {
        guard let bis = input.termineBis else { return true }
        return dayStart < input.calendar.startOfDay(for: bis)
    }
}

enum AgendaAnsicht: Equatable, Hashable {
    case heute, woche
    case monat(Int)
    case tag(Date)
}

struct AgendaEintrag: Identifiable, Equatable {
    var id: String
    var titel: String
    var tag: Date
    var start: Date? = nil
    var ende: Date? = nil
    var ganztags: Bool
    var ort: String? = nil
    var vorbei: Bool
    var laeuft: Bool
    var item: KalenderItem
    var mehrtaegig: Bool { ganztags && item.end.timeIntervalSince(item.start) > 36 * 3600 }
    var letzterTag: Date { item.end.addingTimeInterval(-1) }
}

struct AgendaHeld: Equatable {
    var vorn: String
    var akzent: String
    var text: String { vorn + akzent }

    init(vorn: String, akzent: String) { self.vorn = vorn; self.akzent = akzent }

    init(titel: String) {
        let t = titel.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: " ", options: .backwards) {
            vorn = String(t[..<r.upperBound]); akzent = String(t[r.upperBound...])
        } else {
            vorn = ""; akzent = t
        }
    }
}

struct AgendaTageszeile: Identifiable, Equatable {
    var id: Date { tag }
    var tag: Date
    var heute: Bool
    var vergangen: Bool
    var bekannt: Bool
    var eintraege: [AgendaEintrag]
}

struct AgendaMonatTag: Equatable {
    var tag: Date
    var nummer: Int
    var hatTermin: Bool
    var reise: Bool
    var reiseEnde: Bool
    var heute: Bool
    var vergangen: Bool
}
struct AgendaMonatBild: Equatable {
    var versatz: Int
    var tage: [AgendaMonatTag]
}

struct AgendaSicht: Equatable {
    var ansicht: AgendaAnsicht
    var etikett: String
    var held: AgendaHeld?
    var satz: String
    var listenTitel: String
    var eintraege: [AgendaEintrag]
    var wochentage: [AgendaTageszeile]
    var monat: AgendaMonatBild?
}

extension AgendaLogic {
    static func sicht(_ ansicht: AgendaAnsicht, _ input: AgendaInput) -> AgendaSicht {
        let cal = input.calendar
        switch ansicht {
        case .heute: return tagSicht(cal.startOfDay(for: input.now), ansicht: .heute, input)
        case .tag(let d):
            let start = cal.startOfDay(for: d)
            if cal.isDate(start, inSameDayAs: input.now) { return tagSicht(start, ansicht: .heute, input) }
            return tagSicht(start, ansicht: .tag(start), input)
        case .woche: return wochenSicht(input)
        case .monat(let versatz): return monatsSicht(input, versatz: versatz)
        }
    }

    static func eintraege(_ day: Date, _ input: AgendaInput) -> [AgendaEintrag] {
        let cal = input.calendar
        let start = cal.startOfDay(for: day)
        let now = input.now
        return items(on: start, input)
            .filter { $0.kind == .termin || $0.kind == .ganztags }
            .map { item in
                let ganz = item.kind == .ganztags
                return AgendaEintrag(id: item.id, titel: item.title, tag: start, start: ganz ? nil : item.start, ende: ganz ? nil : item.end,
                                     ganztags: ganz, ort: item.place, vorbei: ganz ? start < cal.startOfDay(for: now) : item.end <= now,
                                     laeuft: KalenderLogic.isRunning(item, now: now), item: item)
            }
            .sorted { ($0.ganztags ? 0 : 1, $0.start ?? start) < ($1.ganztags ? 0 : 1, $1.start ?? start) }
    }

    private static func tagSicht(_ day: Date, ansicht: AgendaAnsicht, _ input: AgendaInput) -> AgendaSicht {
        let cal = input.calendar
        let heute = ansicht == .heute
        let vergangen = day < cal.startOfDay(for: input.now)
        let alle = eintraege(day, input)
        let wochentag = KalenderLogic.weekdayLong[cal.component(.weekday, from: day) - 1]
        let istBekannt = deckt(day, input) && bekannt(day, input)
        let datum = "\(wochentag), \(cal.component(.day, from: day)). \(KalenderLogic.monthName(day, cal))"

        var held: AgendaHeld?
        var satz: String
        let zeitig = alle.filter { !$0.ganztags }
        let wahl: AgendaEintrag? = heute
            ? (zeitig.last(where: { $0.laeuft }) ?? zeitig.first(where: { !$0.vorbei }) ?? alle.first(where: { $0.ganztags && !$0.vorbei }))
            : (zeitig.first ?? alle.first)
        if let e = wahl {
            held = AgendaHeld(titel: e.titel)
            satz = terminSatz(e, heute: heute, wochentag: wochentag, cal)
        } else if !istBekannt {
            satz = vergangen ? "Die Termine dieses Tages sind gerade nicht geladen." : KalenderLogic.unknownDay
        } else if heute {
            held = AgendaHeld(vorn: "Der Tag gehört ", akzent: "dir")
            satz = alle.isEmpty ? "Für heute ist nichts eingetragen." : "Für heute steht nichts mehr an."
        } else {
            held = AgendaHeld(vorn: "Der Tag gehört ", akzent: "dir")
            satz = vergangen ? "An diesem \(wochentag) war nichts eingetragen." : "An diesem \(wochentag) steht nichts im Kalender."
        }
        let alleVorbei = !alle.isEmpty && alle.allSatisfy(\.vorbei)
        let titel = heute ? (alleVorbei ? "Heute stand an" : "Heute steht an") : vergangen ? "An diesem Tag stand an" : "Am \(wochentag) steht an"
        return AgendaSicht(ansicht: ansicht, etikett: datum, held: held, satz: satz, listenTitel: alle.isEmpty ? "" : titel, eintraege: alle,
                           wochentage: [], monat: nil)
    }

    static func terminSatz(_ e: AgendaEintrag, heute: Bool, wochentag: String, _ cal: Calendar) -> String {
        let ort = ortTeil(e.ort, titel: e.titel)
        if e.ganztags {
            if e.mehrtaegig {
                return "Eingetragen vom \(tagMonat(e.item.start, cal, mitMonat: !gleicherMonat(e.item.start, e.letzterTag, cal))) bis \(tagMonat(e.letzterTag, cal))\(ort.map { ", \($0)" } ?? "")."
            }
            return "Ganztägig eingetragen" + (ort.map { ", \($0)" } ?? "") + "."
        }
        guard let start = e.start, let ende = e.ende else { return "" }
        let wann = heute ? (e.laeuft ? "Seit" : "Um") : "Am \(wochentag) um"
        let bis = cal.isDate(start, inSameDayAs: ende) ? "eingetragen bis \(DayLogic.hm(ende, cal)) Uhr" : "eingetragen bis \(tagMonat(ende, cal)), \(DayLogic.hm(ende, cal)) Uhr"
        return "\(wann) \(DayLogic.hm(start, cal)) Uhr\(ort.map { " \($0)" } ?? ""), \(bis)."
    }

    private static func wochenSicht(_ input: AgendaInput) -> AgendaSicht {
        let cal = input.calendar
        let heute = cal.startOfDay(for: input.now)
        let start = KalenderLogic.weekStart(input.now, cal)
        let tage: [AgendaTageszeile] = KalenderLogic.weekDays(start, cal).map { d in
            AgendaTageszeile(tag: d, heute: d == heute, vergangen: d < heute, bekannt: deckt(d, input) && bekannt(d, input),
                             eintraege: eintraege(d, input))
        }
        let alle = tage.flatMap(\.eintraege)
        var held: AgendaHeld?
        var satz: String
        if let e = schoenster(alle.filter { !$0.vorbei }, cal) ?? schoenster(alle, cal) {
            held = AgendaHeld(titel: e.titel)
            let rest = tage.first { cal.isDate($0.tag, inSameDayAs: e.tag) }?.eintraege.filter { $0.id != e.id && !$0.vorbei } ?? []
            satz = "Das steht \(tagWort(e.tag, input)) \(e.ganztags ? "" : "um \(DayLogic.hm(e.start!, cal)) Uhr ")an"
            satz += e.ganztags ? ", ganztägig" : ""
            if let ort = ortTeil(e.ort, titel: e.titel) { satz += ", \(ort)" }
            satz += "."
            if let z = rest.first {
                satz += z.ganztags ? " Am selben Tag steht außerdem \(z.titel) an." : " Am selben Tag kommt außerdem \(z.titel) um \(DayLogic.hm(z.start!, cal)) Uhr."
            }
        } else if !tage.contains(where: { $0.bekannt }) {
            satz = KalenderLogic.unknownDay
        } else {
            held = AgendaHeld(vorn: "Die Woche gehört ", akzent: "dir")
            satz = "In dieser Woche steht noch nichts im Kalender."
        }
        return AgendaSicht(ansicht: .woche, etikett: KalenderLogic.weekLine(start, cal), held: held, satz: satz, listenTitel: "",
                           eintraege: [], wochentage: tage, monat: nil)
    }

    static func schoenster(_ liste: [AgendaEintrag], _ cal: Calendar = .current) -> AgendaEintrag? {
        func punkte(_ e: AgendaEintrag) -> Int {
            var p = 0
            let t = e.titel.lowercased()
            if e.mehrtaegig { p += 60 } else if e.ganztags { p += 40 }
            if ["geburtstag", "hochzeit", "urlaub", "reise", "konzert", "fest", "feier", "party", "kino", "theater", "essen", "brunch",
                "ausflug", "flug", "lesung", "markt"].contains(where: { t.contains($0) }) { p += 30 }
            if let s = e.start {
                if cal.component(.hour, from: s) >= 17 { p += 8 }
                if cal.isDateInWeekend(s) { p += 10 }
            }
            return p
        }
        return liste.enumerated().max { a, b in
            let pa = punkte(a.element), pb = punkte(b.element)
            return pa != pb ? pa < pb : a.offset > b.offset
        }?.element
    }

    static func monatErlaubt(_ versatz: Int, _ input: AgendaInput) -> Bool {
        let cal = input.calendar
        guard let start = cal.date(byAdding: .month, value: versatz, to: KalenderLogic.monthStart(input.now, cal)) else { return false }
        return versatz < 0 ? deckt(start, input) : bekannt(cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start, input)
    }

    private static func monatsSicht(_ input: AgendaInput, versatz: Int) -> AgendaSicht {
        let cal = input.calendar
        let heute = cal.startOfDay(for: input.now)
        let start = cal.date(byAdding: .month, value: versatz, to: KalenderLogic.monthStart(input.now, cal)) ?? KalenderLogic.monthStart(input.now, cal)
        let tage = (0..<(cal.range(of: .day, in: .month, for: start)?.count ?? 30)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let proTag = Dictionary(uniqueKeysWithValues: tage.map { ($0, eintraege($0, input)) })
        let monatsname = KalenderLogic.monthName(start, cal)
        let bild = AgendaMonatBild(versatz: (cal.component(.weekday, from: start) + 5) % 7, tage: tage.enumerated().map { i, d in
            let eintrag = proTag[d] ?? []
            let reise = eintrag.first { $0.mehrtaegig }
            let morgenReise = i + 1 < tage.count && (proTag[tage[i + 1]] ?? []).contains { $0.mehrtaegig && $0.titel == reise?.titel }
            return AgendaMonatTag(tag: d, nummer: i + 1, hatTermin: eintrag.contains { !$0.mehrtaegig }, reise: reise != nil,
                                  reiseEnde: reise != nil && !morgenReise, heute: d == heute, vergangen: d < heute)
        })
        func kommend(ab: Date) -> [AgendaEintrag] {
            tage.filter { $0 > ab }.flatMap { d in
                (proTag[d] ?? []).filter { !$0.mehrtaegig || cal.isDate($0.item.start, inSameDayAs: d) }
            }
        }
        if versatz != 0 {
            let alle = kommend(ab: cal.date(byAdding: .day, value: -1, to: start) ?? start)
            let war = versatz < 0 ? "stand" : "steht"
            return AgendaSicht(ansicht: .monat(versatz), etikett: KalenderLogic.monthLine(start, cal), held: nil, satz: alle.isEmpty ? "Im \(monatsname) \(war) nichts im Kalender." : "",
                               listenTitel: alle.isEmpty ? "" : "Im \(monatsname)", eintraege: alle, wochentage: [], monat: bild)
        }
        let wochenEnde = KalenderLogic.weekDays(KalenderLogic.weekStart(input.now, cal), cal).last ?? heute
        let kommend = kommend(ab: wochenEnde).isEmpty ? kommend(ab: heute) : kommend(ab: wochenEnde)
        var held: AgendaHeld?
        var satz: String
        var danach: [AgendaEintrag] = []
        if let e = schoenster(kommend, cal) {
            held = AgendaHeld(titel: e.titel)
            let letzter = e.mehrtaegig ? cal.startOfDay(for: e.letzterTag) : e.tag
            let wann = e.mehrtaegig ? "vom \(tagMonat(e.tag, cal, mitMonat: !gleicherMonat(e.tag, letzter, cal))) bis \(tagMonat(letzter, cal))" : "am \(tagMonat(e.tag, cal))"
            danach = kommend.filter { $0.tag > letzter }
            satz = "Das steht \(wann) im Kalender"
            if let n = danach.first { satz += ", danach folgt am \(tagMonat(n.tag, cal)) \(n.titel)" }
            satz += "."
            danach = Array(danach.prefix(6))
        } else if !tage.contains(where: { $0 > heute && bekannt($0, input) }) {
            satz = KalenderLogic.unknownDay
        } else {
            held = AgendaHeld(vorn: "Der Rest vom \(monatsname) ist ", akzent: "frei")
            satz = "Im \(monatsname) steht nichts mehr im Kalender."
        }
        return AgendaSicht(ansicht: .monat(0), etikett: KalenderLogic.monthLine(start, cal), held: held, satz: satz,
                           listenTitel: danach.isEmpty ? "" : "Danach im \(monatsname)", eintraege: danach, wochentage: [], monat: bild)
    }

    static func tagWort(_ d: Date, _ input: AgendaInput) -> String {
        let cal = input.calendar
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: input.now), to: cal.startOfDay(for: d)).day ?? 9
        if diff == 0 { return "heute" }
        if diff == 1 { return "morgen" }
        return "am \(KalenderLogic.weekdayLong[cal.component(.weekday, from: d) - 1])"
    }

    static func tagMonat(_ d: Date, _ cal: Calendar, mitMonat: Bool = true) -> String {
        "\(cal.component(.day, from: d)).\(mitMonat ? " " + KalenderLogic.monthName(d, cal) : "")"
    }
    private static func gleicherMonat(_ a: Date, _ b: Date, _ cal: Calendar) -> Bool { cal.isDate(a, equalTo: b, toGranularity: .month) }

    static func ortTeil(_ ort: String?, titel: String) -> String? {
        guard let o = ort?.trimmingCharacters(in: .whitespaces), !o.isEmpty, !titel.localizedCaseInsensitiveContains(o) else { return nil }
        let wort = o.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        let vorwoerter = ["bei", "beim", "in", "im", "am", "an", "auf", "zu", "zum", "zur", "vor", "unter", "über", "hinter", "neben", "mit", "ins"]
        if vorwoerter.contains(wort) { return o }
        if ["haus", "café", "cafe", "kino", "büro", "theater", "museum", "studio", "hotel", "zentrum", "restaurant", "zimmer", "stadion"].contains(where: { wort.hasSuffix($0) })
            || ["park", "garten", "kiosk", "bahnhof", "flughafen", "salon", "zoo", "strand", "club", "saal", "raum"].contains(where: { wort.hasSuffix($0) }) { return "im \(o)" }
        if ["praxis", "schule", "trattoria", "pizzeria", "bar", "kneipe", "bibliothek", "kirche", "universität", "wohnung", "küche", "halle", "arena",
            "philharmonie", "oper", "galerie", "apotheke", "bäckerei", "firma", "agentur", "kantine", "gaststätte", "werkstatt"].contains(where: { wort.hasSuffix($0) }) { return "in der \(o)" }
        return o.contains(" ") ? "Ort: \(o)" : "in \(o)"
    }
}
