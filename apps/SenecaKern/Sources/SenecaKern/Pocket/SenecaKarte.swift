import Foundation

struct SenecaKarte: Equatable {
    enum Ton: String, Equatable { case ok, mittel, hoch, warn, danger }
    struct Marke: Equatable { var text: String; var ton: Ton? }
    struct Zahl: Equatable { var label: String?; var wert: String; var detail: String?; var ton: Ton? }
    struct Fortschritt: Equatable { var anteil: Double; var wert: String; var text: String? }
    struct Punkt: Equatable { var label: String; var wert: Double }
    struct Diagramm: Equatable {
        enum Art: String, Equatable { case balken, linie }
        var art: Art
        var einheit: String?
        var punkte: [Punkt]
    }
    struct Listenpunkt: Equatable { var text: String; var ton: Ton?; var meta: String? }
    struct Aufgabe: Equatable { var text: String; var fertig: Bool; var wer: String?; var bis: String? }
    struct Tabelle: Equatable { var spalten: [String]; var zeilen: [[String]] }
    struct Aktion: Equatable { var label: String; var prompt: String }

    var titel: String?
    var marke: Marke?
    var zahlen: [Zahl] = []
    var fortschritt: Fortschritt?
    var diagramm: Diagramm?
    var punkte: [Listenpunkt] = []
    var aufgaben: [Aufgabe] = []
    var tabelle: Tabelle?
    var text: String?
    var bericht: String?
    var aktionen: [Aktion] = []

    static func parse(_ json: String) -> SenecaKarte? {
        let roh = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard roh.hasPrefix("{"), let data = roh.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var k = SenecaKarte()
        k.titel = string(o["titel"])
        if let m = o["marke"] as? [String: Any], let t = string(m["text"]) { k.marke = Marke(text: t, ton: ton(m["ton"])) }
        k.zahlen = (o["zahlen"] as? [Any] ?? []).compactMap { e in
            guard let z = e as? [String: Any], let w = string(z["wert"]) else { return nil }
            return Zahl(label: string(z["label"]), wert: w, detail: string(z["detail"]), ton: ton(z["ton"]))
        }
        if let f = o["fortschritt"] as? [String: Any], let w = zahl(f["wert"]) {
            let von = zahl(f["von"]) ?? 0
            let anteil = min(1, max(0, von > 0 ? w / von : (w <= 1 ? w : w / 100)))
            k.fortschritt = Fortschritt(anteil: anteil, wert: von > 0 ? "\(zahlText(w)) von \(zahlText(von))" : "\(Int((anteil * 100).rounded())) %", text: string(f["text"]))
        }
        if let d = o["diagramm"] as? [String: Any] {
            let punkte = (d["punkte"] as? [Any] ?? []).compactMap { e -> Punkt? in
                guard let p = e as? [String: Any], let w = zahl(p["wert"]) else { return nil }
                return Punkt(label: string(p["label"]) ?? "", wert: w)
            }
            if !punkte.isEmpty {
                k.diagramm = Diagramm(art: (string(d["art"])?.lowercased()).flatMap(Diagramm.Art.init(rawValue:)) ?? .balken, einheit: string(d["einheit"]), punkte: punkte)
            }
        }
        k.punkte = (o["punkte"] as? [Any] ?? []).compactMap { e in
            if let s = e as? String, let t = string(s) { return Listenpunkt(text: t, ton: nil, meta: nil) }
            guard let p = e as? [String: Any], let t = string(p["text"]) else { return nil }
            return Listenpunkt(text: t, ton: ton(p["ton"]), meta: string(p["meta"]))
        }
        k.aufgaben = (o["aufgaben"] as? [Any] ?? []).compactMap { e in
            guard let a = e as? [String: Any], let t = string(a["text"]) else { return nil }
            return Aufgabe(text: t, fertig: a["fertig"] as? Bool ?? false, wer: string(a["wer"]), bis: string(a["bis"]))
        }
        if let t = o["tabelle"] as? [String: Any] {
            let zeilen = (t["zeilen"] as? [Any] ?? []).compactMap { z -> [String]? in
                guard let zelle = z as? [Any] else { return nil }
                return zelle.map { string($0) ?? "" }
            }
            if !zeilen.isEmpty { k.tabelle = Tabelle(spalten: (t["spalten"] as? [Any] ?? []).map { string($0) ?? "" }, zeilen: zeilen) }
        }
        k.text = string(o["text"])
        k.bericht = string(o["bericht"])
        k.aktionen = (o["aktionen"] as? [Any] ?? []).compactMap { e in
            guard let a = e as? [String: Any], let l = string(a["label"]), let p = string(a["prompt"]) else { return nil }
            return Aktion(label: l, prompt: p)
        }
        return k.istLeer ? nil : k
    }

    var istLeer: Bool {
        titel == nil && marke == nil && zahlen.isEmpty && fortschritt == nil && diagramm == nil && punkte.isEmpty
            && aufgaben.isEmpty && tabelle == nil && text == nil && bericht == nil && aktionen.isEmpty
    }

    var kurz: String? { titel ?? text ?? punkte.first?.text ?? aufgaben.first?.text }

    private static func string(_ v: Any?) -> String? {
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return zahlText(n.doubleValue) }
        return nil
    }
    private static func zahl(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    private static func ton(_ v: Any?) -> Ton? { (v as? String).flatMap { Ton(rawValue: $0.lowercased()) } }
    static func zahlText(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE"))) }
}
