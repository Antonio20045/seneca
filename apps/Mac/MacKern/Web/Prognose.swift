import Foundation

enum Prognose {
    static let tag: Double = 86_400_000
    static let fensterTage = 14
    static let kurzTage = 7
    static let minErledigt = 3

    struct Karte: Equatable {
        var status: String
        var completedAt: Double?
        init(status: String, completedAt: Double? = nil) { self.status = status; self.completedAt = completedAt }
        init(_ c: OvKarte) { status = c.status; completedAt = c.completedAt }
    }

    enum Urteil: String { case bequem, knapp, passtNicht = "passt-nicht", ohneFrist = "ohne-frist" }
    enum Zustand: String { case keineAufgaben = "keine-aufgaben", fertig, nichtBerechenbar = "nicht-berechenbar", berechnet }

    struct Punkt: Equatable { var tag: Double; var fertig: Int }

    struct Ergebnis: Equatable {
        var zustand: Zustand
        var gesamt: Int
        var fertig: Int
        var offen: Int
        var erledigt14: Int
        var erledigt7: Int
        var aktiveTage: Int
        var ohneZeit: Int
        var schuebe: Bool
        var tempo: Double?
        var tempo7: Double?
        var tage: Int?
        var fertigAm: Double?
        var fruehestens: Double?
        var frist: Double?
        var urteil: Urteil?
        var tageNachFrist: Int?
        var grund: String?
        var reihe: [Punkt]
        var heute: Double
        var start: Double
    }

    static func berechne(_ karten: [Karte], jetzt: Double, frist: Double? = nil) -> Ergebnis {
        let heute = Menschlich.tagStart(jetzt)
        let start = Menschlich.addTage(heute, -(fensterTage - 1))
        let startKurz = Menschlich.addTage(heute, -(kurzTage - 1))
        let fertige = karten.filter { $0.status == "done" }
        let offen = karten.count - fertige.count
        let zeiten = fertige.compactMap { $0.completedAt }.filter { $0.isFinite }
        let ohneZeit = fertige.count - zeiten.count
        let morgen = Menschlich.addTage(heute, 1)
        let imFenster = zeiten.filter { $0 >= start && $0 < morgen }
        let erledigt14 = imFenster.count
        let erledigt7 = imFenster.filter { $0 >= startKurz }.count
        let aktiveTage = Set(imFenster.map { Menschlich.tagStart($0) }).count
        let schuebe = erledigt14 >= 4 && aktiveTage <= max(2, fensterTage / 4)
        var reihe: [Punkt] = []
        for i in 0..<fensterTage {
            let t = Menschlich.addTage(start, i)
            let bis = Menschlich.addTage(t, 1)
            reihe.append(Punkt(tag: t, fertig: ohneZeit + zeiten.filter { $0 < bis }.count))
        }
        var e = Ergebnis(zustand: .berechnet, gesamt: karten.count, fertig: fertige.count, offen: offen, erledigt14: erledigt14, erledigt7: erledigt7,
                         aktiveTage: aktiveTage, ohneZeit: ohneZeit, schuebe: schuebe, frist: (frist?.isFinite ?? false) ? frist : nil,
                         reihe: reihe, heute: heute, start: start)
        if karten.isEmpty { e.zustand = .keineAufgaben; e.grund = "Noch keine Aufgaben."; return e }
        if offen == 0 { e.zustand = .fertig; return e }
        if erledigt14 < minErledigt {
            e.zustand = .nichtBerechenbar
            e.grund = erledigt14 == 0 ? "In den letzten \(fensterTage) Tagen wurde nichts erledigt."
                : "In den letzten \(fensterTage) Tagen \(erledigt14 == 1 ? "wurde nur eine Aufgabe" : "wurden nur \(erledigt14) Aufgaben") erledigt, das reicht nicht für eine Rechnung."
            return e
        }
        let tempo = Double(erledigt14) / Double(fensterTage)
        let tempo7 = Double(erledigt7) / Double(kurzTage)
        func bis(_ t: Double) -> Double { Menschlich.addTage(heute, Int((Double(offen) / t).rounded(.up))) }
        let fertigAm = bis(tempo)
        let fruehestens = bis(max(tempo, tempo7))
        e.urteil = .ohneFrist
        if let f = e.frist {
            e.tageNachFrist = Int(((fertigAm - f) / tag).rounded())
            e.urteil = fertigAm <= f ? .bequem : fruehestens <= f ? .knapp : .passtNicht
        }
        e.tempo = tempo; e.tempo7 = tempo7
        e.tage = Int((Double(offen) / tempo).rounded(.up))
        e.fertigAm = fertigAm; e.fruehestens = fruehestens
        return e
    }

    static func zahl(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.maximumFractionDigits = 1
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    private static func aufg(_ n: Int) -> String { "\(n) \(n == 1 ? "Aufgabe" : "Aufgaben")" }

    static func satz(_ p: Ergebnis) -> String {
        let stand = "\(p.fertig) von \(p.gesamt) erledigt."
        switch p.zustand {
        case .keineAufgaben: return "Noch keine Aufgaben, also gibt es nichts zu berechnen."
        case .fertig: return "Alle \(aufg(p.gesamt)) sind erledigt."
        case .nichtBerechenbar:
            let g = p.grund ?? ""
            return "\(stand) Noch nicht berechenbar: \(g.prefix(1).lowercased() + g.dropFirst())"
        case .berechnet: break
        }
        var teile = [stand, "In den letzten \(fensterTage) Tagen waren es \(p.erledigt14), das sind \(zahl(p.tempo ?? 0)) pro Tag."]
        let fertig = Menschlich.datumKurz(p.fertigAm ?? 0)
        if p.urteil == .ohneFrist { teile.append("So wäre alles um den \(fertig) fertig. Eine Frist gibt es nicht.") }
        else {
            let frist = Menschlich.datumKurz(p.frist ?? 0)
            let n = abs(p.tageNachFrist ?? 0)
            let tage = "\(n) \(n == 1 ? "Tag" : "Tage")"
            switch p.urteil {
            case .bequem: teile.append("So wäre alles um den \(fertig) fertig, \(n == 0 ? "genau zur Frist" : "\(tage) vor der Frist") (\(frist)).")
            case .knapp: teile.append("So wäre alles um den \(fertig) fertig, \(tage) nach der Frist (\(frist)). Mit dem Tempo der letzten \(kurzTage) Tage (\(zahl(p.tempo7 ?? 0)) pro Tag) ginge es bis \(Menschlich.datumKurz(p.fruehestens ?? 0)), also knapp.")
            default: teile.append("So wäre alles erst um den \(fertig) fertig, \(tage) nach der Frist (\(frist)). Auch das schnellere Tempo reicht nicht.")
            }
        }
        if p.schuebe { teile.append("Die Arbeit kam in Schüben: \(p.erledigt14) Aufgaben an nur \(p.aktiveTage) \(p.aktiveTage == 1 ? "Tag" : "Tagen"). Das Datum ist deshalb grob.") }
        return teile.joined(separator: " ")
    }
}
