import Foundation

struct StatKmSample: Equatable {
    var von: Date
    var bis: Date
    var meter: Double
}

struct StatKm: Equatable, Codable {
    var label: String
    var sekunden: Double
    var meter: Double
    var pace: Double { meter > 0 ? sekunden * 1000 / meter : 0 }
    var voll: Bool { meter >= 999.5 }
}

struct StatLauf: Equatable, Identifiable, Codable {
    var id: String
    var start: Date
    var dauer: Double
    var meter: Double
    var kcal: Double? = nil
    var aufstieg: Double? = nil
    var pulsMittel: Double? = nil
    var pulsMax: Double? = nil
    var quelle: String = ""
    var kmZeiten: [StatKm]? = nil

    var datum: String { StatKalender.schluessel(start) }
    var km: Double { meter / 1000 }
    var pace: Double { km > 0 ? dauer / km : 0 }
}

enum StatLaufRechnen {
    static func kmZeiten(_ samples: [StatKmSample]) -> [StatKm]? {
        let s = samples.filter { $0.meter > 0 && $0.bis >= $0.von }.sorted { $0.von < $1.von }
        guard s.count >= 2, let erster = s.first, let letzter = s.last else { return nil }
        let t0 = erster.von
        var ergebnis: [StatKm] = []
        var summe = 0.0
        var naechster = 1000.0
        var letzteMarke = 0.0
        for sample in s {
            let dauer = sample.bis.timeIntervalSince(sample.von)
            let startRel = sample.von.timeIntervalSince(t0)
            var verbraucht = 0.0
            while summe + (sample.meter - verbraucht) >= naechster - 1e-6 {
                verbraucht += naechster - summe
                let t = startRel + dauer * (verbraucht / sample.meter)
                ergebnis.append(StatKm(label: "\(ergebnis.count + 1)", sekunden: t - letzteMarke, meter: 1000))
                letzteMarke = t
                summe = naechster
                naechster += 1000
            }
            summe += sample.meter - verbraucht
        }
        let rest = summe - Double(ergebnis.count) * 1000
        if rest >= 100 {
            let ende = letzter.bis.timeIntervalSince(t0)
            let zehntel = min(9, Int((rest / 100).rounded()))
            ergebnis.append(StatKm(label: ",\(zehntel)", sekunden: max(1, ende - letzteMarke), meter: rest))
        }
        return ergebnis.isEmpty ? nil : ergebnis
    }

    static func schnellsterKm(_ laeufe: [StatLauf]) -> Double? {
        laeufe.compactMap { $0.kmZeiten?.filter(\.voll).map(\.sekunden).min() }.min()
    }

    static func schnellste5km(_ laeufe: [StatLauf]) -> (sekunden: Double, lauf: StatLauf)? {
        var beste: (Double, StatLauf)?
        for l in laeufe {
            let voll = (l.kmZeiten ?? []).filter(\.voll).map(\.sekunden)
            guard voll.count >= 5 else { continue }
            for i in 0...(voll.count - 5) {
                let s = voll[i..<(i + 5)].reduce(0, +)
                if beste == nil || s < beste!.0 { beste = (s, l) }
            }
        }
        return beste.map { ($0.0, $0.1) }
    }
}

enum StatGewichtRechnen {
    static let alpha = 0.1

    static func trend(_ werte: [String: Double]) -> [(tag: String, trend: Double)] {
        let tage = werte.keys.sorted()
        guard let erster = tage.first, let letzter = tage.last else { return [] }
        var ergebnis: [(String, Double)] = []
        var t = werte[erster]!
        var vorher = erster
        ergebnis.append((erster, t))
        for tag in tage.dropFirst() {
            let n = StatKalender.abstand(vorher, tag)
            let von = werte[vorher]!, bis = werte[tag]!
            for i in 1...max(1, n) {
                let m = von + (bis - von) * Double(i) / Double(n)
                t += alpha * (m - t)
                ergebnis.append((StatKalender.plus(vorher, tage: i), t))
            }
            vorher = tag
        }
        _ = letzter
        return ergebnis
    }

    static func tempo(_ trend: [Double]) -> Double? {
        let w = Array(trend.suffix(14))
        guard w.count >= 3 else { return nil }
        let n = Double(w.count)
        let xm = (n - 1) / 2
        let ym = w.reduce(0, +) / n
        var zaehler = 0.0, nenner = 0.0
        for (i, y) in w.enumerated() {
            zaehler += (Double(i) - xm) * (y - ym)
            nenner += (Double(i) - xm) * (Double(i) - xm)
        }
        return nenner > 0 ? zaehler / nenner * 7 : nil
    }
}

struct StatQuellen: Equatable {
    var daten: StatDaten
    var laeufe: [StatLauf] = []
    var gewichtHealth: [String: Double] = [:]
    var jetzt: Date

    var heute: String { StatKalender.schluessel(jetzt) }
}

struct StatTage {
    var km: [String: Double] = [:]
    var laeufe: [String: [StatLauf]] = [:]
    var lesezeit: [String: Int] = [:]
    var saetze: [String: [StatSatz]] = [:]
    var training: Set<String> = []
    var gewicht: [String: Double] = [:]
    var koerperHealth: [String: Double] = [:]
    var trend: [(tag: String, trend: Double)] = []
    var trendNach: [String: Double] = [:]

    init(_ q: StatQuellen) {
        for l in q.laeufe {
            km[l.datum, default: 0] += l.km
            laeufe[l.datum, default: []].append(l)
        }
        for e in q.daten.eintraege {
            switch e.thema {
            case "lesen" where e.istLesezeit: lesezeit[e.datum, default: 0] += Int(e.wert.rounded())
            case "krafttraining": training.insert(e.datum)
            case "abnehmen": gewicht[e.datum] = e.wert
            default: break
            }
        }
        for s in q.daten.saetze {
            saetze[s.datum, default: []].append(s)
            training.insert(s.datum)
        }
        koerperHealth = q.gewichtHealth
        for (tag, kg) in q.gewichtHealth { gewicht[tag] = kg }
        trend = StatGewichtRechnen.trend(gewicht)
        for t in trend { trendNach[t.tag] = t.trend }
    }

    func trendBis(_ tag: String) -> Double? {
        trend.last { $0.tag <= tag }?.trend
    }
    func tempoBis(_ tag: String) -> Double? {
        StatGewichtRechnen.tempo(trend.filter { $0.tag <= tag }.map(\.trend))
    }
    func summeKm(von: String, bis: String) -> Double { km.filter { $0.key >= von && $0.key <= bis }.values.reduce(0, +) }
    func summeLesezeit(von: String, bis: String) -> Int { lesezeit.filter { $0.key >= von && $0.key <= bis }.values.reduce(0, +) }
    func laeufeIm(von: String, bis: String) -> [StatLauf] {
        laeufe.filter { $0.key >= von && $0.key <= bis }.flatMap(\.value).sorted { $0.start < $1.start }
    }
    func trainingsTage(von: String, bis: String) -> [String] { training.filter { $0 >= von && $0 <= bis }.sorted() }
    func saetzeIm(von: String, bis: String) -> [StatSatz] {
        saetze.filter { $0.key >= von && $0.key <= bis }.flatMap(\.value).sorted { ($0.datum, $0.erfasst ?? .distantPast) < ($1.datum, $1.erfasst ?? .distantPast) }
    }
    static func volumen(_ s: [StatSatz], koerper: [String: Double] = [:]) -> Double { s.reduce(0) { $0 + StatKraft.bewegt($1, koerper: koerper) } }
}
