import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveAnzeige {
    static let shared = LiveAnzeige()

    private weak var store: SenecaStore?
    private var abo: AnyCancellable?
    private var arbeitete: [String: SenecaStand.Mitglied] = [:]
    private var fertig: (SenecaLive.ContentState, Date)?
    private var quittung: (SenecaLive.ContentState, Date, String, String)?

    func starten(store: SenecaStore) {
        guard self.store == nil else { return }
        self.store = store
        SenecaLiveHaken.antwort = { [weak self] frage, wahl in self?.gewaehlt(frage, wahl) }
        abo = store.$stand.compactMap { $0 }.sink { [weak self] s in Task { @MainActor in await self?.zeigen(s) } }
    }

    static func zustand(_ s: SenecaStand, jetzt: Date, fertig: SenecaLive.ContentState? = nil) -> SenecaLive.ContentState? {
        let uhr = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute()
        let regel = { (n: String, w: Double) in s.regeln?[n] ?? w }
        if let t = s.termine?.first(where: { t in
            guard let weg = t.weg_min else { return false }
            let los = HeuteTafelLogik.datum(t.ankunft ?? t.start).addingTimeInterval(-weg * 60)
            return jetzt >= los.addingTimeInterval(-regel("los_erinnern_min", 6) * 60) && jetzt < los.addingTimeInterval(5 * 60)
        }), let weg = t.weg_min {
            let rest = Int((HeuteTafelLogik.datum(t.ankunft ?? t.start).addingTimeInterval(-weg * 60).timeIntervalSince(jetzt) / 60).rounded(.up))
            let da = HeuteTafelLogik.datum(t.ankunft ?? t.start).formatted(uhr)
            let unter = ["\(Int(weg)) Min zu Fuß", "du bist \(da) da", t.bescheid?.components(separatedBy: ",").first].compactMap { $0 }.joined(separator: " · ")
            return .init(art: "los", titel: [t.titel, t.ort].compactMap { $0 }.joined(separator: " · "), unter: unter, insel: rest > 0 ? "\(rest) Min" : "jetzt", bis: HeuteTafelLogik.datum(t.start))
        }
        let ruhe = s.ruhe.flatMap { r in (r.bis.map { HeuteTafelLogik.datum($0) > jetzt } ?? true) ? r : nil }
        if ruhe == nil, let f = s.braucht_dich?.first(where: { $0.mitteilung != nil }) {
            let o = TeamLogik.empfohlen(f)
            let seit = f.seit.map { " · SEIT \(HeuteTafelLogik.datum($0).formatted(uhr))" } ?? ""
            return .init(art: "frage", titel: f.text, unter: f.mitteilung?.text ?? "", insel: "\(s.braucht_dich?.count ?? 1) \(s.braucht_dich?.count == 1 ? "Frage" : "Fragen")",
                         kopf: "\((f.von ?? "Seneca").uppercased()) FRAGT\(seit)", frage: f.id, wahl: f.empfehlung ?? o?.wert ?? "ja", knopf: o?.text ?? "Ja")
        }
        if let m = s.team?.first(where: { $0.zustand == "arbeitet" && ($0.rest_min ?? 0) >= 2 }), let rest = m.rest_min {
            let lief = m.seit.map { jetzt.timeIntervalSince(HeuteTafelLogik.datum($0)) / 60 } ?? 0
            let titel = m.titel ?? [m.satz.map { $0.prefix(1).uppercased() + $0.dropFirst() }, m.projekt].compactMap { $0 }.joined(separator: " · ")
            return .init(art: "arbeitet", titel: titel, unter: "\(m.name) · noch \(Int(rest)) Min", insel: "\(Int(rest)) Min", anteil: lief / max(1, lief + rest), knopf: "Ansehen")
        }
        if let fertig { return fertig }
        if let r = ruhe, ["laufen", "trail"].contains(r.grund) {
            let n = s.braucht_dich?.count ?? 0
            return .init(art: "unterwegs", titel: "Unterwegs", unter: n == 0 ? "Seneca schweigt, bis du zurück bist. Nichts wartet." : "Seneca schweigt, bis du zurück bist. \(n) \(n == 1 ? "Sache wartet" : "Sachen warten").", insel: "läuft")
        }
        return nil
    }

    private func zeigen(_ s: SenecaStand) async {
        let jetzt = Date()
        for m in s.team ?? [] where m.zustand != "arbeitet" {
            if arbeitete.removeValue(forKey: m.name) != nil, let satz = m.zuletzt?.satz {
                fertig = (.init(art: "fertig", titel: satz, unter: s.ruhe?.grund == "fokus" ? "Kein Ton, du bist im Fokus." : m.name, insel: "fertig"), jetzt.addingTimeInterval(5 * 60))
            }
        }
        for m in s.team ?? [] where m.zustand == "arbeitet" { arbeitete[m.name] = m }
        if let f = fertig, f.1 < jetzt { fertig = nil }
        let ziel = quittung.map(\.0) ?? Self.zustand(s, jetzt: jetzt, fertig: fertig?.0)
        await setzen(ziel)
    }

    private func setzen(_ ziel: SenecaLive.ContentState?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let laufend = Activity<SenecaLive>.activities
        guard let ziel else {
            for a in laufend { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let inhalt = ActivityContent(state: ziel, staleDate: Date().addingTimeInterval(15 * 60))
        if let a = laufend.first {
            if a.content.state != ziel { await a.update(inhalt) }
            for b in laufend.dropFirst() { await b.end(nil, dismissalPolicy: .immediate) }
        } else {
            _ = try? Activity.request(attributes: SenecaLive(), content: inhalt)
        }
    }

    private func gewaehlt(_ frage: String, _ wahl: String) {
        if wahl == "rueckgaengig" {
            quittung = nil
            if let s = store?.stand { Task { await zeigen(s) } }
            return
        }
        guard wahl != "spaeter" else { store?.antworte(frage: frage, wahl: wahl); return }
        let f = store?.stand?.braucht_dich?.first { $0.id == frage }
        let folge = f?.optionen?.first { $0.wert == wahl }?.folge?.components(separatedBy: ". ").first ?? ""
        let dauer = store?.stand?.regeln?["rueckgaengig_s"] ?? 5
        let bis = Date().addingTimeInterval(dauer)
        let q = SenecaLive.ContentState(art: "quittung", titel: "Freigegeben", unter: folge, insel: "\(Int(dauer)) s", frage: frage, knopf: "Rückgängig", bis: bis)
        quittung = (q, bis, frage, wahl)
        Task {
            await setzen(q)
            try? await Task.sleep(for: .seconds(dauer))
            guard let q = quittung, q.2 == frage else { return }
            store?.antworte(frage: frage, wahl: wahl)
            quittung = nil
            if let s = store?.stand { await zeigen(s) }
        }
    }
}
