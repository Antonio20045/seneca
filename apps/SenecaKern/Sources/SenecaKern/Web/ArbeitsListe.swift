import Foundation

struct ListenStation: Equatable {
    var name: String
    var zeit: Date?
    var beleg = ""
    var dateien: [String] = []
    var fehlt = false
    var offen = false
    var zustand = ""
    var zustandArt = ""
    var zustandText = ""
}

struct ListenTeil: Equatable, Identifiable {
    var id: String
    var titel: String
    var zustand = ""
    var weg: [ListenStation] = []
}

struct ListenZeile: Equatable, Identifiable {
    var id: String
    var titel: String
    var satz: String
    var board = ""
    var projekt: String?
    var projektName = ListenText.ohneProjekt
    var bereich: String?
    var bereichName = ""
    var agent = ""
    var von = ""
    var frist: Date?
    var projektFrist: Date?
    var zustand = ""
    var art = ""
    var seit: Date?
    var weg: [ListenStation] = []
    var steht = ""
    var runden = 0
    var kette = false
    var paket = ""
    var spalte = ""
    var haelt = false
    var haltSeit: Date?
    var haltGrund = ""
    var urteil = ""
    var beleg = ""
    var worum = ""
    var zweifel: [String] = []
    var entscheidung = false
    var ruhend = false
    var frageSeit: Date?
    var gegenstandUeberholt = ""
    var fertigUm: Date?
    var gelesenKennung = ""
    var auftrag = false
    var teile: [ListenTeil] = []
    var nachricht: Date?
    var nachrichtAn = ""
    var zustandSatz = ""

    func station(_ name: String) -> ListenStation? { weg.first { $0.name == name } }
}

struct ListenMeilenstein: Equatable {
    var name: String
    var datum: Date?
    var erreicht: Bool
}

struct ListenProjekt: Equatable, Identifiable {
    var id: String
    var name: String
    var bereich: String?
    var bereichName = ""
    var frist: Date?
    var ziel = ""
    var meilensteine: [ListenMeilenstein] = []
    var agent = ""
    var von = ""
    var zahlen: [String: Int] = [:]
}

struct ListenBereich: Equatable, Identifiable {
    var id: String
    var name: String
}

struct ListenStand: Equatable {
    var startstrich: Date?
    var fragenGeprueft: Date?
    var fragenAlterMin: Int?
    var fragenVeraltet = false
    var eingang = 0
    var ohneMitarbeiter = 0
    var hinweise: [String] = []
    var schlange = 0, laeuft = 0, blockiert = 0, fragen = 0, fragenUeberholt = 0, abnahmen = 0, fertig = 0
    var board: [String: Int] = [:]
}

struct OffeneZusage: Equatable, Identifiable {
    var id: String
    var agent = ""
    var von = ""
    var zeit: Date?
    var wortlaut = ""
    var was = ""
    var alterMin = 0
    var grund = ""
    var klasse = "antonio"
}

struct ArbeitsListe: Equatable {
    var zusagenOffen: [OffeneZusage] = []
    var schlange: [ListenZeile] = []
    var laeuft: [ListenZeile] = []
    var blockiert: [ListenZeile] = []
    var fragen: [ListenZeile] = []
    var fragenUeberholt: [ListenZeile] = []
    var abnahmen: [ListenZeile] = []
    var fertig: [ListenZeile] = []
    var eingang: [ListenZeile] = []
    var projekte: [ListenProjekt] = []
    var bereiche: [ListenBereich] = []
    var stand = ListenStand()

    var alle: [ListenZeile] { laeuft + blockiert + schlange + fragen + abnahmen + fertig + eingang }

    var laufendeKarten: [ListenZeile] { laeuft.filter { !$0.id.hasPrefix("warten:") } }

    func laufendeKarten(fuer agent: String) -> [ListenZeile] {
        let eigene = laufendeKarten.filter { $0.agent == agent || $0.nachrichtAn == agent }
        func beginn(_ z: ListenZeile) -> Date { z.station("begonnen")?.zeit ?? z.seit ?? .distantPast }
        let auftraege = eigene.filter { $0.nachricht != nil }.sorted { ($0.nachricht ?? .distantPast, $0.id) > ($1.nachricht ?? .distantPast, $1.id) }
        let rest = eigene.filter { $0.nachricht == nil }.sorted { (beginn($0), $0.id) > (beginn($1), $1.id) }
        return auftraege + rest
    }


    var agentJeKarte: [String: String] {
        var m: [String: String] = [:]
        for z in alle where !z.agent.isEmpty && !z.id.hasPrefix("warten:") && z.agent != "paket.sh" { m[z.id] = z.agent }
        return m
    }

    static func lies(_ daten: Data, jetzt: Date = Date(), kalender: Calendar = .current) -> ArbeitsListe? {
        guard let wurzel = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] else { return nil }
        return lies(wurzel: wurzel, jetzt: jetzt, kalender: kalender)
    }

    static func lies(wurzel: [String: Any], jetzt: Date = Date(), kalender: Calendar = .current) -> ArbeitsListe? {
        guard let ls = wurzel["liste_stand"] as? [String: Any] else { return nil }
        func text(_ w: Any?) -> String { (w as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func zeit(_ w: Any?) -> Date? { TageslaufZeit.lies(w, heute: jetzt, kalender: kalender) }
        func zahl(_ w: Any?) -> Int { (w as? NSNumber)?.intValue ?? 0 }
        func ja(_ w: Any?) -> Bool { (w as? Bool) ?? false }
        func texte(_ w: Any?) -> [String] { ((w as? [Any]) ?? []).map(text).filter { !$0.isEmpty } }
        func station(_ s: [String: Any]) -> ListenStation {
            var st = ListenStation(name: text(s["station"]), zeit: zeit(s["zeit"]), fehlt: ja(s["fehlt"]), offen: ja(s["offen"]))
            st.zustand = text(s["zustand"]); st.zustandArt = text(s["zustand_art"]); st.zustandText = text(s["zustand_text"])
            if let b = s["beleg"] as? [String: Any] { st.beleg = text(b["pruefung"]); st.dateien = texte(b["dateien"]) } else { st.beleg = text(s["beleg"]) }
            return st
        }
        func zeilen(_ name: String) -> [ListenZeile] {
            ((wurzel[name] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { z in
                let id = text(z["id"]), titel = text(z["titel"])
                guard !id.isEmpty, !titel.isEmpty else { return nil }
                var n = ListenZeile(id: id, titel: titel, satz: text(z["satz"]).isEmpty ? titel : text(z["satz"]))
                n.board = text(z["board"])
                n.projekt = text(z["projekt"]).isEmpty ? nil : text(z["projekt"])
                n.projektName = n.projekt == nil ? ListenText.ohneProjekt : (text(z["projekt_name"]).isEmpty ? n.projekt! : text(z["projekt_name"]))
                n.bereich = text(z["bereich"]).isEmpty ? nil : text(z["bereich"])
                n.bereichName = text(z["bereich_name"])
                n.agent = text(z["agent"]); n.von = text(z["von"])
                n.frist = zeit(z["frist"]); n.projektFrist = zeit(z["projekt_frist"])
                n.zustand = text(z["zustand"]); n.art = text(z["art"]); n.seit = zeit(z["seit"])
                n.weg = ((z["weg"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map(station)
                n.steht = text(z["steht"]); n.runden = zahl(z["runden"])
                n.kette = ja(z["kette"]); n.paket = text(z["paket"])
                n.spalte = text(z["spalte"]); n.haelt = ja(z["haelt"])
                if let h = z["halt"] as? [String: Any] { n.haltSeit = zeit(h["seit"]); n.haltGrund = text(h["grund"]) }
                if n.haltGrund.isEmpty { n.haltGrund = text(z["grund"]) }
                n.urteil = text(z["urteil"]); n.beleg = text(z["beleg"]); n.worum = text(z["worum"]); n.zweifel = texte(z["zweifel"])
                n.entscheidung = ja(z["entscheidung"]); n.ruhend = ja(z["ruhend"]); n.frageSeit = zeit(z["frage_seit"])
                n.gegenstandUeberholt = text(z["gegenstand_ueberholt"])
                n.fertigUm = zeit(z["fertig_um"]); n.gelesenKennung = text(z["gelesen_kennung"])
                n.auftrag = ja(z["auftrag"])
                n.nachricht = zeit(z["nachricht"]); n.nachrichtAn = text(z["nachricht_an"]); n.zustandSatz = text(z["zustand_satz"])
                n.teile = ((z["teile"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { t in
                    let tid = text(t["id"]), titel = text(t["titel"])
                    guard !tid.isEmpty, !titel.isEmpty else { return nil }
                    return ListenTeil(id: tid, titel: titel, zustand: text(t["zustand"]),
                                      weg: ((t["weg"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map(station))
                }
                return n
            }
        }
        var l = ArbeitsListe()
        l.schlange = zeilen("schlange"); l.laeuft = zeilen("laeuft_alle"); l.blockiert = zeilen("blockiert")
        l.fragen = zeilen("fragen"); l.fragenUeberholt = zeilen("fragen_ueberholt"); l.abnahmen = zeilen("abnahmen")
        l.fertig = zeilen("fertig"); l.eingang = zeilen("eingang_alle")
        l.projekte = ((wurzel["projekte"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { p in
            let id = text(p["id"])
            guard !id.isEmpty else { return nil }
            var n = ListenProjekt(id: id, name: text(p["name"]).isEmpty ? id : text(p["name"]))
            n.bereich = text(p["bereich"]).isEmpty ? nil : text(p["bereich"]); n.bereichName = text(p["bereich_name"])
            n.frist = zeit(p["frist"]); n.ziel = text(p["ziel"]); n.agent = text(p["agent"]); n.von = text(p["von"])
            n.meilensteine = ((p["meilensteine"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
                .map { ListenMeilenstein(name: text($0["name"]), datum: zeit($0["datum"]), erreicht: ja($0["erreicht"])) }.filter { !$0.name.isEmpty }
            n.zahlen = ((p["zahlen"] as? [String: Any]) ?? [:]).mapValues(zahl)
            return n
        }
        l.bereiche = ((wurzel["bereiche"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { b in
            text(b["id"]).isEmpty ? nil : ListenBereich(id: text(b["id"]), name: text(b["name"]).isEmpty ? text(b["id"]) : text(b["name"]))
        }
        l.zusagenOffen = ((wurzel["zusagen_offen"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { z in
            let id = text(z["id"]), wortlaut = text(z["wortlaut"])
            guard !id.isEmpty, !wortlaut.isEmpty else { return nil }
            return OffeneZusage(id: id, agent: text(z["agent"]), von: text(z["von"]), zeit: zeit(z["zeit"]), wortlaut: wortlaut, was: text(z["was"]),
                                alterMin: zahl(z["alter_min"]), grund: text(z["grund"]), klasse: text(z["klasse"]).isEmpty ? "antonio" : text(z["klasse"]))
        }
        var s = ListenStand()
        s.startstrich = zeit(ls["startstrich"]); s.fragenGeprueft = zeit(ls["fragen_geprueft"])
        s.fragenAlterMin = (ls["fragen_alter_min"] as? NSNumber)?.intValue
        s.fragenVeraltet = ja(ls["fragen_veraltet"]); s.eingang = zahl(ls["eingang"]); s.ohneMitarbeiter = zahl(ls["ohne_mitarbeiter"])
        s.hinweise = texte(ls["hinweise"])
        let z = (ls["zahlen"] as? [String: Any]) ?? [:]
        s.schlange = zahl(z["schlange"]); s.laeuft = zahl(z["laeuft"]); s.blockiert = zahl(z["blockiert"])
        s.fragen = ((z["fragen"] as? [String: Any]) ?? [:]).values.reduce(0) { $0 + zahl($1) }
        s.fragenUeberholt = zahl(z["fragen_ueberholt"]); s.abnahmen = zahl(z["abnahmen"]); s.fertig = zahl(z["fertig"])
        s.board = ((ls["board"] as? [String: Any]) ?? [:]).mapValues(zahl)
        l.stand = s
        return l
    }
}

enum ListenText {
    static let ohneProjekt = "ohne Projekt"
    static let stationen = ["angelegt", "angenommen", "begonnen", "zur_pruefung", "fertig"]

    static func station(_ name: String) -> String {
        switch name {
        case "angelegt": "Angelegt"
        case "angenommen": "Angenommen"
        case "begonnen": "Begonnen"
        case "zur_pruefung": "Zur Prüfung"
        case "fertig": "Fertig"
        case "gesendet": "Gesendet"
        default: name
        }
    }

    static func wer(_ z: ListenZeile) -> String {
        let name = z.von.isEmpty ? z.agent : z.von
        guard z.kette else { return name }
        let starter = name.isEmpty || name == "paket.sh" ? "" : ", gestartet von " + name
        return "Bau-Kette" + starter
    }

    static func marke(_ z: ListenZeile) -> String { z.paket.isEmpty ? (z.kette ? "Bau-Kette" : "") : "Paket " + z.paket }

    static func lage(_ z: ListenZeile) -> String {
        switch z.art {
        case "arbeit": "in Arbeit"
        case "auftrag": "Dauerauftrag"
        case "helfer": "Helfer arbeitet"
        case "bitte": "Bitte an Kollegen"
        case "warten": "wartet auf ein Ereignis"
        case "pruefung": "beim Prüfer"
        case "bereit": "bereit"
        case "blockiert": "hängt"
        case "frage": z.entscheidung ? "Entscheidung" : "Frage an dich"
        case "abnahme": "wartet auf deine Abnahme"
        case "fertig": "fertig"
        case "eingang": "im Eingang"
        default: z.zustand
        }
    }

    static func uhr(_ d: Date, jetzt: Date, kalender: Calendar = .current) -> String {
        let tage = kalender.dateComponents([.day], from: kalender.startOfDay(for: d), to: kalender.startOfDay(for: jetzt)).day ?? 0
        let c = kalender.dateComponents([.day, .month, .hour, .minute], from: d)
        let zeit = String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        switch tage {
        case 0: return zeit
        case 1: return "gestern " + zeit
        default: return "\(c.day ?? 0).\(c.month ?? 0). " + zeit
        }
    }

    static func dauer(_ sek: TimeInterval) -> String {
        if sek < 60 { return sek < 1 ? "unter 1 Sek." : "\(Int(sek)) Sek." }
        let m = Int((sek / 60).rounded())
        if m < 60 { return "\(m) Min." }
        if m < 24 * 60 { return m % 60 == 0 ? "\(m / 60) Std." : "\(m / 60) Std. \(m % 60) Min." }
        let t = Int((sek / 86_400).rounded())
        return t == 1 ? "1 Tag" : "\(t) Tage"
    }

    private static let sperre = NSLock()
    nonisolated(unsafe) private static var formate: [String: DateFormatter] = [:]
    private static func format(_ muster: String, kalender: Calendar) -> DateFormatter {
        let k = muster + "|" + kalender.timeZone.identifier + "|\(kalender.identifier)"
        sperre.lock(); defer { sperre.unlock() }
        if let f = formate[k] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE"); f.calendar = kalender; f.timeZone = kalender.timeZone; f.dateFormat = muster
        formate[k] = f
        return f
    }

    static func tag(_ d: Date, kalender: Calendar = .current) -> String { format("EE, d. MMM", kalender: kalender).string(from: d) }

    static func tagKurz(_ d: Date, kalender: Calendar = .current) -> String { format("d.M.", kalender: kalender).string(from: d) }

    static func tageBis(_ d: Date, jetzt: Date, kalender: Calendar = .current) -> Int {
        kalender.dateComponents([.day], from: kalender.startOfDay(for: jetzt), to: kalender.startOfDay(for: d)).day ?? 0
    }

    static func rest(_ d: Date, jetzt: Date, kalender: Calendar = .current) -> String {
        switch tageBis(d, jetzt: jetzt, kalender: kalender) {
        case 0: "heute"
        case 1: "morgen"
        case -1: "seit gestern überfällig"
        case let n where n < 0: "seit \(-n) Tagen überfällig"
        case let n: "in \(n) Tagen"
        }
    }

    static func dringlich(_ d: Date?, jetzt: Date, kalender: Calendar = .current) -> Int {
        guard let d else { return 0 }
        let n = tageBis(d, jetzt: jetzt, kalender: kalender)
        return n <= 0 ? 2 : (n <= 2 ? 1 : 0)
    }

    static func anzahl(_ n: Int, _ eins: String, _ viele: String) -> String { n == 1 ? "1 " + eins : "\(n) " + viele }
}

struct WegSicht: Equatable {
    struct Station: Equatable, Identifiable {
        var id: String
        var name: String
        var zeit: String
        var erreicht: Bool
        var fehlt: Bool
        var hier: Bool
        var dauer: String
        var beleg: String
    }

    var stationen: [Station] = []

    init(_ z: ListenZeile, jetzt: Date, kalender: Calendar = .current) {
        var vorher: Date?
        func uhr(_ d: Date) -> String { ListenText.uhr(d, jetzt: jetzt, kalender: kalender) }
        stationen += z.weg.map { s in
            let erreicht = s.zeit != nil || s.fehlt
            var dauer = ""
            if let t = s.zeit, let v = vorher, t.timeIntervalSince(v) >= 1 { dauer = ListenText.dauer(t.timeIntervalSince(v)) }
            if let t = s.zeit { vorher = t }
            return Station(id: s.name, name: ListenText.station(s.name), zeit: (s.zeit.map(uhr) ?? (s.fehlt ? "nicht gemessen" : "")) + (s.zustand.isEmpty ? "" : "\n" + s.zustand),
                           erreicht: erreicht, fehlt: s.fehlt, hier: s.name == z.steht, dauer: dauer, beleg: s.beleg)
        }
    }
}

struct BoardSicht: Equatable {
    struct Zeile: Equatable, Identifiable {
        var id: String
        var titel: String
        var wortlaut: String
        var wer: String
        var lage: String
        var marke: String
        var seit: String
        var frist: String
        var dringlich: Int
        var weg: WegSicht
        var grund: String
        var haelt: Bool
        var runden: Int
        var gelesenKennung: String
        var teile: [Teil] = []
        var zustandSatz = ""
    }

    struct Teil: Equatable, Identifiable {
        enum Art: String { case wartet, laeuft, pruefung, fertig, haelt }
        var id: String
        var titel: String
        var lage: String
        var art: Art = .wartet
        var wort = ""
        var weg: WegSicht?
    }

    static func teile(_ liste: [ListenTeil], jetzt: Date, kalender: Calendar = .current) -> [Teil] {
        func uhr(_ d: Date?) -> String { d.map { ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? "" }
        func zeit(_ t: ListenTeil, _ name: String) -> Date? { t.weg.first { $0.name == name }?.zeit }
        func pruefer(_ t: ListenTeil) -> ListenStation? { t.weg.first { $0.name == "zur_pruefung" && !$0.zustand.isEmpty } }
        return liste.map { t in
            var w: WegSicht?
            if !t.weg.isEmpty {
                var h = ListenZeile(id: t.id, titel: t.titel, satz: t.titel)
                h.weg = t.weg; h.steht = t.weg.last { $0.zeit != nil || $0.fehlt }?.name ?? ""
                w = WegSicht(h, jetzt: jetzt, kalender: kalender)
            }
            var n = Teil(id: t.id, titel: t.titel, lage: "", weg: w)
            if let f = zeit(t, "fertig") {
                n.art = .fertig; n.lage = "fertig"; n.wort = "fertig " + uhr(f)
            } else if let p = pruefer(t), p.zustandArt == "zurueck", t.zustand == "läuft" || t.zustand == "bereit" {
                n.art = .haelt; n.lage = "vom Prüfer zurück"; n.wort = "vom Prüfer zurück" + (p.zeit.map { " " + uhr($0) } ?? "")
            } else {
                switch t.zustand {
                case "läuft":
                    if let p = zeit(t, "zur_pruefung") { n.art = .pruefung; n.lage = "zur Prüfung"; n.wort = "zur Prüfung " + uhr(p) }
                    else { n.art = .laeuft; n.lage = "läuft"; n.wort = zeit(t, "begonnen").map { "läuft seit " + uhr($0) } ?? "läuft" }
                case "bereit": n.art = .wartet; n.lage = "wartet auf Start"; n.wort = zeit(t, "angelegt").map { "wartet seit " + uhr($0) } ?? "wartet"
                case "wartet auf Antonio": n.art = .haelt; n.lage = "wartet auf dich"; n.wort = "wartet auf dich"
                case "blockiert": n.art = .haelt; n.lage = "gesperrt"; n.wort = "gesperrt"
                case "eingang": n.art = .wartet; n.lage = "im Eingang"; n.wort = "im Eingang"
                default: n.art = .wartet; n.lage = t.zustand; n.wort = t.zustand
                }
            }
            return n
        }
    }

    static func zaehlzeile(_ t: [Teil]) -> String {
        func n(_ a: Teil.Art) -> Int { t.filter { $0.art == a }.count }
        var z = [ListenText.anzahl(t.count, "Teil", "Teile")]
        if n(.laeuft) > 0 { z.append("\(n(.laeuft)) " + (n(.laeuft) == 1 ? "läuft" : "laufen")) }
        if n(.pruefung) > 0 { z.append("\(n(.pruefung)) zur Prüfung") }
        if n(.wartet) > 0 { z.append("\(n(.wartet)) " + (n(.wartet) == 1 ? "wartet" : "warten")) }
        if n(.haelt) > 0 { z.append("\(n(.haelt)) " + (n(.haelt) == 1 ? "hält an" : "halten an")) }
        if n(.fertig) > 0 { z.append("\(n(.fertig)) fertig") }
        return z.joined(separator: " · ")
    }

    struct Auftrag: Equatable, Identifiable {
        var id: String
        var titel: String
        var wer: String
        var seit: String
    }

    struct Gruppe: Equatable, Identifiable {
        var id: String
        var name: String
        var bereich: String
        var ohneProjekt: Bool
        var auftraege: [Auftrag] = []
        var zeilen: [Zeile] = []
        var haltend: [Zeile] = []
    }

    var angelegt: [Gruppe] = []
    var eingang: [Gruppe] = []
    var laeuft: [Gruppe] = []
    var fertig: [Gruppe] = []
    var fertigSeit = ""
    var fragen = 0
    var abnahmen = 0
    var hinweise: [String] = []

    var angelegtZeilen: [Zeile] { angelegt.flatMap(\.zeilen) }
    var eingangZeilen: [Zeile] { eingang.flatMap(\.zeilen) }
    var laeuftZeilen: [Zeile] { laeuft.flatMap(\.zeilen) }
    var haltZeilen: [Zeile] { laeuft.flatMap(\.haltend) }
    var auftraege: [Auftrag] { laeuft.flatMap(\.auftraege) }
    var fertigZeilen: [Zeile] { fertig.flatMap(\.zeilen) }

    init(_ l: ArbeitsListe, jetzt: Date = Date(), kalender: Calendar = .current, gelesen: Set<String> = []) {
        func uhr(_ d: Date?) -> String { d.map { ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? "" }
        func mit(_ wort: String, _ d: Date?) -> String { d == nil ? "" : wort + " " + uhr(d) }
        func spalte(_ z: ListenZeile) -> String { z.spalte.isEmpty ? (z.zustand == "läuft" ? "laeuft" : "angelegt") : z.spalte }
        func haelt(_ z: ListenZeile) -> Bool { z.haelt && spalte(z) == "laeuft" }
        func seit(_ z: ListenZeile) -> String {
            switch z.zustand {
            case "läuft": return mit("seit", z.station("begonnen")?.zeit ?? z.seit)
            case "blockiert": return mit(haelt(z) ? "hält seit" : "gesperrt seit", z.haltSeit ?? z.seit)
            case "bereit": return haelt(z) ? mit("hält seit", z.haltSeit ?? z.seit) : mit("wartet seit", z.station("angenommen")?.zeit ?? z.station("angelegt")?.zeit)
            case "fertig": return mit("fertig", z.fertigUm)
            default: return mit("angelegt", z.station("angelegt")?.zeit)
            }
        }
        func zeile(_ z: ListenZeile) -> Zeile {
            return Zeile(id: z.id, titel: z.titel, wortlaut: "", wer: ListenText.wer(z),
                         lage: haelt(z) ? "hält an" : (z.zustand == "blockiert" ? "gesperrt" : ListenText.lage(z)), marke: ListenText.marke(z), seit: seit(z),
                         frist: z.frist.map { "bis " + ListenText.tag($0, kalender: kalender) + ", " + ListenText.rest($0, jetzt: jetzt, kalender: kalender) } ?? "",
                         dringlich: z.zustand == "fertig" ? 0 : ListenText.dringlich(z.frist, jetzt: jetzt, kalender: kalender),
                         weg: WegSicht(z, jetzt: jetzt, kalender: kalender), grund: z.haltGrund, haelt: haelt(z), runden: z.runden,
                         gelesenKennung: z.gelesenKennung, teile: Self.teile(z.teile, jetzt: jetzt, kalender: kalender), zustandSatz: z.zustandSatz)
        }
        func gruppen(_ quelle: [ListenZeile]) -> [Gruppe] {
            var aus: [Gruppe] = []
            for z in quelle {
                let id = z.projekt ?? "ohne|" + (z.bereich ?? "")
                let i = aus.firstIndex { $0.id == id } ?? {
                    aus.append(Gruppe(id: id, name: z.projekt == nil ? "Ohne Projekt" : z.projektName, bereich: z.bereichName, ohneProjekt: z.projekt == nil))
                    return aus.count - 1
                }()
                if z.art == "auftrag" {
                    aus[i].auftraege.append(Auftrag(id: z.id, titel: z.titel, wer: ListenText.wer(z), seit: mit("läuft seit", z.station("begonnen")?.zeit ?? z.seit)))
                } else if haelt(z) {
                    aus[i].haltend.append(zeile(z))
                } else {
                    aus[i].zeilen.append(zeile(z))
                }
            }
            return aus.filter { !$0.ohneProjekt } + aus.filter(\.ohneProjekt)
        }
        let offen = l.laeuft + l.schlange + l.blockiert
        angelegt = gruppen(offen.filter { spalte($0) == "angelegt" })
        eingang = gruppen(l.eingang)
        laeuft = gruppen(offen.filter { spalte($0) == "laeuft" })
        fertig = gruppen(l.fertig.filter { !gelesen.contains($0.gelesenKennung) })
        fertigSeit = l.stand.startstrich.map { "seit " + ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? ""
        fragen = l.fragen.count
        abnahmen = l.abnahmen.count
        hinweise = l.stand.hinweise.filter { $0.contains("Startstrich") }
    }

    var laeuftKopf: String { haltZeilen.isEmpty ? "\(laeuftZeilen.count)" : "\(laeuftZeilen.count) · hält \(haltZeilen.count)" }

    var satz: (String, String) {
        let ab13 = ["dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn", "zwanzig"]
        func wort(_ n: Int) -> String { n > 1 && n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n].lowercased() : (n >= 13 && n <= 20 ? ab13[n - 13] : String(n)) }
        var teile: [String] = []
        let l = laeuftZeilen.count, h = haltZeilen.count, a = angelegtZeilen.count, f = fertigZeilen.count
        if l > 0 { teile.append(l == 1 ? "eine Arbeit läuft" : wort(l) + " Arbeiten laufen") }
        if h > 0 { teile.append(h == 1 ? "eine hält an" : wort(h) + " halten an") }
        if a > 0 { teile.append(a == 1 ? "eine wartet auf Start" : wort(a) + " warten auf Start") }
        if f > 0 { teile.append(f == 1 ? "eine ist neu fertig" : wort(f) + " sind neu fertig") }
        guard let letzter = teile.last else { return ("Gerade ist ", "nichts in Arbeit.") }
        if l == 0 { teile.insert("gerade läuft nichts", at: 0) }
        let vorn = teile.dropLast().joined(separator: ", ")
        let kopf = vorn.isEmpty ? "" : vorn.prefix(1).uppercased() + vorn.dropFirst() + (teile.count > 2 ? ", " : " und ")
        return kopf.isEmpty ? ("", letzter.prefix(1).uppercased() + letzter.dropFirst() + ".") : (kopf, letzter + ".")
    }

    var fragenSatz: String {
        var teile: [String] = []
        if fragen > 0 { teile.append(ListenText.anzahl(fragen, "Frage", "Fragen")) }
        if abnahmen > 0 { teile.append(ListenText.anzahl(abnahmen, "Abnahme", "Abnahmen")) }
        guard !teile.isEmpty else { return "" }
        return teile.joined(separator: " und ") + (fragen + abnahmen == 1 ? " wartet" : " warten") + " auf dich"
    }
}

struct ProjektTabSicht: Equatable {
    static let ohneBereich = "-"

    struct Reiter: Equatable, Identifiable {
        var id: String
        var name: String
        var offen: Int
    }

    struct Aufgabe: Equatable, Identifiable {
        var id: String
        var titel: String
        var wortlaut: String
        var wer: String
        var zustand: String
        var lage: String
        var marke: String
        var frist: Date?
        var fristText: String
        var dringlich: Int
        var ort: Double?
        var weg: WegSicht
        var halt: String
    }

    struct Meilenstein: Equatable, Identifiable {
        var id: String
        var name: String
        var datum: String
        var erreicht: Bool
        var ort: Double?
    }

    struct Projekt: Equatable, Identifiable {
        var id: String
        var name: String
        var ohneProjekt = false
        var frist: Date?
        var fristTag = ""
        var fristRest = ""
        var dringlich = 0
        var ort: Double?
        var ziel = ""
        var wer = ""
        var stand = ""
        var meilensteine: [Meilenstein] = []
        var aufgaben: [Aufgabe] = []
        var eingang: [Aufgabe] = []
    }

    struct Marke: Equatable, Identifiable {
        var id: String
        var text: String
        var ort: Double
    }

    var reiter: [Reiter] = []
    var gewaehlt = ""
    var bereichName = ""
    var projekte: [Projekt] = []
    var ohneProjekt = Projekt(id: "ohne", name: "Ohne Projekt", ohneProjekt: true)
    var marken: [Marke] = []
    var heute: Double = 0
    var achseVon = Date()
    var achseBis = Date()
    var fristSatz = ""

    var aufgaben: [Aufgabe] { projekte.flatMap(\.aufgaben) + ohneProjekt.aufgaben }
    var eingang: [Aufgabe] { projekte.flatMap(\.eingang) + ohneProjekt.eingang }

    static func reiter(_ l: ArbeitsListe) -> [Reiter] {
        let offene = l.laeuft + l.blockiert + l.schlange + l.fragen + l.abnahmen + l.fertig
        var r = l.bereiche.map { b in Reiter(id: b.id, name: b.name, offen: offene.filter { $0.bereich == b.id }.count) }
        var bekannt = Set(r.map(\.id))
        for z in l.alle { if let b = z.bereich, bekannt.insert(b).inserted { r.append(Reiter(id: b, name: z.bereichName.isEmpty ? b : z.bereichName, offen: offene.filter { $0.bereich == b }.count)) } }
        for p in l.projekte { if let b = p.bereich, bekannt.insert(b).inserted { r.append(Reiter(id: b, name: p.bereichName.isEmpty ? b : p.bereichName, offen: 0)) } }
        if l.alle.contains(where: { $0.bereich == nil }) || l.projekte.contains(where: { $0.bereich == nil }) {
            r.append(Reiter(id: ohneBereich, name: "Übergreifend", offen: offene.filter { $0.bereich == nil }.count))
        }
        return r
    }

    init(_ l: ArbeitsListe, bereich wunsch: String? = nil, jetzt: Date = Date(), kalender: Calendar = .current) {
        reiter = Self.reiter(l)
        gewaehlt = reiter.first { $0.id == wunsch }?.id ?? reiter.first { $0.offen > 0 }?.id ?? reiter.first?.id ?? ""
        bereichName = reiter.first { $0.id == gewaehlt }?.name ?? ""
        let b: String? = gewaehlt == Self.ohneBereich ? nil : gewaehlt
        let zeilen = (l.laeuft + l.blockiert + l.schlange + l.fragen + l.abnahmen + l.fertig).filter { $0.bereich == b }
        let imEingang = l.eingang.filter { $0.bereich == b }
        let listenProjekte = l.projekte.filter { $0.bereich == b }

        let heuteTag = kalender.startOfDay(for: jetzt)
        let fristen = listenProjekte.compactMap(\.frist) + listenProjekte.flatMap { $0.meilensteine.compactMap(\.datum) } + (zeilen + imEingang).compactMap(\.frist)
        let von = kalender.date(byAdding: .day, value: -2, to: heuteTag) ?? heuteTag
        let spaeteste = max(fristen.max() ?? heuteTag, kalender.date(byAdding: .day, value: 19, to: heuteTag) ?? heuteTag)
        let bis = kalender.date(byAdding: .day, value: 3, to: kalender.startOfDay(for: spaeteste)) ?? spaeteste
        achseVon = von; achseBis = bis
        let spanne = max(1, bis.timeIntervalSince(von))
        func ort(_ d: Date?) -> Double? {
            guard let d else { return nil }
            let mitte = kalender.startOfDay(for: d).addingTimeInterval(12 * 3600)
            return min(1, max(0, mitte.timeIntervalSince(von) / spanne))
        }
        heute = min(1, max(0, jetzt.timeIntervalSince(von) / spanne))
        var m: [Marke] = []
        var tag = von
        while tag <= bis {
            if kalender.component(.weekday, from: tag) == 2 { m.append(Marke(id: ListenText.tagKurz(tag, kalender: kalender), text: ListenText.tagKurz(tag, kalender: kalender), ort: tag.timeIntervalSince(von) / spanne)) }
            tag = kalender.date(byAdding: .day, value: 1, to: tag) ?? bis.addingTimeInterval(1)
        }
        marken = m

        func aufgabe(_ z: ListenZeile) -> Aufgabe {
            let titel = z.zustand != "wartet auf Antonio" || z.satz.isEmpty ? z.titel : z.satz
            return Aufgabe(id: z.id, titel: titel, wortlaut: titel == z.titel ? "" : z.titel, wer: ListenText.wer(z), zustand: z.zustand, lage: z.haelt && z.spalte == "laeuft" ? "hält an" : (z.zustand == "blockiert" ? "gesperrt" : ListenText.lage(z)),
                           marke: ListenText.marke(z), frist: z.frist,
                           fristText: z.frist.map { "bis " + ListenText.tag($0, kalender: kalender) + ", " + ListenText.rest($0, jetzt: jetzt, kalender: kalender) } ?? "",
                           dringlich: z.zustand == "fertig" ? 0 : ListenText.dringlich(z.frist, jetzt: jetzt, kalender: kalender), ort: ort(z.frist),
                           weg: WegSicht(z, jetzt: jetzt, kalender: kalender), halt: z.haltGrund)
        }
        func geordnet(_ a: [Aufgabe]) -> [Aufgabe] {
            a.enumerated().sorted { x, y in
                switch (x.element.frist, y.element.frist) {
                case let (p?, q?) where p != q: return p < q
                case (_?, nil): return true
                case (nil, _?): return false
                default: return x.offset < y.offset
                }
            }.map(\.element)
        }
        func stand(_ a: [ListenZeile], eingang: Int) -> String {
            func n(_ zustand: String) -> Int { a.filter { $0.zustand == zustand }.count }
            var t: [String] = []
            if n("läuft") > 0 { t.append(n("läuft") == 1 ? "1 läuft" : "\(n("läuft")) laufen") }
            let haelt = a.filter { $0.haelt && $0.spalte == "laeuft" }.count, gesperrt = a.filter { $0.zustand == "blockiert" && !($0.haelt && $0.spalte == "laeuft") }.count
            if haelt > 0 { t.append(haelt == 1 ? "1 hält an" : "\(haelt) halten an") }
            if gesperrt > 0 { t.append(gesperrt == 1 ? "1 gesperrt" : "\(gesperrt) gesperrt") }
            if n("wartet auf Antonio") > 0 { t.append(n("wartet auf Antonio") == 1 ? "1 wartet auf dich" : "\(n("wartet auf Antonio")) warten auf dich") }
            let bereit = a.filter { $0.zustand == "bereit" && !($0.haelt && $0.spalte == "laeuft") }.count
            if bereit > 0 { t.append("\(bereit) in der Schlange") }
            if n("fertig") > 0 { t.append("\(n("fertig")) neu fertig") }
            if eingang > 0 { t.append("\(eingang) im Eingang") }
            return t.isEmpty ? "Keine offene Aufgabe" : t.joined(separator: " · ")
        }
        func projekt(id: String, name: String, p: ListenProjekt?) -> Projekt {
            let meine = zeilen.filter { $0.projekt == id }, ein = imEingang.filter { $0.projekt == id }
            var n = Projekt(id: id, name: name)
            n.frist = p?.frist ?? meine.compactMap(\.projektFrist).first
            if let f = n.frist {
                n.fristTag = ListenText.tag(f, kalender: kalender); n.fristRest = ListenText.rest(f, jetzt: jetzt, kalender: kalender)
                n.dringlich = ListenText.dringlich(f, jetzt: jetzt, kalender: kalender); n.ort = ort(f)
            }
            n.ziel = p?.ziel ?? ""; n.wer = p?.von ?? ""
            n.stand = stand(meine, eingang: ein.count)
            n.meilensteine = (p?.meilensteine ?? []).enumerated().map { i, ms in
                Meilenstein(id: "\(i)|" + ms.name, name: ms.name, datum: ms.datum.map { ListenText.tag($0, kalender: kalender) } ?? "", erreicht: ms.erreicht, ort: ort(ms.datum))
            }
            n.aufgaben = geordnet(meine.map(aufgabe)); n.eingang = ein.map(aufgabe)
            return n
        }
        var liste = listenProjekte.map { projekt(id: $0.id, name: $0.name, p: $0) }
        var bekannt = Set(liste.map(\.id))
        for z in zeilen + imEingang { if let id = z.projekt, bekannt.insert(id).inserted { liste.append(projekt(id: id, name: z.projektName, p: nil)) } }
        projekte = liste.enumerated().sorted { x, y in
            switch (x.element.frist, y.element.frist) {
            case let (p?, q?) where p != q: return p < q
            case (_?, nil): return true
            case (nil, _?): return false
            default: return x.offset < y.offset
            }
        }.map(\.element)
        let frei = zeilen.filter { $0.projekt == nil }, freiEin = imEingang.filter { $0.projekt == nil }
        ohneProjekt.stand = stand(frei, eingang: freiEin.count)
        ohneProjekt.aufgaben = geordnet(frei.map(aufgabe)); ohneProjekt.eingang = freiEin.map(aufgabe)

        let mitFrist = projekte.filter { $0.frist != nil }
        func bisWann(_ p: Projekt) -> String {
            if p.fristRest.hasPrefix("seit") { return p.fristRest }
            let tag = p.fristTag.hasSuffix(".") ? String(p.fristTag.dropLast()) : p.fristTag
            return "bis " + (p.fristRest.hasPrefix("in ") ? tag : p.fristRest)
        }
        fristSatz = mitFrist.isEmpty ? (projekte.isEmpty ? "Hier gibt es kein Projekt." : "Kein Projekt hat eine Frist.")
            : mitFrist.prefix(3).map { $0.name + " " + bisWann($0) }.joined(separator: ", ") + "."
    }
}
