import SwiftUI

@MainActor
final class StatistikModel: ObservableObject {
    @Published private(set) var server: StatDaten = .leer
    @Published private(set) var laeufe: [StatLauf] = []
    @Published private(set) var gewichtHealth: [String: Double] = [:]
    @Published private(set) var wartend: [StatOp] = []
    @Published var meldung: String?

    private var outbox = StatOutbox()
    private var cache: [String: StatInhalt] = [:]
    private var wocheCache: (tag: String, stand: StatWochenStand)?
    private var demoAktiv = false

    init() {
        wartend = outbox.ops
        let health = StatHealthSync.shared
        laeufe = health.stand.laeufeSortiert
        gewichtHealth = health.stand.gewichtProTag
        health.beobachten { [weak self] stand in
            guard let self else { return false }
            self.healthUebernehmen(stand)
            return true
        }
    }

    private func healthUebernehmen(_ stand: StatHealthStand) {
        guard !demoAktiv else { return }
        let l = stand.laeufeSortiert, g = stand.gewichtProTag
        guard l != laeufe || g != gewichtHealth else { return }
        laeufe = l
        gewichtHealth = g
        geaendert()
    }

    var wartetAufMac: Bool { !wartend.isEmpty }

    func daten(jetzt: Date) -> StatDaten { server.anwenden(wartend, jetzt: jetzt) }
    func quellen(jetzt: Date) -> StatQuellen {
        StatQuellen(daten: daten(jetzt: jetzt), laeufe: laeufe, gewichtHealth: gewichtHealth, jetzt: jetzt)
    }

    func inhalt(_ z: StatZeitraum, zurueck: Int, jetzt: Date) -> StatInhalt {
        let key = "\(z.rawValue)-\(zurueck)-\(StatKalender.schluessel(jetzt))"
        if let c = cache[key] { return c }
        let r = StatAbschnitte.inhalt(z, quellen(jetzt: jetzt), monatZurueck: zurueck)
        cache[key] = r
        return r
    }
    func wochenStand(jetzt: Date) -> StatWochenStand {
        let key = StatKalender.schluessel(jetzt)
        if let c = wocheCache, c.tag == key { return c.stand }
        let q = quellen(jetzt: jetzt)
        let stand = StatWochenStand.bauen(StatTage(q), heute: q.heute)
        wocheCache = (key, stand)
        return stand
    }
    func laufenSeite(jetzt: Date) -> StatLaufenSeite { StatSeitenLogik.laufen(quellen(jetzt: jetzt)) }
    func buecherSeite(jetzt: Date) -> StatBuecherSeite { StatSeitenLogik.buecher(quellen(jetzt: jetzt)) }
    func kraftSeite(jetzt: Date) -> StatKraftSeite { StatKraft.seite(quellen(jetzt: jetzt)) }
    func uebungSeite(_ key: String, jetzt: Date) -> StatUebungSeite? { StatKraft.uebung(key, quellen(jetzt: jetzt)) }

    private func geaendert() {
        cache.removeAll()
        wocheCache = nil
        wartend = outbox.ops
        objectWillChange.send()
    }

    func laden(store: SenecaStore) async {
        if store.demo { ladeDemo(store.clock()); return }
        await senden(store: store)
        guard store.isConnected, let json = try? await store.rufe("seneca.statistik") else { return }
        server = StatDaten.parse(json)
        geaendert()
    }

    private func ladeDemo(_ jetzt: Date) {
        guard !demoAktiv else { return }
        demoAktiv = true
        outbox = StatOutbox(defaults: nil)
        let d = StatDemo.daten(jetzt: jetzt)
        server = d.daten
        laeufe = d.laeufe
        gewichtHealth = d.gewicht
        geaendert()
    }

    func healthErlauben(demo: Bool) async {
        guard !demo else { return }
        await StatHealthSync.shared.abgleichen(grund: .statistikOffen, fragen: true)
    }

    func schreiben(_ ops: [StatOp], store: SenecaStore) {
        for op in ops { outbox.hinzufuegen(op) }
        meldung = nil
        geaendert()
        Task { await senden(store: store) }
    }

    func senden(store: SenecaStore) async {
        guard !store.demo, !outbox.istLeer else { return }
        let r = await outbox.abarbeiten { op in try await store.rufe(op.methode, params: op.params) }
        for op in r.gesendet { server = server.anwenden(op, jetzt: store.clock()) }
        if let a = r.abgelehnt.last { meldung = a.meldung }
        geaendert()
        if outbox.istLeer, !r.gesendet.isEmpty || !r.abgelehnt.isEmpty, store.isConnected,
           let json = try? await store.rufe("seneca.statistik") {
            server = StatDaten.parse(json)
            geaendert()
        }
    }

    @discardableResult
    func lesenEintragen(minuten: Int, tag: String, notiz: String, buch: StatBuch?, neuesBuch: String?, store: SenecaStore) -> String {
        var ops: [StatOp] = []
        var buchId = buch?.id
        if let neu = neuesBuch {
            let b = StatOp.buchBeginnen(titel: neu, datum: tag, beendeAktuelles: true)
            ops.append(b)
            buchId = b.id
        }
        let aktuell = daten(jetzt: store.clock()).aktuellesBuch?.id
        let eintrag = StatOp.eintragen(thema: "lesen", wert: Double(minuten), datum: tag, notiz: notiz, buch: buchId == aktuell && neuesBuch == nil ? nil : buchId)
        ops.append(eintrag)
        schreiben(ops, store: store)
        return eintrag.id
    }

    func lesenZuruecknehmen(_ eintrag: String, store: SenecaStore) {
        schreiben([StatOp.entfernen(eintrag: eintrag)], store: store)
    }
}

struct StatWochenZeile: Identifiable, Equatable {
    var id: String
    var name: String
    var tage: [Bool]
    var summe: String
    var ziel: StatSeite
}

struct StatWochenStand: Equatable {
    var kuerzel: [String]
    var heute: Int
    var zeilen: [StatWochenZeile]

    static func bauen(_ t: StatTage, heute: String) -> StatWochenStand {
        let start = StatKalender.wochenstart(heute)
        let tage = (0..<7).map { StatKalender.plus(start, tage: $0) }
        let km = tage.reduce(0.0) { $0 + (t.km[$1] ?? 0) }
        let minuten = tage.reduce(0) { $0 + (t.lesezeit[$1] ?? 0) }
        let einheiten = tage.filter { t.training.contains($0) }.count
        let laufen = StatWochenZeile(id: "laufen", name: "Laufen", tage: tage.map { (t.km[$0] ?? 0) > 0 },
                                     summe: km > 0 ? "\(StatFormat.zahl(km, 1)) km" : "–", ziel: .laufen)
        let lesen = StatWochenZeile(id: "lesen", name: "Lesen", tage: tage.map { (t.lesezeit[$0] ?? 0) > 0 },
                                    summe: minuten > 0 ? StatFormat.lesezeit(minuten) : "–", ziel: .buecher)
        let kraft = StatWochenZeile(id: "kraft", name: "Krafttraining", tage: tage.map { t.training.contains($0) },
                                    summe: einheiten > 0 ? "\(einheiten) \(einheiten == 1 ? "Einheit" : "Einheiten")" : "–", ziel: .kraft)
        return StatWochenStand(kuerzel: ["M", "D", "M", "D", "F", "S", "S"], heute: StatKalender.wochentag(heute), zeilen: [laufen, lesen, kraft])
    }
}
