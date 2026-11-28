import Foundation

enum GespraecheTafelLogik {
    enum Punkt { case arbeitet, wartet, fertig, ruht }

    struct Zeile: Equatable {
        var text: String
        var hervor = false
    }

    static func fragen(_ s: SenecaStand, von name: String) -> [SenecaStand.Frage] {
        ((s.braucht_dich ?? []) + (s.buendel?.fragen ?? [])).filter { $0.von == name && $0.antwort == nil }
    }

    private static func anzahl(_ n: Int) -> String { n == 1 ? "1 Frage" : "\(n) Fragen" }

    static func mitglied(_ m: SenecaStand.Mitglied, _ s: SenecaStand) -> (punkt: Punkt, zeilen: [Zeile]) {
        let n = fragen(s, von: m.name).count
        switch m.zustand {
        case "arbeitet", "hängt":
            return (.arbeitet, [Zeile(text: (m.satz ?? "arbeitet") + (n > 0 ? " · " : ""))] + (n > 0 ? [Zeile(text: anzahl(n), hervor: true)] : []))
        case "ruht": return (.ruht, [Zeile(text: m.ruht_seit.map { VerlaufLogik.ruhtSeit($0, jetzt: s.jetzt) } ?? "ruht")])
        default:
            if n > 0 { return (.wartet, [Zeile(text: "wartet auf dich · \(anzahl(n))", hervor: true)]) }
            if let z = m.zuletzt, let satz = z.satz { return (.fertig, [Zeile(text: "fertig · \(satz)" + (z.um.map { " · \(HeuteTafelLogik.uhr($0))" } ?? ""))]) }
            return (.fertig, [Zeile(text: "frei")])
        }
    }

    static func leiste(_ s: SenecaStand) -> [(m: SenecaStand.Mitglied, punkt: Punkt, zeilen: [Zeile])] {
        let rang: [Punkt] = [.arbeitet, .wartet, .fertig, .ruht]
        return (s.team ?? []).filter { $0.id != Hauptagent.id }.map { m in let z = mitglied(m, s); return (m, z.punkt, z.zeilen) }
            .filter { $0.punkt != .fertig || $0.m.zuletzt != nil }
            .enumerated().sorted { (rang.firstIndex(of: $0.element.punkt) ?? 9, $0.offset) < (rang.firstIndex(of: $1.element.punkt) ?? 9, $1.offset) }.map(\.element)
    }

    static func hilfe(_ m: SenecaStand.Mitglied, _ zeilen: [Zeile]) -> String {
        var s = zeilen.map(\.text).joined()
        if m.zustand == "arbeitet" || m.zustand == "hängt" {
            if let t = m.titel, !t.isEmpty { s += " · Auftrag „\(t)“" }
            if let r = m.rest_min { s += " · noch etwa \(Int(r)) Min" }
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Nur ein echter Tätigkeitssatz („schreibt die Begrüßung“) ergibt eine Zeile. Ein Zustandswort wie „angenommen“ ergäbe Unsinn.
    static func laufSatz(_ m: SenecaStand.Mitglied) -> String? {
        let w = ohneNummern(m.satz ?? "").split(separator: " ", maxSplits: 1).map(String.init)
        guard w.count == 2, !["angenommen", "arbeitet", "wartet", "frei", "fertig"].contains(w[0].lowercased()) else { return nil }
        return "Solange du überlegst, \(w[0]) \(m.name) \(w[1])" + (m.rest_min.map { " · noch etwa \(Int($0)) Min" } ?? "")
    }

    /// Antwort-Etikett ist zu lang für einen Knopf (gleiche Regel wie die Kachel auf Heute und der Server).
    static func langesEtikett(_ s: String) -> Bool { s.count > 28 || s.split(separator: " ").count > 3 }

    /// Serifen-Überschrift: bis 80 Zeichen groß, bis 130 mittel, darüber klein (wie die Kachel auf Heute).
    static func ueberschrift(_ t: String, gross: Double = 38) -> (groesse: Double, zeile: Double) {
        t.count <= 80 ? (gross, gross + 3) : t.count <= 130 ? (30, 34) : (25, 29)
    }

    /// Erster Satz, für knappe Zeilen am Rand.
    static func ersterSatz(_ t: String) -> String {
        let s = ohneNummern(t)
        guard let r = s.range(of: #"(?<!\d)[.!?](\s+(?=[A-ZÄÖÜ„])|$)"#, options: .regularExpression) else { return s }
        return String(s[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
    }

    private static let nummer = #"(?:\b[0O]m(?=[a-z]*\d)[a-z0-9]{6,}…?|(?<![+\d])\b[1-9]\d{8,}\b|\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b)"#
    private static let nummerRegeln: [(NSRegularExpression, String)] = [
        (#"\s*\((?:[A-Za-zÄÖÜäöüß-]+\s)?§(?:\s*(?:,|/|und)\s*§)*\)"#, ""),
        (#"\s*(?:\b(?:Frage|Lauf|Run|Auftrag|Aufträgen|Aufträge|ID|Nr\.?)\s)?§(?:\s*(?:,|/|und)\s*§)*"#, ""),
        (#"\(\s*\)"#, ""), (#"[ \t]{2,}"#, " "), (#"\s+([.,;:!?)])"#, "$1"), (#"\(\s+"#, "("),
    ].compactMap { m, z in (try? NSRegularExpression(pattern: m.replacingOccurrences(of: "§", with: nummer)), z) }.map { ($0.0!, $0.1) }

    /// Interne Nummern (Auftrags-IDs „0m…“, Lauf-Nummern ab 9 Ziffern, Hashes) zeigt die App nie. Einziger Ort dafür.
    static func ohneNummern(_ t: String) -> String {
        guard t.range(of: nummer, options: .regularExpression) != nil else { return t }
        var s = t
        for (r, z) in nummerRegeln { s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: z) }
        return s
    }

    static func seneca(_ s: SenecaStand) -> String? {
        guard let m = s.team?.first(where: { $0.id == Hauptagent.id }) else { return nil }
        if m.zustand == "arbeitet", let satz = m.satz { return satz }
        return m.zuletzt.flatMap { z in z.satz.map { $0 + (z.um.map { " · \(HeuteTafelLogik.uhr($0))" } ?? "") } }
    }

    static func heuteMitSeneca(_ s: SenecaStand) -> [Zeile] {
        var z: [Zeile] = []
        if s.ruhe?.grund == "fokus", let bis = s.ruhe?.bis { z.append(Zeile(text: "Fokus bis \(HeuteTafelLogik.uhr(bis))", hervor: true)) }
        let heute = s.wochenplan?.tage.first { KalenderLogik.gleicherTag($0.tag, s.jetzt) }?.bloecke ?? []
        for b in heute where b.ende > s.jetzt {
            if let da = b.detail?.da { z.append(Zeile(text: "\(HeuteTafelLogik.uhr(da)) bei \(b.detail?.mit ?? b.titel)")) }
            if b.art == "fenster" { z.append(Zeile(text: "\(HeuteTafelLogik.uhr(b.start)) \(b.titel)")) }
        }
        return z
    }

    static func standSatz(_ phasen: [SenecaStand.Phase]) -> String {
        let fertig = phasen.filter { $0.zustand == "fertig" }.map(\.name)
        let jetzt = phasen.first { $0.zustand == "jetzt" }?.name
        let danach = phasen.drop { $0.zustand != "jetzt" }.dropFirst().map(\.name)
        var s = fertig.isEmpty ? "" : fertig.joined(separator: " · ") + " fertig."
        if let jetzt { s += (s.isEmpty ? "" : " ") + "Jetzt \(jetzt)" + (danach.isEmpty ? "." : ", dann \(danach.joined(separator: ", ")).") }
        return s
    }

    static func mitmachen(_ s: SenecaStand, projekt: String) -> [(name: String, was: String, hervor: Bool)] {
        var l: [(String, String, Bool)] = (s.team ?? []).filter { $0.projekt == projekt && $0.id != Hauptagent.id }.map { ($0.name, $0.zustand == "arbeitet" ? "arbeitet" : $0.zustand, false) }
        if ((s.braucht_dich ?? []) + (s.buendel?.fragen ?? [])).contains(where: { $0.projekt == projekt && $0.antwort == nil }) { l.append(("Du", "gibst frei", true)) }
        return l
    }

    static func haupt(_ f: SenecaStand.Frage) -> SenecaStand.Option? { f.optionen?.first { $0.wert == f.empfehlung } ?? f.optionen?.first { $0.wert != "spaeter" } }

    static func gehalten(_ f: SenecaStand.Frage, _ s: SenecaStand) -> (bis: Double, grund: String)? {
        let z = (f.zustellung ?? []).sorted { ($0.zeit ?? 0) < ($1.zeit ?? 0) }
        guard let i = z.firstIndex(where: { $0.was == "zurueckgehalten" }), let bis = z.dropFirst(i + 1).first?.zeit ?? s.ruhe?.bis else { return nil }
        return (bis, z[i].grund ?? "")
    }

    static func mehrSeite(_ f: SenecaStand.Frage, _ s: SenecaStand) -> String {
        [f.von, f.projekt, HeuteTafelLogik.wochentag(s.jetzt), HeuteTafelLogik.uhr(s.jetzt)].compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    static func mehrKopf(_ f: SenecaStand.Frage, _ s: SenecaStand) -> String {
        let haelt = (gehalten(f, s)?.bis ?? 0) > s.jetzt
        return ["\(f.von ?? "Seneca") fragt", f.seit.map { "seit \(HeuteTafelLogik.uhr($0))" }, f.zurueckgehalten.flatMap { haelt ? String($0.split(separator: ",")[0]).replacingOccurrences(of: ".", with: "") : nil }]
            .compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    struct Gruppe: Equatable {
        var name: String
        var punkte: [String]
    }

    static func worum(_ text: String?, namen: [String]) -> (satz: String, gruppen: [Gruppe]) {
        var satz: [String] = [], gruppen: [Gruppe] = []
        for zeile in (text ?? "").split(separator: "\n").map(String.init) {
            if let r = zeile.range(of: ": "), namen.contains(String(zeile[..<r.lowerBound])) {
                gruppen.append(Gruppe(name: String(zeile[..<r.lowerBound]), punkte: zeile[r.upperBound...].components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
            } else {
                satz.append(zeile)
            }
        }
        return (satz.joined(separator: "\n"), gruppen)
    }

    static func spalten(_ g: [Gruppe]) -> [[Gruppe]] {
        var out: [[Gruppe]] = [[], []], hoehe = [0, 0]
        for x in g.sorted(by: { $0.punkte.count > $1.punkte.count }) {
            let i = hoehe[0] <= hoehe[1] ? 0 : 1
            out[i].append(x); hoehe[i] += x.punkte.count + 2
        }
        return out.filter { !$0.isEmpty }
    }

    static func gehaltenSatz(_ f: SenecaStand.Frage, _ s: SenecaStand) -> (um: Double, satz: String)? {
        guard let g = gehalten(f, s), let t = f.zurueckgehalten else { return nil }
        return (g.bis, "Seneca: " + t)
    }

    static func wennJa(_ f: SenecaStand.Frage) -> String {
        let k = (haupt(f)?.knopf ?? haupt(f)?.text ?? "").lowercased()
        return k.hasSuffix("geben") ? "WENN DU \(k.dropLast(5).uppercased())GIBST" : "WENN JA"
    }

    static func empfiehlt(_ f: SenecaStand.Frage) -> String {
        let h = f.optionen?.first { $0.wert == f.empfehlung }
        return [h.map { ($0.knopf ?? $0.text ?? "") + "." } ?? f.empfehlung, f.grund].compactMap { $0 }.joined(separator: " ")
    }

    static func wirktSatz(_ f: SenecaStand.Frage, _ s: SenecaStand) -> String {
        let n = Int(s.regeln?["rueckgaengig_s"] ?? 5)
        let k = haupt(f)?.knopf ?? haupt(f)?.text ?? "Ja"
        if (f.optionen ?? []).contains(where: { langesEtikett($0.knopf ?? $0.text ?? "") }) {
            return "Deine Wahl wirkt nach \(n < VerlaufLogik.zahlwort.count ? VerlaufLogik.zahlwort[n] : "\(n)") Sekunden. Bis dahin kannst du sie zurücknehmen."
        }
        return "\(k) wirkt nach \(n < VerlaufLogik.zahlwort.count ? VerlaufLogik.zahlwort[n] : "\(n)") Sekunden. Bis dahin kannst du es zurücknehmen."
    }

    static func wann(_ ms: Double, _ s: SenecaStand) -> String {
        if KalenderLogik.gleicherTag(ms, s.jetzt) { return HeuteTafelLogik.uhr(ms) }
        let k = KalenderLogik.cal().dateComponents([.day, .month], from: HeuteTafelLogik.datum(ms))
        return "\(k.day ?? 1). \(k.month ?? 1)."
    }

    struct Station: Equatable { var art: String; var titel: String; var unter: [String]; var teil: SenecaStand.Mitglied.Teil? = nil }

    static func station(_ s: SenecaStand, _ m: SenecaStand.Mitglied) -> Station? {
        let zahl = { (n: Int) in n < VerlaufLogik.zahlwort.count ? VerlaufLogik.zahlwort[n].replacingOccurrences(of: "eine", with: "einer") : "\(n)" }
        if m.zustand == "hängt" {
            let min = Int((s.jetzt - (m.schritte?.last?.um ?? m.seit ?? s.jetzt)) / 60_000)
            return Station(art: "haengt", titel: "\(m.name) kommt nicht weiter.", unter: ["Seit \(zahl(min)) \(min == 1 ? "Minute" : "Minuten") kein Schritt."])
        }
        if m.zustand == "arbeitet" {
            if let n = s.auftraege_neu?.first(where: { $0.wer == m.id }), m.schritte?.isEmpty ?? true {
                return Station(art: "angenommen", titel: "\(m.name) · angenommen",
                               unter: [[n.dauer_min.map { "schätzt etwa \(Int($0)) Minuten" }, n.bis.map { "fertig gegen \(HeuteTafelLogik.uhr($0))" }].compactMap { $0 }.joined(separator: " · ")])
            }
            let seit = m.seit.map { " · seit \(HeuteTafelLogik.uhr($0))" } ?? "", zuletzt = m.schritte?.last?.um ?? 0
            if let r = m.ruecklauf, let t = r.satz, (r.um ?? 0) >= zuletzt { return Station(art: "ruecklauf", titel: t, unter: ["zurück an \(m.name) · kein Hinweis an dich"]) }
            if let t = m.teil, t.um >= zuletzt { return Station(art: "teil", titel: t.satz, unter: ["meldet sich nicht · nur wer will, hört rein"], teil: t) }
            if m.id == "pruefer" { return Station(art: "arbeit", titel: "\(m.name) \(m.satz ?? "prüft")", unter: ["derselbe Auftrag" + seit]) }
            return Station(art: "arbeit", titel: (m.satz ?? "arbeitet") + seit, unter: (m.schritte ?? []).compactMap(\.satz), teil: m.teil)
        }
        guard let e = s.heute_erledigt?.last(where: { $0.wer == m.name }) else { return nil }
        let euro = (e.kosten_cent ?? 0) / 100
        return Station(art: "fertig", titel: e.titel + (e.pruefer == true ? " · geprüft" : ""),
                       unter: [[e.pruefer == true ? "\(m.name) und Prüfer" : m.name, e.min.map { "\(Int($0)) Minuten" }, String(format: "%.2f €", euro).replacingOccurrences(of: ".", with: ",")].compactMap { $0 }.joined(separator: " · ")])
    }
}
