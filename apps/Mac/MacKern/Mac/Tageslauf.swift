import Foundation

struct TageslaufEreignis: Equatable {
    var zeit: Date?
    var ende: Date?
    var art: String
    var titel: String
    var detail: String
    var mit = ""
    var faellig: Date? = nil
    var ganztags = false
    var routine = false
    var karte = ""
    var belege: [String] = []
    var ergebnis = ""
    var geprueft = false
    var urteil = ""
    var wartetAufAbnahme = false
    var probe = false
    var runde = 0
}

struct TageslaufWartet: Equatable {
    var wer: String
    var seit: Date?
    var seitRoh: String
    var chat: String
    var worum: String
    var quelle = ""
}

struct Tageslauf: Equatable {
    var jetztText = ""
    var jetztSeit: Date? = nil
    var unterwegs = false
    var ereignisse: [TageslaufEreignis] = []
    var kommt: [TageslaufEreignis] = []
    var fuerDich: [FuerDichZeile]? = nil
    var laeuft: [LaeuftZeile]? = nil
    var klartext: [String: String] = [:]
    var klartextArt: [String: String] = [:]
    var liste: ArbeitsListe? = nil

    var istLeer: Bool { ereignisse.isEmpty && kommt.isEmpty && fuerDich == nil && laeuft == nil }

    private func schluessel(_ kartenId: String) -> String? {
        let id = kartenId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        if klartext[id] != nil { return id }
        guard id.count >= 8 else { return nil }
        return klartext.keys.first { $0.hasPrefix(id) || id.hasPrefix($0) && $0.count >= 8 }
    }

    func klar(_ kartenId: String) -> String? { schluessel(kartenId).flatMap { klartext[$0] }.flatMap { $0.isEmpty ? nil : $0 } }
    func klarArt(_ kartenId: String) -> String? { schluessel(kartenId).flatMap { klartextArt[$0] } }

    func klarTitel(_ kartenId: String) -> String? {
        guard var s = klar(kartenId) else { return nil }
        for schluss in [" ist fertig und wartet auf deine Prüfung.", " sind fertig und warten auf deine Prüfung.", " ist fertig und wartet auf deine Abnahme.", " sind fertig und warten auf deine Abnahme."] where s.hasSuffix(schluss) {
            s = String(s.dropLast(schluss.count))
        }
        return s.isEmpty ? nil : s
    }

    static func lies(_ daten: Data, jetzt: Date = Date(), kalender: Calendar = .current) -> Tageslauf? {
        guard let wurzel = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] else { return nil }
        func text(_ w: Any?) -> String {
            if let s = w as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = w as? NSNumber { return n.stringValue }
            return ""
        }
        func zeit(_ w: Any?) -> Date? { TageslaufZeit.lies(w, heute: jetzt, kalender: kalender) }
        func ereignisse(_ w: Any?) -> [TageslaufEreignis] {
            ((w as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { e in
                let t = text(e["titel"]), art = text(e["art"]).lowercased()
                guard !t.isEmpty, !art.isEmpty else { return nil }
                let d = e["detail"] as? [String: Any]
                var neu = TageslaufEreignis(zeit: zeit(e["zeit"]), ende: zeit(e["ende"]), art: art, titel: t, detail: d == nil ? text(e["detail"]) : text(d?["ort"]))
                if let d {
                    neu.mit = text(art == "agent_fertig" ? d["agent"] : d["chat"])
                    neu.ganztags = (d["ganztags"] as? Bool) ?? false
                    neu.routine = (d["routine"] as? Bool) ?? false
                    neu.karte = text(d["karte"])
                    neu.belege = ((d["beleg"] as? [Any]) ?? []).map { text($0) }.filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    neu.ergebnis = text(d["ergebnis"])
                    neu.geprueft = (d["geprueft"] as? Bool) ?? false
                    neu.urteil = text(d["urteil_des_pruefers"])
                    neu.wartetAufAbnahme = (d["wartet_auf_antonio"] as? Bool) ?? false
                    neu.probe = (d["probe"] as? Bool) ?? false
                    if (d["dauerauftrag"] as? Bool) ?? false { neu.runde = max(1, (d["runde"] as? NSNumber)?.intValue ?? 1) }
                }
                neu.faellig = zeit(e["faellig"]) ?? zeit(d?["faellig"])
                return neu
            }
        }
        var t = Tageslauf()
        t.ereignisse = ereignisse(wurzel["ereignisse"])
        t.kommt = ereignisse(wurzel["kommt"])
        t.fuerDich = FuerDich.zeilen(wurzel["fuer_dich"], zeit: zeit)
        t.laeuft = FuerDich.laeuft(wurzel["laeuft"], zeit: zeit)
        t.liste = ArbeitsListe.lies(wurzel: wurzel, jetzt: jetzt, kalender: kalender)
        for (k, v) in (wurzel["klartext"] as? [String: Any]) ?? [:] { let satz = text(v); if !satz.isEmpty { t.klartext[k] = satz } }
        for (k, v) in (wurzel["klartext_art"] as? [String: Any]) ?? [:] { t.klartextArt[k] = text(v) }
        if let j = wurzel["jetzt"] as? [String: Any] {
            if let ort = j["ort"] as? [String: Any] {
                t.unterwegs = (ort["unterwegs"] as? Bool) ?? false
                t.jetztText = t.unterwegs ? "Unterwegs" : text(ort["ort"])
                t.jetztSeit = zeit(ort["seit"])
            } else {
                t.jetztText = ["satz", "text", "titel", "was", "ort"].lazy.map { text(j[$0]) }.first { !$0.isEmpty } ?? ""
            }
        } else {
            t.jetztText = text(wurzel["jetzt"])
        }
        return t
    }
}

enum TageslaufZeit {
    static func lies(_ wert: Any?, heute: Date, kalender: Calendar) -> Date? {
        if let n = wert as? NSNumber, !(wert is String) {
            let z = n.doubleValue
            return z <= 0 ? nil : Date(timeIntervalSince1970: z > 100_000_000_000 ? z / 1000 : z)
        }
        guard let roh = wert as? String else { return nil }
        let s = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let d = IsoZeit.datum(s) { return d }
        if let g = Muster.erster(s, #"^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?"#) {
            var c = DateComponents(year: g[1].flatMap(Int.init), month: g[2].flatMap(Int.init), day: g[3].flatMap(Int.init))
            c.hour = g[4].flatMap(Int.init) ?? 0; c.minute = g[5].flatMap(Int.init) ?? 0; c.second = g[6].flatMap(Int.init) ?? 0
            return kalender.date(from: c)
        }
        if let g = Muster.erster(s, #"^(\d{1,2}):(\d{2})$"#), let h = g[1].flatMap(Int.init), let m = g[2].flatMap(Int.init) {
            return kalender.date(bySettingHour: h, minute: m, second: 0, of: heute)
        }
        return nil
    }

    static func hhmm(_ d: Date, kalender: Calendar) -> String {
        let c = kalender.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func uhr(_ d: Date, kalender: Calendar) -> String {
        let c = kalender.dateComponents([.hour, .minute], from: d)
        return (c.minute ?? 0) == 0 ? "\(c.hour ?? 0) Uhr" : String(format: "%d:%02d Uhr", c.hour ?? 0, c.minute ?? 0)
    }

    private static func zahl(_ n: Int) -> String {
        n > 1 && n < HeuteLogik.zahlwort.count ? HeuteLogik.zahlwort[n].lowercased() : String(n)
    }

    static func seit(_ d: Date, jetzt: Date, kalender: Calendar) -> String {
        let sek = jetzt.timeIntervalSince(d)
        guard sek >= 0 else { return "" }
        if sek < 5 * 60 { return "seit eben" }
        if sek < 55 * 60 { return "seit \(Int((sek / 60).rounded())) Minuten" }
        if sek < 5.5 * 3600 { let h = max(1, Int((sek / 3600).rounded())); return h == 1 ? "seit einer Stunde" : "seit \(zahl(h)) Stunden" }
        let tage = kalender.dateComponents([.day], from: kalender.startOfDay(for: d), to: kalender.startOfDay(for: jetzt)).day ?? 0
        let stunde = kalender.component(.hour, from: d)
        let teil: String
        switch stunde {
        case ..<5: teil = tage == 0 ? "Nacht" : "früh"
        case ..<10: teil = "Morgen"
        case ..<12: teil = "Vormittag"
        case ..<14: teil = "Mittag"
        case ..<18: teil = "Nachmittag"
        default: teil = "Abend"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE"); f.calendar = kalender; f.timeZone = kalender.timeZone
        switch tage {
        case ...0: return "seit heute \(teil)"
        case 1: return "seit gestern \(teil)"
        case 2: return "seit vorgestern"
        case ..<7: f.dateFormat = "EEEE"; return "seit \(f.string(from: d))"
        default: f.dateFormat = "d. MMMM"; return "seit dem \(f.string(from: d))"
        }
    }

    static func dauer(_ sek: TimeInterval) -> String {
        let m = Int((sek / 60).rounded())
        guard m > 0 else { return "" }
        if m % 60 == 0 { let h = m / 60; return h == 1 ? "eine Stunde" : "\(zahl(h)) Stunden" }
        if m < 120 { return "\(m) Minuten" }
        return m % 60 == 30 ? "\(m / 60),5 Stunden" : "\(zahl(m / 60)) Stunden und \(m % 60) Minuten"
    }
}

struct TageslaufSicht: Equatable {
    struct Wartet: Equatable, Identifiable {
        var id: String
        var name: String
        var rest: String
        var mensch = true
        var wortlaut = ""
    }

    struct Ergebnis: Equatable, Identifiable {
        var id: String
        var zeit: String
        var titel: String
        var wer: String
        var ergebnis: String
        var belege: [String]
        var geprueft: Bool
        var urteil: String
        var wartetAufAbnahme: Bool
        var wortlaut: String
        var runde = 0
    }

    struct Zusage: Equatable, Identifiable {
        var id: String
        var titel: String
        var wann: String
        var heute: Bool
        var detail: String
    }

    enum Lage: Equatable { case war, jetzt, kommt }

    struct Zeile: Equatable, Identifiable {
        var id: String
        var zeit: String
        var titel: String
        var nebenzeile: String
        var lage: Lage
        var marke = false
    }

    static let hoechstensZusagen = 5
    static let hoechstensVorher = 5
    static let hoechstensNachher = 6
    static let zeitleistenArten: Set<String> = ["termin", "ort_ankunft", "ort_abfahrt", "training", "meeting"]

    var wartet: [Wartet] = []
    var ergebnisse: [Ergebnis] = []
    var zugesagt: [Zusage] = []
    var zeitleiste: [Zeile] = []

    var istLeer: Bool { wartet.isEmpty && zugesagt.isEmpty && zeitleiste.isEmpty }

    init() {}

    static func schoenerName(_ kennung: String) -> String {
        kennung.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    init(_ t: Tageslauf, jetzt: Date = Date(), kalender: Calendar = .current, name: (String) -> String = TageslaufSicht.schoenerName) {
        wartet = FuerDich.wartende(t.fuerDich ?? [], jetzt: jetzt, kalender: kalender)

        var kartenGesehen = Set<String>()
        ergebnisse = t.ereignisse.filter { $0.art == "agent_fertig" && !$0.karte.isEmpty && !$0.probe && $0.zeit != nil && !($0.belege.isEmpty && $0.ergebnis.isEmpty) }
            .sorted { $0.zeit! > $1.zeit! }
            .filter { kartenGesehen.insert($0.karte).inserted }
            .map { e in
                let satz = e.wartetAufAbnahme ? t.klarTitel(e.karte) : nil
                return Ergebnis(id: e.karte, zeit: TageslaufZeit.hhmm(e.zeit!, kalender: kalender), titel: satz ?? Arbeitsplan.titel(e.titel, max: 200),
                                wer: e.mit.isEmpty ? "" : name(e.mit), ergebnis: e.ergebnis, belege: e.belege, geprueft: e.geprueft, urteil: e.urteil,
                                wartetAufAbnahme: e.wartetAufAbnahme, wortlaut: e.titel, runde: e.runde)
            }

        let heute = kalender.startOfDay(for: jetzt)
        func tagAbstand(_ d: Date) -> Int { kalender.dateComponents([.day], from: heute, to: kalender.startOfDay(for: d)).day ?? 99 }
        var doppelt = Set<String>()
        let alle = (t.ereignisse + t.kommt).filter { doppelt.insert("\($0.art)|\($0.titel)|\($0.zeit?.timeIntervalSince1970 ?? 0)").inserted }
        zugesagt = alle.compactMap { e -> (Date, Zusage)? in
            guard e.art == "zusage" || e.art == "verabredung" else { return nil }
            guard let faellig = e.art == "zusage" ? (e.faellig ?? e.ende) : e.zeit else { return nil }
            let abstand = tagAbstand(faellig)
            guard abstand == 0 || abstand == 1 else { return nil }
            let c = kalender.dateComponents([.hour, .minute], from: faellig)
            let ohneUhr = e.ganztags || ((c.hour ?? 0) == 0 && (c.minute ?? 0) == 0)
            if e.art == "verabredung", !ohneUhr, (e.ende ?? faellig) < jetzt { return nil }
            let wann = (abstand == 0 ? "Heute" : "Morgen") + (ohneUhr ? "" : " um " + TageslaufZeit.uhr(faellig, kalender: kalender))
            let mit = e.mit.isEmpty ? e.detail : (e.art == "zusage" ? "an " : "mit ") + e.mit
            return (faellig, Zusage(id: "\(e.art)|\(e.titel)|\(faellig.timeIntervalSince1970)", titel: Self.titelOhneZusatz(e), wann: wann, heute: abstand == 0, detail: mit))
        }
        .sorted { $0.0 < $1.0 }.prefix(Self.hoechstensZusagen).map(\.1)

        func lage(_ e: TageslaufEreignis) -> Lage { e.zeit! > jetzt ? .kommt : ((e.ende ?? e.zeit!) > jetzt ? .jetzt : .war) }
        let tag = alle.filter { e in Self.zeitleistenArten.contains(e.art) && !e.ganztags && e.zeit.map { tagAbstand($0) == 0 } == true }
            .filter { !($0.routine && lage($0) == .war) }
            .sorted { $0.zeit! < $1.zeit! }
        func zeile(_ e: TageslaufEreignis) -> Zeile {
            let l = lage(e)
            return Zeile(id: "\(e.art)|\(e.titel)|\(e.zeit!.timeIntervalSince1970)", zeit: TageslaufZeit.hhmm(e.zeit!, kalender: kalender),
                         titel: e.titel, nebenzeile: Self.nebenzeile(e, lage: l, jetzt: jetzt, name: name), lage: l)
        }
        let war = tag.filter { lage($0) == .war }.suffix(Self.hoechstensVorher).map(zeile)
        let laeuft = tag.filter { lage($0) == .jetzt }.map(zeile)
        let kommt = tag.filter { lage($0) == .kommt }.prefix(Self.hoechstensNachher).map(zeile)
        if !tag.isEmpty {
            var seit = ""
            if !t.jetztText.isEmpty, let s = t.jetztSeit, tagAbstand(s) == 0, s <= jetzt {
                let uhr = TageslaufZeit.uhr(s, kalender: kalender)
                seit = t.unterwegs ? "Du bist um \(uhr) aufgebrochen." : "Du bist seit \(uhr) hier."
            }
            let marke = Zeile(id: "jetzt", zeit: TageslaufZeit.hhmm(jetzt, kalender: kalender), titel: t.jetztText, nebenzeile: seit, lage: .jetzt, marke: true)
            zeitleiste = war + (laeuft.isEmpty ? [marke] : laeuft) + kommt
        }
    }

    mutating func ergaenze(termine: [(zeit: String, titel: String, nebenzeile: String)], jetzt: Date = Date(), kalender: Calendar = .current) {
        guard !zeitleiste.isEmpty else { return }
        let nun = TageslaufZeit.hhmm(jetzt, kalender: kalender)
        func gleich(_ a: String, _ b: String) -> Bool {
            let x = a.lowercased(), y = b.lowercased()
            return x == y || x.contains(y) || y.contains(x)
        }
        var neu = zeitleiste.filter { !$0.marke }
        for t in termine where Muster.passt(t.zeit, #"^\d{2}:\d{2}$"#) {
            guard !neu.contains(where: { $0.zeit == t.zeit && gleich($0.titel, t.titel) }) else { continue }
            neu.append(Zeile(id: "kalender|\(t.zeit)|\(t.titel)", zeit: t.zeit, titel: t.titel, nebenzeile: t.nebenzeile, lage: t.zeit <= nun ? .jetzt : .kommt))
        }
        func teil(_ l: Lage) -> [Zeile] { neu.filter { $0.lage == l }.sorted { $0.zeit < $1.zeit } }
        let marke = zeitleiste.first { $0.marke } ?? Zeile(id: "jetzt", zeit: nun, titel: "", nebenzeile: "", lage: .jetzt, marke: true)
        let laeuft = teil(.jetzt)
        zeitleiste = teil(.war) + (laeuft.isEmpty ? [marke] : laeuft) + teil(.kommt).prefix(Self.hoechstensNachher)
    }

    private static let kleinAmAnfang: Set<String> = ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer",
                                                     "dein", "deine", "deinen", "deinem", "deiner", "sein", "seine", "seinen", "ihr", "ihre", "ihren",
                                                     "euer", "eure", "unser", "unsere", "ob", "wann", "wie", "wo", "was", "welche", "welcher", "welches"]

    static func wartetRest(_ w: TageslaufWartet, jetzt: Date, kalender: Calendar) -> String {
        var s = " wartet"
        if let d = w.seit {
            let t = TageslaufZeit.seit(d, jetzt: jetzt, kalender: kalender)
            if !t.isEmpty { s += " " + t }
        } else if !w.seitRoh.isEmpty {
            s += " " + (w.seitRoh.lowercased().hasPrefix("seit") ? w.seitRoh : "seit " + w.seitRoh)
        }
        if !w.chat.isEmpty, w.chat.caseInsensitiveCompare(w.wer) != .orderedSame { s += " in „\(w.chat)“" }
        s += " auf deine Antwort"
        var worum = w.worum.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !worum.isEmpty else { return s + "." }
        if worum.contains("?") || worum.contains("!") || worum.hasSuffix(".") || worum.hasSuffix("…") || worum.split(separator: " ").count > 6 {
            return s + ": „" + gekuerzt(worum, auf: 90) + "“"
        }
        for anfang in ["es geht um ", "um "] where worum.lowercased().hasPrefix(anfang) { worum = String(worum.dropFirst(anfang.count)) }
        if let erstes = worum.split(separator: " ").first, kleinAmAnfang.contains(erstes.lowercased()) {
            worum = worum.prefix(1).lowercased() + worum.dropFirst()
        }
        return s + ", es geht um " + worum + "."
    }

    static func fragtRest(_ w: TageslaufWartet, klar: String?, jetzt: Date, kalender: Calendar) -> String {
        var s = " fragt"
        if let d = w.seit {
            let t = TageslaufZeit.seit(d, jetzt: jetzt, kalender: kalender)
            if !t.isEmpty { s += " " + t }
        }
        if let klar, !klar.isEmpty { return s + ": " + klar }
        let worum = w.worum.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return worum.isEmpty ? s.replacingOccurrences(of: " fragt", with: " wartet") + " auf deine Antwort." : s + ": „" + gekuerzt(worum, auf: 160) + "“"
    }

    static func gekuerzt(_ s: String, auf laenge: Int) -> String {
        guard s.count > laenge else { return s }
        let anfang = s.prefix(laenge)
        let bisWort = anfang.lastIndex(of: " ").map { anfang[..<$0] } ?? anfang
        return bisWort.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:–-")) + " …"
    }

    static func titelOhneZusatz(_ e: TageslaufEreignis) -> String {
        var t = e.titel
        if !e.mit.isEmpty { for zusatz in [" (an \(e.mit))", " (\(e.mit))"] where t.hasSuffix(zusatz) { t = String(t.dropLast(zusatz.count)) } }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    static func nebenzeile(_ e: TageslaufEreignis, lage: Lage, jetzt: Date, name: (String) -> String = TageslaufSicht.schoenerName) -> String {
        var teile: [String] = []
        if lage == .kommt, let z = e.zeit {
            let m = Int((z.timeIntervalSince(jetzt) / 60).rounded(.up))
            if m > 0, m <= 90 { teile.append(m == 1 ? "in einer Minute" : "in \(m) Minuten") }
        }
        let wort: String
        switch e.art {
        case "ort_ankunft": wort = lage == .kommt ? "Ankunft" : "Angekommen"
        case "ort_abfahrt": wort = lage == .kommt ? "Aufbruch" : "Aufgebrochen"
        case "training": wort = "Training"
        case "meeting": wort = "Besprechung"
        case "agent_fertig": wort = ["fertig", "abgeschlossen", "erledigt"].contains { e.titel.lowercased().contains($0) } ? "" : "Fertig geworden"
        default: wort = ""
        }
        if !wort.isEmpty, !e.titel.lowercased().contains(wort.lowercased()) { teile.append(wort) }
        if let z = e.zeit, let ende = e.ende, ende > z {
            let d = TageslaufZeit.dauer(ende.timeIntervalSince(z))
            if !d.isEmpty { teile.append(d) }
        }
        if e.art == "agent_fertig", !e.mit.isEmpty { teile.append(name(e.mit)) }
        let detail = e.detail.replacingOccurrences(of: "\n", with: " ")
        if !detail.isEmpty { teile.append(detail) }
        return teile.joined(separator: " · ")
    }
}
