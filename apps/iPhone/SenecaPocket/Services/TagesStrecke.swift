import Foundation

struct TagesStrecke: Equatable {
    enum Lage: Equatable { case war, laeuft, kommt }
    struct Block: Equatable, Identifiable {
        var id: String
        var x: Double
        var breite: Double
        var lage: Lage
        var training = false
        var leise = false
        var anteil: Double = 0
        var zeit: String
        var titel: String
    }
    struct Schild: Equatable, Identifiable {
        var id: String
        var x: Double
        var breite: Double
        var zeit: String
        var titel: String
        var hell: Bool
        var zeilen = 1
    }
    struct Zeichen: Equatable, Identifiable {
        var id: String
        var x: Double
        var symbol: String
        var war: Bool
        var name: String
    }
    struct Stueck: Equatable { var von: Double; var bis: Double }

    var breite: Double
    var bloecke: [Block] = []
    var schilder: [Schild] = []
    var zeichen: [Zeichen] = []
    var ausgelassen: [Stueck] = []
    var jetzt: Double = 0
    var jetztText = ""
    var tagX: Double? = nil
    var tagName = ""
    var ende: Double = 0
    var zeilen: Int { schilder.map(\.zeilen).max() ?? 1 }
    var leer: Bool { bloecke.isEmpty }
}

extension Tagesablauf {
    static let schildEinzeilig = 118.0
    static let schildHoechstens = 168.0
    static let schildLuft = 12.0

    static func schildMass(_ text: String, messen: (String) -> Double) -> (breite: Double, zeilen: Int) {
        let roh = messen(text)
        if roh <= schildEinzeilig { return (roh + 2, 1) }
        let worte = text.split(separator: " ").map(String.init)
        var beste = Double.infinity
        for k in 1..<max(2, worte.count) where worte.count > 1 {
            beste = min(beste, max(messen(worte[..<k].joined(separator: " ")), messen(worte[k...].joined(separator: " "))))
        }
        if beste <= schildHoechstens { return (beste + 3, 2) }
        return (schildHoechstens + 2, max(3, Int((roh * 1.15 / schildHoechstens).rounded(.up))))
    }

    static func strecke(_ punkte: [AblaufPunkt], jetzt: Date, breite: Double, schilder hoechstens: Int = 3,
                        messen: (String) -> Double = { Double($0.count) * 7.0 }, _ cal: Calendar = .current) -> TagesStrecke {
        var leer = TagesStrecke(breite: breite)
        leer.jetztText = hm(jetzt, cal)
        let tag0 = cal.startOfDay(for: jetzt)
        guard breite > 60, let tag1 = cal.date(byAdding: .day, value: 1, to: tag0), let tag2 = cal.date(byAdding: .day, value: 2, to: tag0) else { return leer }
        func schluss(_ p: AblaufPunkt) -> Date { max(p.zeit.addingTimeInterval(300), p.ende ?? p.zeit.addingTimeInterval(1800)) }
        let alle = punkte.filter { !$0.ganztags && ($0.istTermin || $0.art == "training") }.sorted { $0.zeit < $1.zeit }
        let heute = alle.filter { $0.zeit >= tag0 && $0.zeit < tag1 }
        var vorbei = heute.filter { schluss($0) <= jetzt }
        let offen = heute.filter { schluss($0) > jetzt }
        var morgen: [AblaufPunkt] = []
        if offen.isEmpty || cal.component(.hour, from: jetzt) >= 18 {
            let m = alle.filter { $0.zeit >= tag1 && $0.zeit < tag2 }
            morgen = Array(m.prefix(5))
            if !morgen.contains(where: { !$0.routine }), let erst = m.first(where: { !$0.routine }) { morgen.append(erst) }
        }
        vorbei = Array(vorbei.suffix(6))
        guard !(vorbei + offen + morgen).isEmpty else { return leer }

        let kommend = offen + morgen
        var wahl: [String] = kommend.filter { !$0.routine && $0.zeit <= jetzt }.map(\.id)
        for p in kommend where !p.routine && p.zeit > jetzt && wahl.count < hoechstens { wahl.append(p.id) }
        let leise = kommend.filter { $0.routine && $0.zeit > jetzt }.map(\.id)
        if wahl.count < 2, let erste = leise.first { wahl.append(erste) }
        if wahl.count < hoechstens, let l = vorbei.last(where: { !$0.routine }) { wahl.append(l.id) }
        if wahl.count < 2, leise.count > 1 { wahl.append(leise[1]) }

        while true {
            let da = vorbei + offen + morgen
            if let s = setze(da, schilder: wahl, mitternacht: morgen.isEmpty ? nil : tag1, punkte: punkte, jetzt: jetzt, breite: breite, messen: messen, cal) { return s }
            if wahl.count > 2 { wahl.removeLast() }
            else if vorbei.count > 2 { let weg = vorbei.removeFirst(); wahl.removeAll { $0 == weg.id } }
            else if wahl.count > 1 { wahl.removeLast() }
            else if !vorbei.isEmpty { let weg = vorbei.removeFirst(); wahl.removeAll { $0 == weg.id } }
            else if morgen.count > 1 { morgen.removeLast() }
            else if !wahl.isEmpty { wahl.removeLast() }
            else { return leer }
        }
    }

    private static func setze(_ da: [AblaufPunkt], schilder wahl: [String], mitternacht: Date?, punkte: [AblaufPunkt], jetzt: Date, breite W: Double,
                              messen: (String) -> Double, _ cal: Calendar) -> TagesStrecke? {
        var von: [Date] = [], bis: [Date] = []
        for p in da {
            let a = max(p.zeit, bis.last ?? .distantPast)
            von.append(a)
            bis.append(max(a.addingTimeInterval(300), p.ende ?? p.zeit.addingTimeInterval(1800)))
        }
        var zeiten = Set(von + bis)
        zeiten.insert(jetzt)
        if let mitternacht { zeiten.insert(mitternacht) }
        let t = zeiten.sorted()
        guard t.count >= 2 else { return nil }
        let orte = punkte.filter { $0.art == "ort_ankunft" && !$0.ganztags }.map(\.zeit)
        let n = t.count - 1
        let jeStunde = W / 14
        var w = [Double](repeating: 0, count: n), mind = [Double](repeating: 0, count: n), luecke = [Bool](repeating: false, count: n)
        var lang = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let dauer = t[i + 1].timeIntervalSince(t[i]) / 3600
            if let k = da.indices.first(where: { von[$0] <= t[i] && t[i + 1] <= bis[$0] }) {
                let ganz = max(1.0 / 60, bis[k].timeIntervalSince(von[k]) / 3600), anteil = dauer / ganz
                let training = da[k].art == "training"
                w[i] = min(76, max(da[k].routine ? 10 : (training ? 24 : 18), ganz * jeStunde)) * anteil
                mind[i] = (da[k].routine ? 8 : (training ? 22 : 12)) * anteil
            } else {
                luecke[i] = true
                lang[i] = dauer > 2.5
                w[i] = min(30, max(7, dauer * jeStunde))
                mind[i] = 5
                if orte.contains(where: { $0 > t[i] && $0 < t[i + 1] }) { w[i] = max(w[i], 30); mind[i] = 26 }
            }
        }
        let natur = w.reduce(0, +)
        let wunsch = natur < W ? w.map { $0 * min(1.7, W / natur) } : w
        w = mind

        func index(_ d: Date) -> Int { t.firstIndex(of: d) ?? 0 }
        func x(_ i: Int) -> Double { w.prefix(i).reduce(0, +) }
        let beschriftet = da.indices.filter { wahl.contains(da[$0].id) }
        let texte = Dictionary(uniqueKeysWithValues: beschriftet.map { ($0, hm(da[$0].zeit, cal) + " " + da[$0].titel) })
        let masse = texte.mapValues { schildMass($0, messen: messen) }
        let breiten = masse.mapValues(\.breite)
        let jetztHalb = messen(hm(jetzt, cal)) / 2 + 3
        let tagName: String = {
            guard let mitternacht else { return "" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE"); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "EEEE"
            return f.string(from: mitternacht)
        }()
        var schwanz = 0.0
        func zwinge() {
            for (a, b) in zip(beschriftet, beschriftet.dropFirst()) {
                let ia = index(von[a]), ib = index(von[b])
                let fehlt = (breiten[a] ?? 0) + schildLuft - (x(ib) - x(ia))
                if fehlt > 0, ib > 0 { w[ib - 1] += fehlt }
            }
            if let mitternacht, jetzt < mitternacht {
                let im = index(mitternacht), ij = index(jetzt)
                let fehlt = jetztHalb + 2 - (x(im) - x(ij))
                if fehlt > 0, im > 0 { w[im - 1] += fehlt }
            }
            schwanz = 0
            let gesamt = w.reduce(0, +)
            if let l = beschriftet.last { schwanz = max(schwanz, x(index(von[l])) + (breiten[l] ?? 0) - gesamt) }
            if let mitternacht { schwanz = max(schwanz, x(index(mitternacht)) + 7 + messen(tagName) - gesamt) }
            schwanz = max(schwanz, x(index(jetzt)) + jetztHalb - gesamt)
        }
        zwinge()
        let noetig = w.reduce(0, +) + schwanz
        guard noetig <= W + 0.5 else { return nil }
        var uebrig = max(0, W - noetig)
        let wichtig = Set(beschriftet.flatMap { k in Array(index(von[k])..<index(bis[k])) })
        for runde in [true, false] {
            let offen = (0..<n).map { wichtig.contains($0) == runde ? max(0, wunsch[$0] - w[$0]) : 0 }, summe = offen.reduce(0, +)
            guard summe > 0 else { continue }
            let f = min(1, uebrig / summe)
            for i in 0..<n { w[i] += offen[i] * f }
            uebrig -= summe * f
        }
        if uebrig > 1 {
            let bloecke = (0..<n).filter { !luecke[$0] }.reduce(0) { $0 + w[$1] }
            let f = min(0.66, uebrig / max(1, bloecke))
            for i in 0..<n where !luecke[i] { w[i] *= 1 + f }
        }
        zwinge()
        for a in beschriftet {
            let ia = index(von[a]), ie = index(bis[a])
            guard ie < n, luecke[ie] else { continue }
            let teile = Array(ia..<ie), ist = teile.reduce(0) { $0 + w[$1] }
            let mehr = min(84 - ist, w[ie] - 12)
            guard ist > 0, mehr > 1 else { continue }
            for i in teile { w[i] *= (ist + mehr) / ist }
            w[ie] -= mehr
        }

        var s = TagesStrecke(breite: W)
        s.jetztText = hm(jetzt, cal)
        s.jetzt = x(index(jetzt))
        s.ende = min(W, w.reduce(0, +) + schwanz)
        if let mitternacht { s.tagX = x(index(mitternacht)); s.tagName = tagName }
        for i in 0..<n where luecke[i] && lang[i] { s.ausgelassen.append(.init(von: x(i), bis: x(i + 1))) }
        for (k, p) in da.enumerated() {
            let a = x(index(von[k])), b = x(index(bis[k]))
            let lage: TagesStrecke.Lage = bis[k] <= jetzt ? .war : (von[k] <= jetzt ? .laeuft : .kommt)
            let anteil = lage == .laeuft ? jetzt.timeIntervalSince(von[k]) / max(60, bis[k].timeIntervalSince(von[k])) : 0
            s.bloecke.append(.init(id: p.id, x: a, breite: max(3, b - a), lage: lage, training: p.art == "training", leise: p.routine,
                                   anteil: min(1, max(0, anteil)), zeit: hm(p.zeit, cal), titel: p.titel))
            if let breit = breiten[k] {
                s.schilder.append(.init(id: p.id, x: a, breite: breit, zeit: hm(p.zeit, cal), titel: p.titel, hell: lage != .war, zeilen: masse[k]?.zeilen ?? 1))
            }
        }
        func ort(_ d: Date) -> Double? {
            guard let erste = t.first, let letzte = t.last, d >= erste, d <= letzte else { return nil }
            let i = min(n - 1, max(0, (t.firstIndex { $0 > d } ?? n) - 1))
            if luecke[i] { return x(i) + w[i] / 2 }
            let teil = t[i + 1].timeIntervalSince(t[i])
            return x(i) + (teil > 0 ? d.timeIntervalSince(t[i]) / teil : 0) * w[i]
        }
        for p in punkte where p.art == "ort_ankunft" && !p.ganztags {
            guard let px = ort(p.zeit) else { continue }
            let name = p.titel.lowercased()
            let symbol = name.contains("hause") ? "house.fill" : (name.contains("campus") || name.contains("büro") || name.contains("vodafone") ? "building.2.fill" : "mappin")
            s.zeichen.append(.init(id: p.id, x: px, symbol: symbol, war: p.zeit <= jetzt, name: p.titel))
        }
        return s
    }
}
