import Foundation

struct AblaufPunkt: Equatable, Codable, Identifiable {
    var zeit: Date
    var ende: Date? = nil
    var art: String = "termin"
    var titel: String
    var ort: String? = nil
    var ganztags = false
    var routine = false

    var id: String { "\(art)|\(Int(zeit.timeIntervalSince1970 / 60))|\(titel.lowercased())" }
    var istTermin: Bool { art == "termin" || art == "meeting" || art == "verabredung" }
    func laeuft(_ jetzt: Date) -> Bool { !ganztags && istTermin && zeit <= jetzt && (ende.map { jetzt < $0 } ?? false) }
}

struct AblaufWartet: Equatable, Codable, Identifiable {
    var wer: String
    var seit: Date? = nil
    var chat: String = ""
    var worum: String = ""
    var quelle: String = ""
    var id: String { wer + "|" + chat }
}

struct AblaufOrt: Equatable, Codable {
    var name: String
    var seit: Date? = nil
    var unterwegs = false
}

struct TageslaufBild: Equatable, Codable {
    var stand: Date? = nil
    var punkte: [AblaufPunkt] = []
    var ort: AblaufOrt? = nil
    var fertig = 0
    var fuerDich: [FuerDichZeile]? = nil
    var laeuft: [LaeuftZeile]? = nil

    static func lesen(_ json: [String: Any]) -> TageslaufBild? {
        if json["ok"] as? Bool == false { return nil }
        guard json["kommt"] != nil || json["wartet_auf_antwort"] != nil || json["ereignisse"] != nil else { return nil }
        var b = TageslaufBild(stand: TageslaufZeit.lesen(json["stand"]))
        let jetzt = json["jetzt"] as? [String: Any] ?? [:]
        var roh = json["ereignisse"] as? [[String: Any]] ?? []
        roh += jetzt["termin"] as? [[String: Any]] ?? []
        if let n = jetzt["als_naechstes"] as? [String: Any] { roh.append(n) }
        roh += json["kommt"] as? [[String: Any]] ?? []
        var gesehen = Set<String>()
        for e in roh {
            let art = e["art"] as? String ?? ""
            let detail = e["detail"] as? [String: Any] ?? [:]
            if art == "agent_fertig" { b.fertig += max(1, detail["anzahl"] as? Int ?? 1); continue }
            guard Tagesablauf.zeigbar.contains(art), let zeit = TageslaufZeit.lesen(e["zeit"]),
                  let titel = (e["titel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !titel.isEmpty else { continue }
            let ort = (detail["ort"] as? String).flatMap { $0.isEmpty || art.hasPrefix("ort_") ? nil : $0 }
            let p = AblaufPunkt(zeit: zeit, ende: TageslaufZeit.lesen(e["ende"]), art: art, titel: titel, ort: ort,
                                ganztags: detail["ganztags"] as? Bool ?? false, routine: detail["routine"] as? Bool ?? false)
            if gesehen.insert(Tagesablauf.schluessel(p)).inserted { b.punkte.append(p) }
        }
        b.punkte.sort { $0.zeit < $1.zeit }
        b.fuerDich = FuerDich.zeilen(json["fuer_dich"], wartende: json["wartet_auf_antwort"] as? [[String: Any]] ?? [])
        b.laeuft = FuerDich.laeuft(json["laeuft"])
        if let o = jetzt["ort"] as? [String: Any], let name = o["ort"] as? String, !name.isEmpty {
            b.ort = AblaufOrt(name: name, seit: TageslaufZeit.lesen(o["seit"]), unterwegs: o["unterwegs"] as? Bool ?? false)
        }
        return b
    }
}

enum AblaufZeile: Equatable, Identifiable {
    case war(AblaufPunkt)
    case jetzt
    case laeuft(AblaufPunkt)
    case aufgabe(String)
    case weitereAufgaben(Int)
    case kommt(AblaufPunkt)
    case morgen
    case morgenPunkt(AblaufPunkt)

    var id: String {
        switch self {
        case .war(let p): return "war:" + p.id
        case .jetzt: return "jetzt"
        case .laeuft(let p): return "laeuft:" + p.id
        case .aufgabe(let a): return "aufgabe:" + a
        case .weitereAufgaben: return "weitere"
        case .kommt(let p): return "kommt:" + p.id
        case .morgen: return "morgen"
        case .morgenPunkt(let p): return "morgen:" + p.id
        }
    }
}

enum Tagesablauf {
    static let zeigbar: Set<String> = ["termin", "training", "ort_ankunft", "ort_abfahrt", "meeting", "verabredung"]
    static let hoechstensAufgaben = 3

    static func schluessel(_ p: AblaufPunkt) -> String {
        let art = p.istTermin ? "termin" : p.art
        return "\(art)|\(Int(p.zeit.timeIntervalSince1970 / 60))|\(p.titel.lowercased().trimmingCharacters(in: .whitespaces))"
    }

    static func punkt(_ t: KalenderTermin) -> AblaufPunkt {
        AblaufPunkt(zeit: t.start, ende: t.end, titel: t.title, ort: t.place, ganztags: t.isAllDay, routine: KalenderLogic.isRoutine(t))
    }
    static func punkt(_ t: GeraetTermin) -> AblaufPunkt {
        AblaufPunkt(zeit: t.start, ende: t.ende, titel: t.titel, ort: t.ort.flatMap { $0.isEmpty ? nil : $0 }, ganztags: t.ganztags)
    }

    static func punkte(mac: TageslaufBild?, kalender: [KalenderTermin], geraet: [GeraetTermin], jetzt: Date, _ cal: Calendar = .current) -> [AblaufPunkt] {
        let von = cal.startOfDay(for: jetzt)
        let bis = cal.date(byAdding: .day, value: 2, to: von) ?? von.addingTimeInterval(2 * 86_400)
        var gesehen = Set<String>()
        var aus: [AblaufPunkt] = []
        for p in (mac?.punkte ?? []) + kalender.map(punkt) + geraet.map(punkt) {
            guard !p.titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let drin = p.zeit >= von && p.zeit < bis || (!p.ganztags && p.zeit < von && (p.ende ?? p.zeit) > von)
            guard drin, gesehen.insert(schluessel(p)).inserted else { continue }
            aus.append(p)
        }
        return aus.sorted { $0.zeit < $1.zeit }
    }

    static func ganztags(_ punkte: [AblaufPunkt], jetzt: Date, _ cal: Calendar = .current) -> String? {
        punkte.first { $0.ganztags && cal.isDate($0.zeit, inSameDayAs: jetzt) }?.titel
    }

    static func zeilen(_ punkte: [AblaufPunkt], aufgaben: [String], weitereAufgaben: Int = 0, jetzt: Date, platz: Int, _ cal: Calendar = .current) -> [AblaufZeile] {
        let mitUhr = punkte.filter { !$0.ganztags }
        let heute = mitUhr.filter { cal.isDate($0.zeit, inSameDayAs: jetzt) || ($0.zeit < jetzt && $0.laeuft(jetzt)) }
        let laeuft = heute.filter { $0.laeuft(jetzt) }
        let war = heute.filter { $0.zeit <= jetzt && !$0.laeuft(jetzt) }
        let kommt = heute.filter { $0.zeit > jetzt }
        let morgen = mitUhr.filter { $0.zeit > jetzt && !cal.isDate($0.zeit, inSameDayAs: jetzt) && !$0.routine }

        let meine = Array(aufgaben.prefix(hoechstensAufgaben))
        let rest = weitereAufgaben + max(0, aufgaben.count - meine.count)
        var fest: [AblaufZeile] = [.jetzt] + laeuft.suffix(1).map(AblaufZeile.laeuft) + meine.map(AblaufZeile.aufgabe)
        if rest > 0 { fest.append(.weitereAufgaben(rest)) }
        var frei = max(0, platz - fest.count)
        var danach: [AblaufZeile] = []
        if kommt.isEmpty, !morgen.isEmpty, frei >= 2 {
            danach = [.morgen] + morgen.prefix(min(2, frei - 1)).map(AblaufZeile.morgenPunkt)
            frei -= danach.count
        }
        var nKommt = min(kommt.count, (frei * 2 + 2) / 3)
        let nWar = min(war.count, frei - nKommt)
        nKommt = min(kommt.count, frei - nWar)
        danach = kommt.prefix(nKommt).map(AblaufZeile.kommt) + danach
        return war.suffix(nWar).map(AblaufZeile.war) + fest + danach
    }

    static func hm(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    static func uhr(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.minute ?? 0) == 0 ? "\(c.hour ?? 0) Uhr" : String(format: "%d:%02d Uhr", c.hour ?? 0, c.minute ?? 0)
    }

    static func text(_ p: AblaufPunkt) -> String {
        switch p.art {
        case "ort_ankunft": return "\(p.titel) erreicht"
        case "ort_abfahrt": return "\(p.titel) verlassen"
        case "training":
            guard let e = p.ende, e > p.zeit else { return p.titel }
            let min = Int((e.timeIntervalSince(p.zeit) / 60).rounded())
            return "\(p.titel), \(min) Minuten"
        default: return p.titel
        }
    }

    static func wartetTeile(_ w: AblaufWartet, jetzt: Date, _ cal: Calendar = .current) -> (kopf: String, anlass: String) {
        var s = "\(w.wer) wartet"
        if let seit = w.seit { s += " seit \(seitText(seit, jetzt: jetzt, cal))" }
        let worum = kurz(w.worum, 46)
        guard !worum.isEmpty else { return (s + " auf deine Antwort.", "") }
        return (s + ":", worum + (worum.last.map { ".?!…".contains($0) } == true ? "" : "."))
    }
    static func wartetSatz(_ w: AblaufWartet, jetzt: Date, _ cal: Calendar = .current) -> String {
        let t = wartetTeile(w, jetzt: jetzt, cal)
        return t.anlass.isEmpty ? t.kopf : t.kopf + " " + t.anlass
    }

    static func seitText(_ seit: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: seit), to: cal.startOfDay(for: jetzt)).day ?? 0
        switch tage {
        case ...0: return uhr(seit, cal)
        case 1: return "gestern"
        case 2: return "vorgestern"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE"); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "EEEE"
            return f.string(from: seit)
        }
    }

    static func kurz(_ s: String, _ laenge: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > laenge else { return t }
        let kopf = t.prefix(laenge)
        let schnitt = kopf.lastIndex(of: " ").map { kopf[..<$0] } ?? kopf
        return schnitt.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    static func laeuftSaetze(_ laufend: [(wer: String, woran: String)], fertig: Int) -> [String] {
        func eins(_ l: (wer: String, woran: String)) -> String {
            l.wer.isEmpty ? "„\(l.woran)“ läuft gerade für dich." : "\(l.wer) arbeitet gerade an „\(l.woran)“."
        }
        switch laufend.count {
        case 0:
            guard fertig > 0 else { return [] }
            return [fertig == 1 ? "Heute ist eine Arbeit für dich fertig geworden, gerade läuft keine."
                                : "Heute sind \(zahl(fertig)) Arbeiten für dich fertig geworden, gerade läuft keine."]
        case 1: return [eins(laufend[0])]
        case 2: return [eins(laufend[0]), eins(laufend[1])]
        default:
            let rest = laufend.count - 1
            return [eins(laufend[0]), rest == 1 ? "Dazu läuft eine weitere Arbeit für dich." : "Dazu laufen \(zahl(rest)) weitere Arbeiten für dich."]
        }
    }

    static func weitereSatz(_ n: Int) -> String {
        n == 1 ? "Eine weitere wartet heute noch." : "\(zahl(n).prefix(1).uppercased() + zahl(n).dropFirst()) weitere warten heute noch."
    }

    static func zahl(_ n: Int) -> String {
        let w = ["null", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
        return n >= 0 && n < w.count ? w[n] : String(n)
    }

    static func ansage(_ punkte: [AblaufPunkt], jetzt: Date, _ cal: Calendar = .current) -> String {
        let termine = punkte.filter { !$0.ganztags && $0.istTermin && !$0.routine }
        let laeuft = termine.last { $0.laeuft(jetzt) }
        let naechster = termine.first { $0.zeit > jetzt && cal.isDate($0.zeit, inSameDayAs: jetzt) }
        func wo(_ p: AblaufPunkt) -> String { WidgetLogic.shortPlace(p.ort, title: p.titel).map { ", \($0)" } ?? "" }
        var saetze: [String] = []
        if let l = laeuft { saetze.append("Gerade läuft „\(l.titel)“" + (l.ende.map { " bis \(uhr($0, cal))" } ?? "") + ".") }
        if let n = naechster {
            saetze.append((laeuft == nil ? "Als Nächstes kommt" : "Danach kommt") + " um \(uhr(n.zeit, cal)) „\(n.titel)“\(wo(n)).")
        } else {
            saetze.append(laeuft == nil ? "Heute steht nichts mehr an." : "Danach steht heute nichts mehr an.")
            if let m = termine.first(where: { $0.zeit > jetzt }) { saetze.append("Morgen geht es um \(uhr(m.zeit, cal)) mit „\(m.titel)“ los.") }
        }
        return saetze.joined(separator: " ")
    }

    static func wartetAnsage(_ namen: [String]) -> String {
        switch namen.count {
        case 0: return ""
        case 1: return "\(namen[0]) wartet auf deine Antwort."
        case 2: return "\(namen[0]) und \(namen[1]) warten auf deine Antwort."
        default:
            let rest = namen.count - 2
            return "\(namen[0]), \(namen[1]) und \(rest == 1 ? "eine weitere Person" : "\(zahl(rest)) weitere") warten auf deine Antwort."
        }
    }

    static func widget(_ punkte: [AblaufPunkt], jetzt: Date, stand: Date? = nil, _ cal: Calendar = .current) -> WidgetSnapshot {
        let von = cal.startOfDay(for: jetzt)
        let horizont = cal.date(byAdding: .day, value: 2, to: von) ?? von.addingTimeInterval(2 * 86_400)
        let termine = punkte.filter { !$0.ganztags && $0.istTermin }
        func item(_ p: AblaufPunkt) -> WidgetSnapshot.Item {
            WidgetSnapshot.Item(title: p.titel, start: p.zeit, end: p.ende ?? p.zeit.addingTimeInterval(1800), place: p.ort)
        }
        var s = WidgetLogic.snapshot(items: termine.map(item), now: jetzt, horizon: horizont, stand: stand)
        s.laufend = termine.filter { $0.laeuft(jetzt) && !$0.routine }.map(item)
        return s
    }
}

struct Entscheidung: Equatable, Codable, Identifiable {
    struct Option: Equatable, Codable { var key: String; var titel: String }
    var id: String
    var frage: String
    var kurz = ""
    var kontext = ""
    var optionen: [Option] = []
    var empfohlen: String? = nil
    var empfehlung = ""
    var bereich = ""
    var antwortSitzung = ""
    var gestelltAm: Double = 0
    var updatedAt: Double? = nil
    var ruht = false

    static func liste(_ json: [String: Any]) -> [Entscheidung]? {
        guard json["ok"] as? Bool != false, let roh = json["entscheidungen"] as? [[String: Any]] else { return nil }
        let heute = json["heute"] as? String ?? ""
        func text(_ v: Any?) -> String { (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return roh.compactMap { e in
            let id = text(e["id"]), frage = text(e["frage"])
            guard !id.isEmpty, !frage.isEmpty else { return nil }
            var d = Entscheidung(id: id, frage: frage, kurz: text(e["kurz"]), kontext: text(e["kontext"]))
            d.optionen = (e["optionen"] as? [[String: Any]] ?? []).compactMap { o in
                let k = text(o["key"]), t = text(o["titel"])
                return k.isEmpty || t.isEmpty ? nil : Option(key: k, titel: t)
            }
            if let emp = e["empfehlung"] as? [String: Any] { d.empfohlen = text(emp["key"]).isEmpty ? nil : text(emp["key"]); d.empfehlung = text(emp["text"]) }
            d.bereich = [text(e["bereichName"]), text(e["projektName"])].first { !$0.isEmpty } ?? ""
            d.antwortSitzung = text(e["leiterSession"])
            d.gestelltAm = (e["gestelltAm"] as? NSNumber)?.doubleValue ?? 0
            d.updatedAt = (e["updatedAt"] as? NSNumber)?.doubleValue
            let bis = text(e["gesnooztBis"])
            d.ruht = e["ruhend"] as? Bool == true || (!bis.isEmpty && !heute.isEmpty && bis > heute)
            return d
        }
    }
}

enum BrauchtDich: Equatable, Identifiable {
    case abnahme(karte: String, satz: String)
    case person(AblaufWartet)
    case entscheidung(Entscheidung, klartext: String?)
    case frage(Frage)

    var id: String {
        switch self {
        case .abnahme(let k, _): return "abnahme:" + k
        case .person(let w): return "person:" + w.id
        case .entscheidung(let e, _): return "entscheidung:" + e.id
        case .frage(let f): return "frage:" + f.id
        }
    }
    var istEntscheidung: Bool {
        switch self {
        case .entscheidung, .frage: return true
        default: return false
        }
    }
    var istAbnahme: Bool { if case .abnahme = self { return true }; return false }
}

struct KopfSatz: Equatable {
    var vor = ""
    var akzent = ""
    var nach = ""
    var leise = ""
    var termin: AblaufPunkt? = nil
    var text: String { vor + akzent + nach }
}

struct TagesBild: Equatable {
    struct Block: Equatable, Identifiable {
        enum Lage: Equatable { case war, laeuft, kommt }
        var id: String
        var von: Double
        var bis: Double
        var titel: String
        var zeit: String
        var lage: Lage
        var training = false
        var leise = false
        var anteil: Double = 0
        var nenne = false
    }
    struct Zeichen: Equatable, Identifiable {
        var id: String
        var x: Double
        var symbol: String
        var war: Bool
        var name: String
    }
    struct Marke: Equatable, Identifiable {
        var x: Double
        var text: String
        var tag = false
        var id: String { "\(text)|\(x)" }
    }
    struct Schild: Equatable, Identifiable {
        var id: String
        var x: Double
        var breite: Double
        var reihe: Int
        var zeit: String
        var titel: String
        var hell: Bool
        var anker: Double
    }
    var von: Date
    var bis: Date
    var jetzt: Double
    var jetztText: String
    var bloecke: [Block] = []
    var zeichen: [Zeichen] = []
    var marken: [Marke] = []
}

extension Tagesablauf {
    static func kopf(_ punkte: [AblaufPunkt], braucht: [BrauchtDich], aufgaben: Int = 0, stand: Bool = true, jetzt: Date, _ cal: Calendar = .current) -> KopfSatz {
        let termine = punkte.filter { !$0.ganztags && $0.istTermin && !$0.routine }
        if let l = termine.last(where: { $0.laeuft(jetzt) }) {
            return KopfSatz(akzent: l.titel, nach: l.ende.map { " läuft bis \(uhr($0, cal))." } ?? " läuft gerade.", leise: l.ort ?? "", termin: l)
        }
        if let n = termine.first(where: { $0.zeit > jetzt && cal.isDate($0.zeit, inSameDayAs: jetzt) }) {
            return KopfSatz(vor: "Um \(uhr(n.zeit, cal)) steht ", akzent: n.titel, nach: " an.", leise: n.ort ?? "", termin: n)
        }
        if !stand {
            return KopfSatz(vor: "Vom Mac liegt gerade ", akzent: "kein Stand", nach: " vor.", leise: "Was auf dich wartet und was für dich läuft, steht hier, sobald dein Mac antwortet.")
        }
        if !braucht.isEmpty {
            if braucht.count == 1, case .person(let w) = braucht[0] { return KopfSatz(akzent: w.wer, nach: " wartet auf deine Antwort.") }
            let n = braucht.count
            let menge = zahl(n).prefix(1).uppercased() + zahl(n).dropFirst()
            if braucht.allSatisfy(\.istAbnahme) {
                return KopfSatz(akzent: n == 1 ? "Eine fertige Arbeit" : "\(menge) fertige Arbeiten", nach: n == 1 ? " wartet auf deine Prüfung." : " warten auf deine Prüfung.")
            }
            let wort = braucht.allSatisfy(\.istEntscheidung) ? (n == 1 ? "Entscheidung" : "Entscheidungen") : (n == 1 ? "Sache" : "Sachen")
            return KopfSatz(akzent: "\(menge) \(wort)", nach: n == 1 ? " wartet auf dich." : " warten auf dich.")
        }
        if aufgaben > 0 {
            let menge = zahl(aufgaben).prefix(1).uppercased() + zahl(aufgaben).dropFirst()
            return KopfSatz(akzent: aufgaben == 1 ? "Eine Aufgabe" : "\(menge) Aufgaben", nach: aufgaben == 1 ? " steht heute noch bei dir an." : " stehen heute noch bei dir an.")
        }
        if let m = termine.first(where: { $0.zeit > jetzt }), let morgen = cal.date(byAdding: .day, value: 1, to: jetzt), cal.isDate(m.zeit, inSameDayAs: morgen) {
            return KopfSatz(vor: "Morgen um \(uhr(m.zeit, cal)) steht ", akzent: m.titel, nach: " an.", leise: m.ort ?? "", termin: m)
        }
        let war = punkte.filter { !$0.ganztags && !$0.routine && ($0.istTermin || $0.art == "training") && cal.isDate($0.zeit, inSameDayAs: jetzt) && ($0.ende ?? $0.zeit) <= jetzt }
        if let w = war.last { return KopfSatz(akzent: w.titel, nach: " ist geschafft, heute ist nichts mehr offen.") }
        return cal.component(.hour, from: jetzt) < 12 ? KopfSatz(vor: "Heute ist nichts eingetragen, ", akzent: "der Tag gehört dir", nach: ".")
                                                       : KopfSatz(vor: "Heute ist ", akzent: "nichts mehr offen", nach: ".")
    }

    static func laeuftZeile(_ n: Int) -> String {
        switch n {
        case ...0: return ""
        case 1: return "Eine Arbeit läuft für dich."
        default: return "\(zahl(n).prefix(1).uppercased() + zahl(n).dropFirst()) Arbeiten laufen für dich."
        }
    }

    static func aufgabenSatz(_ n: Int) -> String {
        n == 1 ? "Eine Aufgabe steht heute bei dir an." : "\(zahl(n).prefix(1).uppercased() + zahl(n).dropFirst()) Aufgaben stehen heute bei dir an."
    }

    static func nochSatz(_ n: Int) -> String {
        switch n {
        case ...0: return ""
        case 1: return "Danach kommt noch eine."
        default: return "Danach kommen noch \(zahl(n))."
        }
    }

    private static func stunde(_ d: Date, auf: Bool, _ cal: Calendar) -> Date {
        let unten = cal.dateInterval(of: .hour, for: d)?.start ?? d
        return auf && unten < d ? unten.addingTimeInterval(3600) : unten
    }

    static func bild(_ punkte: [AblaufPunkt], jetzt: Date, _ cal: Calendar = .current) -> TagesBild {
        let mitUhr = punkte.filter { !$0.ganztags }
        let wichtig = mitUhr.filter { !$0.routine && ($0.istTermin || $0.art == "training") }
        let heute = mitUhr.filter { !$0.routine && cal.isDate($0.zeit, inSameDayAs: jetzt) }
        var a = jetzt.addingTimeInterval(-3 * 3600)
        if let frueh = heute.first(where: { ($0.ende ?? $0.zeit) > jetzt.addingTimeInterval(-12 * 3600) }) { a = min(a, frueh.zeit.addingTimeInterval(-1800)) }
        a = stunde(a, auf: false, cal)
        var b = jetzt.addingTimeInterval(5 * 3600)
        if let l = wichtig.last(where: { cal.isDate($0.zeit, inSameDayAs: jetzt) }) { b = max(b, (l.ende ?? l.zeit.addingTimeInterval(3600)).addingTimeInterval(1800)) }
        var erstesLeise: String?
        if let n = wichtig.first(where: { $0.zeit > jetzt }) { b = max(b, (n.ende ?? n.zeit.addingTimeInterval(3600)).addingTimeInterval(3600)) }
        else if let n = mitUhr.first(where: { $0.zeit > jetzt && $0.istTermin }) { b = max(b, n.zeit.addingTimeInterval(4 * 3600)); erstesLeise = n.id }
        b = min(stunde(b, auf: true, cal), a.addingTimeInterval(30 * 3600))
        let dauer = b.timeIntervalSince(a)
        func x(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(a) / dauer)) }

        var bild = TagesBild(von: a, bis: b, jetzt: x(jetzt), jetztText: hm(jetzt, cal))
        for p in mitUhr where p.istTermin || p.art == "training" {
            let ende = p.ende ?? p.zeit.addingTimeInterval(1800)
            guard ende > a, p.zeit < b else { continue }
            let lage: TagesBild.Block.Lage = ende <= jetzt ? .war : (p.zeit <= jetzt ? .laeuft : .kommt)
            let anteil = lage == .laeuft ? jetzt.timeIntervalSince(p.zeit) / max(60, ende.timeIntervalSince(p.zeit)) : 0
            bild.bloecke.append(.init(id: p.id, von: x(p.zeit), bis: x(ende), titel: p.titel, zeit: hm(p.zeit, cal), lage: lage,
                                      training: p.art == "training", leise: p.routine, anteil: min(1, max(0, anteil)), nenne: p.id == erstesLeise))
        }
        for p in mitUhr where p.art == "ort_ankunft" && p.zeit >= a && p.zeit <= b {
            let name = p.titel.lowercased()
            let symbol = name.contains("zuhause") || name.contains("hause") ? "house.fill"
                : (name.contains("campus") || name.contains("büro") || name.contains("vodafone") ? "building.2.fill" : "mappin")
            bild.zeichen.append(.init(id: p.id, x: x(p.zeit), symbol: symbol, war: p.zeit <= jetzt, name: p.titel))
        }
        let schritt = dauer <= 12 * 3600 ? 2 : 3
        var t = a
        let wochentag = DateFormatter()
        wochentag.locale = Locale(identifier: "de_DE"); wochentag.calendar = cal; wochentag.timeZone = cal.timeZone; wochentag.dateFormat = "EEEE"
        while t <= b {
            let h = cal.component(.hour, from: t)
            if h == 0, t > a { bild.marken.append(.init(x: x(t), text: wochentag.string(from: t), tag: true)) }
            else if h % schritt == 0 { bild.marken.append(.init(x: x(t), text: "\(h)")) }
            t = t.addingTimeInterval(3600)
        }
        return bild
    }

    static func schilder(_ bild: TagesBild, breite: Double, zeichenBreite: Double = 6.8, hoechstens: Double = 150, reihen: Int = 2, luft: Double = 12) -> [TagesBild.Schild] {
        func rang(_ b: TagesBild.Block) -> Double {
            switch b.lage {
            case .laeuft: return -2
            case .kommt: return b.von
            case .war: return 2 + (1 - b.bis)
            }
        }
        var gesetzt: [TagesBild.Schild] = []
        for b in bild.bloecke.filter({ !$0.leise || $0.nenne }).sorted(by: { rang($0) < rang($1) }) {
            let zeichen = Double(b.zeit.count + 1 + b.titel.count)
            let w = min(hoechstens, max(44, zeichen * zeichenBreite + 4))
            let x = min(max(0, b.von * breite), max(0, breite - w))
            let lang = zeichen * zeichenBreite > 2 * hoechstens
            for reihe in (lang ? [reihen - 1] : Array(0..<reihen)) {
                let frei = !gesetzt.contains { $0.reihe == reihe && x < $0.x + $0.breite + luft && $0.x < x + w + luft }
                if frei {
                    gesetzt.append(.init(id: b.id, x: x, breite: w, reihe: reihe, zeit: b.zeit, titel: b.titel, hell: b.lage != .war, anker: b.von * breite))
                    break
                }
            }
        }
        return gesetzt
    }
}

extension Tagesablauf {
    static func zaehlt(_ p: AblaufPunkt) -> Bool { !p.ganztags && !p.routine && (p.istTermin || p.art == "training") }

    static func routineFenster(_ punkte: [AblaufPunkt], jetzt: Date, _ cal: Calendar = .current) -> DateInterval? {
        let r = punkte.filter { $0.routine && !$0.ganztags && cal.isDate($0.zeit, inSameDayAs: jetzt) }
        guard let von = r.map(\.zeit).min() else { return nil }
        let bis = r.map { $0.ende ?? $0.zeit.addingTimeInterval(1800) }.max() ?? von
        return DateInterval(start: von, end: max(von, bis))
    }

    static func jetztSatz(_ punkte: [AblaufPunkt], routineOffen: Bool = false, jetzt: Date, _ cal: Calendar = .current) -> KopfSatz {
        let wichtig = punkte.filter(zaehlt).sorted { $0.zeit < $1.zeit }
        func laeuft(_ p: AblaufPunkt) -> Bool { p.zeit <= jetzt && (p.ende.map { jetzt < $0 } ?? false) }
        let heute = wichtig.filter { cal.isDate($0.zeit, inSameDayAs: jetzt) || laeuft($0) }
        let kommt = heute.filter { $0.zeit > jetzt }
        func danach(_ p: AblaufPunkt?) -> String { p.map { "Danach \(hm($0.zeit, cal)) \($0.titel)." } ?? "" }
        let abends = cal.component(.hour, from: jetzt) >= 17

        if let l = heute.last(where: laeuft) {
            let frei = abends ? "Danach ist der Abend frei." : "Danach ist heute nichts mehr eingetragen."
            let leise = kommt.first.map { danach($0) } ?? frei
            return KopfSatz(vor: "Jetzt ", akzent: l.titel, nach: l.ende.map { ", bis \(hm($0, cal))." } ?? ".", leise: leise, termin: l)
        }
        if routineOffen, let r = routineFenster(punkte, jetzt: jetzt, cal), jetzt < r.end, jetzt >= r.start.addingTimeInterval(-2 * 3600) {
            return KopfSatz(vor: "Jetzt ", akzent: "Morgenroutine", nach: ", bis \(hm(r.end, cal)).", leise: danach(kommt.first))
        }
        if let n = kommt.first {
            let ort = n.ort.flatMap { $0.isEmpty ? nil : $0 }
            let leise = ort ?? danach(kommt.dropFirst().first)
            if n.zeit.timeIntervalSince(jetzt) >= 90 * 60 {
                return KopfSatz(vor: "Frei bis \(hm(n.zeit, cal)), dann ", akzent: n.titel, nach: ".", leise: leise, termin: n)
            }
            return KopfSatz(vor: "Als Nächstes ", akzent: n.titel, nach: " um \(hm(n.zeit, cal)).", leise: leise, termin: n)
        }
        let morgenTag = cal.date(byAdding: .day, value: 1, to: jetzt) ?? jetzt
        let morgen = wichtig.first { $0.zeit > jetzt && cal.isDate($0.zeit, inSameDayAs: morgenTag) }
        let leise = morgen.map { "Morgen \(hm($0.zeit, cal)) \($0.titel)." } ?? ""
        if heute.isEmpty && cal.component(.hour, from: jetzt) < 12 {
            return KopfSatz(vor: "Heute ist nichts eingetragen, ", akzent: "der Tag gehört dir", nach: ".", leise: leise, termin: morgen)
        }
        return KopfSatz(vor: "Heute steht ", akzent: "nichts mehr", nach: " an.", leise: leise, termin: morgen)
    }
}
