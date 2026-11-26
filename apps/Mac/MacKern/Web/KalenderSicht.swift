import Foundation

struct KalenderSicht {
    var termine: [OvTermin]
    var kal: OvKalender?
    var ab: Double
    var bis: Double
    var tage: Int
    var gelesenAm: Double?
    var heute0: Double
    var jetzt: Double

    init(lang: OvKalender?, kurz: OvKalender?, jetzt: Double) {
        self.jetzt = jetzt
        heute0 = Menschlich.tagStart(jetzt)
        termine = (lang?.termine ?? []) + (lang?.vergangen?.termine ?? []) + (kurz?.termine ?? [])
        kal = kurz ?? lang
        let t = lang.flatMap { $0.zeitraumTage > 0 ? $0.zeitraumTage : nil } ?? kurz.flatMap { $0.zeitraumTage > 0 ? $0.zeitraumTage : nil }
            ?? ((kurz != nil && kurz?.fehlt == false) ? 2 : 0)
        tage = t
        bis = Menschlich.addTage(heute0, t)
        if let v = lang?.vergangen, v.ok { ab = Menschlich.tagStart(v.ab) } else { ab = heute0 }
        gelesenAm = (kurz?.geprueftAm).flatMap { Frische.ausStempel($0) } ?? (lang?.geprueftAm).flatMap { Frische.ausStempel($0) }
    }

    func gelesen(_ t: Double) -> Bool { t >= ab && t < bis }

    var kannSchreiben: Bool { kal.map { !$0.fehlt && !$0.schreibbar.isEmpty } ?? false }

    var stand: String {
        if let g = gelesenAm {
            return "Kalender gelesen \(Menschlich.tagText(g, jetzt: jetzt)) \(Menschlich.hhmm(g))" + (jetzt - g > 3 * 3_600_000 ? ", veraltet" : "")
        }
        if let k = kal, !k.fehlt { return "Kalender gelesen, Zeit unbekannt" }
        return "Kalender nicht angebunden"
    }

    var reicht: String {
        guard tage > 0 else { return "" }
        var s = "reicht bis \(Self.datumKurz(Menschlich.addTage(bis, -1)))"
        if ab < heute0 { s += ", zurück bis \(Self.datumKurz(ab))" }
        return s
    }

    var alt: Bool {
        guard let g = gelesenAm, let k = kal else { return true }
        return jetzt - g > 3 * 3_600_000 || k.fehlt || !k.ok
    }

    static func datumKurz(_ ms: Double) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        return "\(c.day ?? 1). \(Menschlich.monatLang[(c.month ?? 1) - 1])"
    }

    func leerSatz(tag0: Double, hatTermine: Bool, hatZeilen: Bool, hatPlanOhne: Bool) -> (text: String, ungelesen: Bool)? {
        if hatTermine { return nil }
        guard let k = kal, !k.fehlt else { return ("Der Kalender ist noch nicht angebunden.", false) }
        if !k.ok { return ("Seneca kommt gerade nicht an deinen Kalender.", false) }
        if !gelesen(tag0) {
            if tag0 < heute0 { return ("Dieser Tag liegt vor dem Zeitraum, den Seneca eingelesen hat (ab \(Self.datumKurz(ab))).", true) }
            return ("Diesen Tag hat Seneca noch nicht eingelesen. Der Kalender reicht bis \(Self.datumKurz(Menschlich.addTage(bis, -1))).", true)
        }
        if !hatZeilen && !hatPlanOhne { return ("Dieser Tag ist frei.", false) }
        return nil
    }

    static func planFuerTag(_ cards: [OvKarte], tag0: Double) -> (mit: [HeuteLogik.TodoEin], ohne: [String]) {
        var mit: [HeuteLogik.TodoEin] = [], ohne: [String] = []
        for c in cards {
            if c.status == "done" || c.archiviert || !(c.agentId ?? "").isEmpty || c.labels.contains(where: { $0.hasPrefix("entscheidung") }) { continue }
            let p = HeuteLogik.planInfo(c)
            guard p.tag == tag0 else { continue }
            let titel = Menschlich.klartext(c.title)
            if let m = p.min { mit.append(HeuteLogik.TodoEin(id: c.id, titel: titel, min: m, bis: p.bis, hinweis: nil)) }
            else if !ohne.contains(titel) { ohne.append(titel) }
        }
        return (mit, ohne)
    }

    static func tagName(_ t: Double, heute0: Double) -> String {
        switch Menschlich.tageZwischen(heute0, t) {
        case 0: return "Heute"
        case 1: return "Morgen"
        case -1: return "Gestern"
        default: return Menschlich.datumLang(t)
        }
    }
}
