import Foundation

struct Arbeitsplan: Equatable {
    enum Stand: Int, Equatable { case wartetAufDich, laeuft, haengt, alsNaechstes, vorrat, fertig }

    struct Aufgabe: Identifiable, Equatable {
        let id: String
        var titel: String
        var stand: Stand
        var wer = ""
        var werName = ""
        var frist: Double?
        var seit: Double?
        var beleg: String?
        var istEntscheidung = false
        var belege: [String] = []
        var geprueft = false
        var inPruefung = false
        var inRunden = false
        var wortlaut = ""
        var satzArt = ""
    }

    struct Projekt: Identifiable, Equatable {
        let id: String
        var name: String
        var ziel = ""
        var frist: Double?
        var meilensteine: [OvMeilenstein] = []
        var aufgaben: [Aufgabe] = []
        var ohneProjekt = false

        func mit(_ s: Stand) -> [Aufgabe] { aufgaben.filter { $0.stand == s } }
        var offen: Int { aufgaben.filter { $0.stand != .fertig && $0.stand != .vorrat }.count }
    }

    struct Bereich: Identifiable, Equatable {
        let id: String
        var name: String
        var projekte: [Projekt]
    }

    var bereiche: [Bereich] = []

    var projekte: [Projekt] { bereiche.flatMap(\.projekte) }
    var wartetAufDich: Int { projekte.reduce(0) { $0 + $1.mit(.wartetAufDich).count } }

    static func istTest(_ name: String, id: String) -> Bool {
        let worte = name.lowercased().split { !$0.isLetter }.map(String.init)
        return worte.contains { $0 == "test" || $0 == "tests" || $0.hasSuffix("test") || $0.hasPrefix("testprojekt") || $0 == "probe" || $0 == "demo" }
            || id.lowercased().hasPrefix("test")
    }

    static func titel(_ roh: String?, max: Int = 120) -> String {
        var s = Menschlich.klartext(roh)
        for muster in [#"^Auftrag an [^:]{1,40}:\s*"#, #"^(?:[A-Z]{1,6}-?\d+[a-z]?\s+){0,2}[A-Z]{1,6}-?\d+[a-z]?\s*(\([^)]{0,40}\))?\s*[:–]\s*"#,
                       #"^[A-Z]{1,6}-?\d+[a-z]?\s*(\([^)]{0,40}\))?\s*[:–]\s*"#, #"^\([^)]{0,30}\)\s*:?\s*"#,
                       #"\s*\((?:PR|Issue|Paket)?\s*#\d+\)"#, #"\s*(?:PR|Issue)\s*#?\d{2,}\b"#, #"[,\s]*#\d{3,}\b"#] {
            s = s.replacingOccurrences(of: muster, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"\s*\([^)]*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = s.first, e.isLowercase { s = e.uppercased() + s.dropFirst() }
        return Menschlich.kuerzen(s, max)
    }

    static func ganzeSaetze(_ text: String, max: Int = 260) -> String {
        let t = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        var aus = ""
        var rest = Substring(t)
        while let r = rest.range(of: #"^.+?(?<![0-9])(?<!\b\p{L})[.!?](?=\s+[A-ZÄÖÜ„"]|\s*$)"#, options: .regularExpression) {
            let satz = rest[r]
            if aus.count + satz.count > max { break }
            aus += satz
            rest = rest[r.upperBound...]
            if rest.isEmpty { break }
        }
        let fertig = aus.trimmingCharacters(in: .whitespaces)
        if !fertig.isEmpty, fertig.count >= 40 || fertig.count == t.count { return fertig }
        return TageslaufSicht.gekuerzt(t, auf: max)
    }

    static func istPruefkarte(_ c: OvKarte) -> Bool { c.labels.contains("pruefkarte") || c.title.hasPrefix("Prüfung: ") }

    static func beleg(_ c: OvKarte) -> String? {
        if let n = c.nachweise.last(where: { $0.status != "failed" && $0.status != "skipped" }) {
            let t = Menschlich.klartext([n.note, n.label].compactMap { $0 }.first { !$0.isEmpty } ?? "")
            if !t.isEmpty { return ganzeSaetze(Menschlich.ohnePfade(t)) }
        }
        let ergebnis = c.kommentare.sorted { $0.createdAt < $1.createdAt }.last { k in
            let b = k.body.lowercased()
            return b.hasPrefix("ergebnis") || b.hasPrefix("beleg") || b.hasPrefix("erledigt") || b.hasPrefix("fertig")
        }
        guard let k = ergebnis else { return nil }
        let t = Menschlich.klartext(k.body).replacingOccurrences(of: #"^(Ergebnis|Beleg|Erledigt|Fertig)\s*(\([^)]{0,40}\))?\s*[:.]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        let satz = ganzeSaetze(Menschlich.ohnePfade(t))
        return satz.isEmpty ? nil : satz
    }

    static func vorliegend(_ c: OvKarte) -> String? {
        if c.nachweise.contains(where: { $0.status == "passed" }) { return beleg(c) }
        let k = c.kommentare.sorted { $0.createdAt < $1.createdAt }.last { k in
            let b = k.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return !b.hasPrefix("Verteiler:") && !b.hasPrefix("Lebenszeichen") && (k.author ?? "") != "verteiler"
        }
        guard let k else { return nil }
        let satz = ganzeSaetze(Menschlich.ohnePfade(Menschlich.klartext(k.body)))
        return satz.isEmpty ? nil : satz
    }

    static func ruhtBis(_ c: OvKarte, _ cal: Calendar = .current) -> Double? {
        guard let k = c.kommentare.max(by: { $0.createdAt < $1.createdAt }),
              let g = Muster.erster(k.body, #"ruht bis (\d{1,2})\.(\d{1,2})\.(\d{4})"#),
              let tag = g[1].flatMap(Int.init), let monat = g[2].flatMap(Int.init), let jahr = g[3].flatMap(Int.init),
              let d = cal.date(from: DateComponents(year: jahr, month: monat, day: tag)) else { return nil }
        return d.timeIntervalSince1970 * 1000
    }

    static func agentName(_ id: String?, _ d: OvDaten) -> String {
        guard let id, !id.isEmpty else { return "" }
        if id == d.defaultAgent { return "Seneca" }
        let n = d.label(id)
        if d.mitarbeiterName(id) != nil { return n }
        guard n == id, let erster = n.first else { return n }
        return String(erster).uppercased() + n.dropFirst().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    static func aufgabe(_ c: OvKarte, _ d: OvDaten, klartext: Tageslauf? = nil, jetzt: Double = Date().timeIntervalSince1970 * 1000) -> Aufgabe {
        var a = ausKarte(c, d)
        a.belege = c.belege
        a.geprueft = c.labels.contains("geprueft")
        a.inPruefung = c.labels.contains("in-pruefung")
        a.inRunden = c.labels.contains("dauerauftrag")
        if let fuer = klartext?.fuerDich, let lauf = klartext?.laeuft {
            if a.stand != .fertig {
                if fuer.contains(where: { $0.id == c.id }) {
                    if a.stand != .wartetAufDich { a.stand = .wartetAufDich; a.beleg = vorliegend(c) }
                } else if lauf.contains(where: { $0.id == c.id }) {
                    if a.stand != .laeuft { a.stand = .laeuft; a.beleg = nil }
                } else if a.stand == .wartetAufDich || a.stand == .laeuft {
                    a.stand = a.frist == nil && ["backlog", "triage"].contains(c.status) ? .vorrat : .alsNaechstes; a.beleg = nil
                }
            }
        } else if a.stand == .wartetAufDich, let bis = ruhtBis(c), bis > jetzt {
            a.stand = .vorrat; a.beleg = nil
        }
        if a.stand != .fertig, a.stand != .vorrat, let satz = klartext?.klarTitel(c.id) {
            a.wortlaut = c.title; a.titel = satz; a.satzArt = klartext?.klarArt(c.id) ?? ""
        }
        return a
    }

    private static func ausKarte(_ c: OvKarte, _ d: OvDaten) -> Aufgabe {
        var a = Aufgabe(id: c.id, titel: titel(c.title), stand: .alsNaechstes)
        a.wer = c.agentId ?? ""
        a.werName = agentName(c.agentId, d)
        a.frist = Menschlich.fristVon(c.labels)
        a.istEntscheidung = HeuteLogik.istEntscheidung(c)
        let dich = c.labels.contains("wartet-auf-antonio")
        switch c.status {
        case "done":
            a.stand = .fertig; a.seit = c.completedAt ?? PM.statusSeit(c, "done") ?? c.updatedAt; a.beleg = beleg(c)
        case "running":
            a.stand = .laeuft; a.seit = PM.statusSeit(c, "running") ?? c.createdAt
        case "review":
            a.stand = .wartetAufDich; a.seit = PM.statusSeit(c, "review") ?? c.updatedAt; a.beleg = vorliegend(c)
        case "blocked":
            a.stand = dich ? .wartetAufDich : .haengt; a.seit = PM.statusSeit(c, "blocked") ?? c.updatedAt
            if dich { a.beleg = vorliegend(c) }
        case "backlog", "triage":
            a.stand = dich ? .wartetAufDich : (a.frist == nil ? .vorrat : .alsNaechstes); a.seit = c.createdAt
        default:
            a.stand = dich || a.istEntscheidung ? .wartetAufDich : .alsNaechstes; a.seit = c.createdAt
            if dich { a.beleg = vorliegend(c) }
        }
        return a
    }

    private static func ordne(_ a: [Aufgabe]) -> [Aufgabe] {
        a.enumerated().sorted { x, y in
            let l = x.element, r = y.element
            if l.stand != r.stand { return l.stand.rawValue < r.stand.rawValue }
            switch l.stand {
            case .fertig: return (l.seit ?? 0) > (r.seit ?? 0)
            case .alsNaechstes: return (l.frist ?? .infinity, x.offset) < (r.frist ?? .infinity, y.offset)
            default: return (l.seit ?? .infinity, x.offset) < (r.seit ?? .infinity, y.offset)
            }
        }.map(\.element)
    }

    static func bauen(_ d: OvDaten, klartext: Tageslauf? = nil, jetzt: Double = Date().timeIntervalSince1970 * 1000) -> Arbeitsplan {
        let karten = d.cards.filter { !$0.archiviert && !$0.labels.contains("auftrag") && !istPruefkarte($0) }
        func aufgabe(_ c: OvKarte, _ d: OvDaten) -> Aufgabe { Self.aufgabe(c, d, klartext: klartext, jetzt: jetzt) }
        let archivierteBoards = Set(d.boards.filter(\.archiviert).map(\.id))
        let bekannteBereiche = d.bereiche?.areas ?? []
        var jeBereich: [String: [Projekt]] = [:]
        var projektIds = Set<String>()
        for (id, f) in d.pm.projekte {
            let name = f.name.isEmpty ? (d.boards.first { $0.id == id }?.name ?? id) : f.name
            if f.status == "archiviert" || archivierteBoards.contains(id) || istTest(name, id: id) { continue }
            projektIds.insert(id)
            var p = Projekt(id: id, name: name)
            p.ziel = f.ziel.trimmingCharacters(in: .whitespacesAndNewlines)
            p.frist = f.faellig
            p.meilensteine = f.meilensteine
            p.aufgaben = ordne(karten.filter { $0.boardId == id }.map { aufgabe($0, d) })
            jeBereich[bekannteBereiche.contains { $0.id == f.bereichId } ? f.bereichId : "", default: []].append(p)
        }
        for b in bekannteBereiche {
            let boards = Set(karten.map(\.boardId)).filter { !projektIds.contains($0) && ($0 == b.id || $0.hasPrefix(b.id + "-")) }
            let lose = ordne(karten.filter { boards.contains($0.boardId) }.map { aufgabe($0, d) }).filter { $0.stand != .fertig && $0.stand != .vorrat }
            if lose.isEmpty { continue }
            jeBereich[b.id, default: []].append(Projekt(id: "ohne:" + b.id, name: "Ohne Projekt", aufgaben: lose, ohneProjekt: true))
        }
        func rang(_ p: Projekt) -> (Int, Double, Int, String) {
            (p.ohneProjekt ? 1 : 0, p.frist ?? .infinity, p.mit(.wartetAufDich).isEmpty ? (p.offen > 0 ? 1 : 2) : 0, p.name.lowercased())
        }
        var plan = Arbeitsplan()
        var reihe = bekannteBereiche.map { ($0.id, $0.name) }
        if jeBereich[""] != nil { reihe.append(("", "Ohne Bereich")) }
        for (id, name) in reihe {
            guard let p = jeBereich[id], !p.isEmpty else { continue }
            plan.bereiche.append(Bereich(id: id, name: name, projekte: p.sorted { rang($0) < rang($1) }))
        }
        plan.bereiche = plan.bereiche.enumerated().sorted { x, y in
            let fx = x.element.projekte.compactMap(\.frist).min() ?? .infinity, fy = y.element.projekte.compactMap(\.frist).min() ?? .infinity
            return (fx, x.offset) < (fy, y.offset)
        }.map(\.element)
        return plan
    }
}

enum ArbeitsplanText {
    private static let monate = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    private static let tage = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]

    static func zahl(_ n: Int, _ eins: String = "eine") -> String {
        n == 1 ? eins : (n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n].lowercased() : String(n))
    }
    private static func gross(_ s: String) -> String { s.first.map { $0.uppercased() + s.dropFirst() } ?? s }

    static func datum(_ ms: Double, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.weekday, .day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        return "\(tage[(c.weekday ?? 1) - 1]), \(c.day ?? 1). \(monate[(c.month ?? 1) - 1])"
    }

    static func wann(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        let t = Menschlich.tageZwischen(jetzt, ms, cal)
        if t == 0 { return "heute" }
        if t == 1 { return "morgen" }
        if t == -1 { return "gestern" }
        let c = cal.dateComponents([.weekday, .day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        if t > 1 && t < 7 { return "am " + tage[(c.weekday ?? 1) - 1] }
        return "am \(c.day ?? 1). \(monate[(c.month ?? 1) - 1])"
    }

    static func rest(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        let t = Menschlich.tageZwischen(jetzt, ms, cal)
        if t == 0 { return "heute fällig" }
        if t == 1 { return "morgen fällig" }
        if t > 1 { return "noch \(zahl(t, "einen")) Tage" }
        return t == -1 ? "seit gestern überfällig" : "seit \(zahl(-t, "einem")) Tagen überfällig"
    }

    static func dringlichkeit(_ ms: Double?, jetzt: Double, _ cal: Calendar = .current) -> Int {
        guard let ms else { return 0 }
        let t = Menschlich.tageZwischen(jetzt, ms, cal)
        return t < 0 ? 2 : (t <= 2 ? 1 : 0)
    }

    static func fristSatz(_ plan: Arbeitsplan, jetzt: Double, _ cal: Calendar = .current) -> String {
        let mitFrist = plan.projekte.filter { $0.frist != nil }.sorted { $0.frist! < $1.frist! }
        let ueber = mitFrist.filter { Menschlich.tageZwischen(jetzt, $0.frist!, cal) < 0 }
        let bald = mitFrist.filter { (0...7).contains(Menschlich.tageZwischen(jetzt, $0.frist!, cal)) }
        var saetze: [String] = []
        if let u = ueber.first {
            saetze.append(ueber.count == 1 ? "\(u.name) ist \(rest(u.frist!, jetzt: jetzt, cal))." : "\(gross(zahl(ueber.count, "ein"))) Projekte sind überfällig.")
        }
        switch bald.count {
        case 0: if ueber.isEmpty { saetze.append(plan.projekte.isEmpty ? "" : "In den nächsten sieben Tagen ist kein Projekt fällig.") }
        case 1: saetze.append("\(bald[0].name) ist \(wann(bald[0].frist!, jetzt: jetzt, cal)) fällig.")
        case 2: saetze.append("\(bald[0].name) ist \(wann(bald[0].frist!, jetzt: jetzt, cal)) fällig, \(bald[1].name) \(wann(bald[1].frist!, jetzt: jetzt, cal)).")
        default: saetze.append("\(gross(zahl(bald.count, "ein"))) Projekte sind in den nächsten sieben Tagen fällig, als erstes \(bald[0].name) \(wann(bald[0].frist!, jetzt: jetzt, cal)).")
        }
        return saetze.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func wartetSatz(_ plan: Arbeitsplan) -> String {
        let n = plan.wartetAufDich
        if n == 0 { return plan.projekte.isEmpty ? "" : "Nichts wartet auf dich." }
        return n == 1 ? "Eine Aufgabe wartet auf dich." : "\(gross(zahl(n))) Aufgaben warten auf dich."
    }

    static let ohneKarten = "Für dieses Projekt steht noch keine Aufgabe auf dem Board."

    static func angabe(_ a: Arbeitsplan.Aufgabe, jetzt: Double, _ cal: Calendar = .current) -> String {
        func seit(_ ms: Double) -> String {
            let t = Menschlich.tageZwischen(ms, jetzt, cal)
            if t == 0 { return "seit \(Menschlich.hhmm(ms, cal)) Uhr" }
            if t == 1 { return "seit gestern" }
            return t < 7 ? "seit \(tage[cal.component(.weekday, from: Date(timeIntervalSince1970: ms / 1000)) - 1])" : "seit \(zahl(t, "einem")) Tagen"
        }
        switch a.stand {
        case .wartetAufDich:
            let wartet = a.seit.map { "wartet \(seit($0)) auf dich" } ?? "wartet auf dich"
            return [a.geprueft ? "vom Prüfer geprüft" : nil, wartet, a.frist.map { "Frist " + wann($0, jetzt: jetzt, cal) }].compactMap { $0 }.joined(separator: " · ")
        case .laeuft:
            if a.inPruefung { return "der Prüfer sieht es gerade an" }
            let wer = a.werName.isEmpty ? "in Arbeit" : (a.inRunden ? "\(a.werName) arbeitet in Runden daran" : "\(a.werName) arbeitet daran")
            return [wer, a.seit.map(seit)].compactMap { $0 }.joined(separator: " ")
        case .haengt:
            return ["hängt fest", a.seit.map(seit)].compactMap { $0 }.joined(separator: " ")
        case .alsNaechstes, .vorrat:
            let f = a.frist.map { "fällig " + wann($0, jetzt: jetzt, cal) }
            return [f, a.werName.isEmpty ? (f == nil ? "niemand eingetragen" : nil) : a.werName].compactMap { $0 }.joined(separator: " · ")
        case .fertig:
            return a.seit.map { "fertig " + wann($0, jetzt: jetzt, cal) } ?? "fertig"
        }
    }

    static func vorrat(_ n: Int) -> String { n == 1 ? "Eine Idee ohne Termin" : "\(gross(zahl(n))) Ideen ohne Termin" }
    static func weitereFertig(_ n: Int) -> String { n == 1 ? "Eine weitere fertige Aufgabe" : "\(gross(zahl(n))) weitere fertige Aufgaben" }
    static func fertigGesamt(_ n: Int) -> String { n == 1 ? "Eine fertige Aufgabe" : "\(gross(zahl(n))) fertige Aufgaben" }
}
