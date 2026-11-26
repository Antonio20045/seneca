import Foundation

enum StatDemo {
    static func daten(jetzt: Date) -> (daten: StatDaten, laeufe: [StatLauf], gewicht: [String: Double]) {
        let h = StatKalender.schluessel(jetzt)
        func tag(_ zurueck: Int) -> String { StatKalender.plus(h, tage: -zurueck) }
        func uhr(_ tag: String, _ std: Int, _ min: Int) -> Date {
            StatKalender.cal.date(bySettingHour: std, minute: min, second: 0, of: StatKalender.tag(tag)!) ?? jetzt
        }
        var d = StatDaten()

        var laeufe: [StatLauf] = []
        for i in 0..<150 where (i * 7 + 3) % 10 < 6 {
            let km = 4.6 + Double((i * 13) % 36) / 10
            let basis = 352 - Double(150 - i) * 0.12
            var zeiten: [StatKm] = []
            var rest = km
            var k = 1
            while rest >= 1 {
                zeiten.append(StatKm(label: "\(k)", sekunden: basis + 9 - Double(k) * 2.2 + Double((i * k) % 5) - 2, meter: 1000))
                rest -= 1; k += 1
            }
            if rest >= 0.1 { zeiten.append(StatKm(label: ",\(Int((rest * 10).rounded()))", sekunden: (basis - 14) * rest, meter: rest * 1000)) }
            let dauer = zeiten.reduce(0) { $0 + $1.sekunden }
            laeufe.append(StatLauf(id: "demo-lauf-\(i)", start: uhr(tag(i), 17, 12), dauer: dauer, meter: km * 1000, kcal: (km * 61).rounded(),
                                   aufstieg: Double((i * 5) % 60 + 12), pulsMittel: nil, pulsMax: nil, quelle: "Nike Run Club", kmZeiten: zeiten))
        }

        d.buecher = [StatBuch(id: "demo-buch-1", titel: "Atomic Habits", autor: "James Clear", begonnen: tag(48), beendet: tag(13)),
                     StatBuch(id: "demo-buch-2", titel: "Gandhi", autor: nil, begonnen: tag(12))]
        for i in 0..<48 where i % 5 != 2 {
            let buch = i > 12 ? "demo-buch-1" : "demo-buch-2"
            let n = i > 12 ? 25 + (i * 11) % 25 : 30 + (i * 7) % 35
            d.eintraege.append(StatEintrag(id: "demo-lesen-\(i)", thema: "lesen", wert: Double(n), datum: tag(i), buch: buch, erfasst: uhr(tag(i), 21, 30)))
        }

        let uebungen = [("Bankdrücken", 50.0, 2.5), ("Kniebeuge", 70.0, 5.0), ("Klimmzüge", 0.0, 0.0), ("Schulterdrücken", 30.0, 2.5)]
        d.uebungen = uebungen.map { StatUebung(id: $0.0.lowercased().replacingOccurrences(of: "ü", with: "ue"), name: $0.0) }
        var tr = 1
        var einheit = 0
        while tr < 100 {
            for (u, def) in uebungen.enumerated() {
                let fortschritt = Double((100 - tr) / 12)
                let kg = def.1 > 0 ? def.1 + fortschritt * def.2 : 0
                for s in 0..<(u == 2 ? 3 : 4) {
                    let wdh = u == 2 ? 10 - s : (u == 1 ? 5 : 8 - (s > 1 ? 1 : 0))
                    d.saetze.append(StatSatz(id: "demo-satz-\(tr)-\(u)-\(s)", uebung: d.uebungen[u].id, kg: kg, wdh: wdh, datum: tag(tr),
                                             erfasst: StatKalender.cal.date(byAdding: .minute, value: 18 + u * 12 + s * 3, to: uhr(tag(tr), 18, 0))))
                }
            }
            einheit += 1
            tr += einheit % 2 == 0 ? 4 : 3
        }

        var gewicht: [String: Double] = [:]
        for i in 0..<90 where i % 6 != 4 {
            gewicht[tag(i)] = ((81.3 + Double(i) * 0.02 + sin(Double(i) * 1.7) * 0.35) * 10).rounded() / 10
        }
        return (d, laeufe, gewicht)
    }
}
