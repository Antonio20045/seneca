import Foundation

@MainActor
final class StatHealthSync {
    static let shared = StatHealthSync()

    private(set) var stand: StatHealthStand
    private var laeuft = false
    private let datei = StatHealthStand.standarddatei
    private var beobachter: [@MainActor (StatHealthStand) -> Bool] = []

    private init() { stand = StatHealthStand.laden(von: StatHealthStand.standarddatei) }

    func beobachten(_ f: @escaping @MainActor (StatHealthStand) -> Bool) { beobachter.append(f) }

    func abgleichen(grund: StatHealthGrund, fragen: Bool) async {
        guard HealthStatistik.verfuegbar, !laeuft, stand.braucht(grund, jetzt: Date()) else { return }
        laeuft = true
        defer { laeuft = false }
        if await HealthStatistik.mussFragen() {
            guard fragen else { return }
            await HealthStatistik.anfragen()
        }

        let jetzt = Date()
        let seit = Calendar.current.date(byAdding: .day, value: -StatHealthStand.fensterTage, to: jetzt) ?? jetzt
        let ankerLauf = stand.ankerLauf, ankerGewicht = stand.ankerGewicht
        async let l = HealthStatistik.neueLaeufe(anker: ankerLauf, seit: seit)
        async let g = HealthStatistik.neueGewichte(anker: ankerGewicht, seit: seit)
        let (laeufe, gewichte) = await (l, g)
        guard let laeufe, let gewichte else { return }

        var s = stand
        s.uebernehmen(laeufe: laeufe.neu, geloescht: laeufe.geloescht, anker: laeufe.anker, seit: seit)
        s.uebernehmen(gewichte: gewichte.neu, geloescht: gewichte.geloescht, anker: gewichte.anker, seit: seit)
        s.aktualisiert = jetzt
        setzen(s)

        let offen = s.offeneDetails
        for von in stride(from: 0, to: offen.count, by: 10) {
            let d = await HealthStatistik.details(ids: Array(offen[von..<min(von + 10, offen.count)]))
            if d.isEmpty { break }
            s = stand
            s.uebernehmen(details: d)
            setzen(s)
        }
    }

    private func setzen(_ neu: StatHealthStand) {
        guard neu != stand else { return }
        stand = neu
        neu.speichern(nach: datei)
        beobachter = beobachter.filter { $0(neu) }
    }
}
