import Foundation

enum MenueTafelLogik {
    struct Zeile: Equatable { var kopf: String; var text: String; var leise: String?; var punkt: String }

    static func fokusBis(_ s: SenecaStand) -> Double? { s.ruhe?.grund == "fokus" ? s.ruhe?.bis : nil }

    static func fragen(_ s: SenecaStand) -> [SenecaStand.Frage] { (s.braucht_dich ?? []).filter { $0.antwort == nil } }

    private static func kurz(_ f: SenecaStand.Frage) -> String { (f.kurz ?? f.projekt ?? f.text).replacingOccurrences(of: "?", with: "").components(separatedBy: " freigeben")[0] }

    static func danach(_ s: SenecaStand) -> Zeile? {
        guard let bis = fokusBis(s), let f = fragen(s).first else { return nil }
        let n = fragen(s).count, wort = kurz(f).components(separatedBy: " ")[0]
        let artikel = ["ung", "heit", "keit", "schaft", "e"].contains { wort.hasSuffix($0) } ? "die" : "der"
        return Zeile(kopf: "DANACH · \(HeuteTafelLogik.uhr(bis))", text: n == 1 ? "1 Frage" : "\(n) Fragen", leise: "zuerst \(artikel) \(wort)", punkt: "aus")
    }

    static func unter(_ f: SenecaStand.Frage) -> String { [f.von, f.seit.map { "seit \(HeuteTafelLogik.uhr($0))" }, f.zusatz].compactMap { $0 }.joined(separator: " · ") }

    static func weitere(_ s: SenecaStand) -> String { fragen(s).dropFirst().map(kurz).joined(separator: ", ") }

    static func laeuft(_ s: SenecaStand) -> Zeile? {
        guard let m = s.team?.first(where: { $0.zustand == "arbeitet" && $0.id != Hauptagent.id }) else { return nil }
        return Zeile(kopf: "LÄUFT", text: "\(m.name) \(m.satz ?? "arbeitet")", leise: m.rest_min.map { "noch \(Int($0)) Min" }, punkt: "gruen")
    }

    static func termin(_ s: SenecaStand) -> Zeile? {
        guard let t = (s.termine ?? []).filter({ $0.ganztag != true && $0.start > s.jetzt }).min(by: { $0.start < $1.start }) else { return nil }
        return Zeile(kopf: "NÄCHSTER TERMIN", text: "\(HeuteTafelLogik.uhr(t.start)) \(t.titel)", leise: t.weg_min.map { "los um \(HeuteTafelLogik.uhr(t.start - $0 * 60_000))" }, punkt: "aus")
    }

    static func jetzt(_ s: SenecaStand) -> Zeile? {
        guard let t = (s.termine ?? []).first(where: { $0.ganztag != true && $0.start <= s.jetzt && $0.ende > s.jetzt }) else { return nil }
        return Zeile(kopf: "JETZT", text: "\(t.titel) bis \(HeuteTafelLogik.uhr(t.ende))", leise: (s.todos ?? []).isEmpty ? nil : "danach To-dos", punkt: "aus")
    }

    static func imFenster(_ s: SenecaStand) -> Zeile? {
        guard let f = fragen(s).first ?? s.buendel?.fragen?.first, let b = s.buendel?.fenster else { return nil }
        return Zeile(kopf: "BRAUCHT DICH", text: kurz(f), leise: "im Fenster um \(HeuteTafelLogik.uhr(b))", punkt: "bernstein")
    }
}
