import Foundation

struct FuerDichZeile: Equatable, Codable, Identifiable {
    enum Art: String, Codable, CaseIterable { case antwort, rueckfrage, entscheidung, abnahme, aufgabe }
    var id: String
    var art: Art
    var satz: String
    var wortlaut: String
    var von = ""
    var bereich = ""
    var seit: Date? = nil
    var beleg: [String] = []
    var geprueft: Bool? = nil
    var ergebnis = ""
    var worum = ""
    var empfehlung = ""
    var empfohlen: String? = nil
    var frist = ""
    var ueberfaellig = false
    var quelle = ""
}

struct LaeuftZeile: Equatable, Codable, Identifiable {
    enum Art: String, Codable, CaseIterable { case auftrag, arbeit, pruefung }
    var id: String
    var art: Art
    var satz: String
    var wortlaut: String
    var von = ""
    var bereich = ""
    var seit: Date? = nil
    var stand = ""
    var runde: Int? = nil
    var zuletzt: Date? = nil
}

struct Frage: Equatable, Identifiable {
    var id: String
    var satz: String
    var wortlaut: String
    var wer = ""
    var karte: String? = nil
    var seit: Date? = nil
    var worum = ""
}

enum FuerDich {
    static let haltbar: TimeInterval = 15 * 60

    private static func text(_ v: Any?) -> String { (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    static func zeilen(_ roh: Any?, wartende: [[String: Any]] = []) -> [FuerDichZeile]? {
        guard let liste = roh as? [[String: Any]] else { return nil }
        return liste.compactMap { z in
            let id = text(z["id"]), wortlaut = text(z["wortlaut"])
            let satz = text(z["satz"]).isEmpty ? wortlaut : text(z["satz"])
            guard !id.isEmpty, let art = FuerDichZeile.Art(rawValue: text(z["art"])), !satz.isEmpty || art == .antwort else { return nil }
            var f = FuerDichZeile(id: id, art: art, satz: satz, wortlaut: wortlaut.isEmpty ? satz : wortlaut, von: text(z["von"]), bereich: text(z["bereich"]),
                                  seit: TageslaufZeit.lesen(z["seit"]))
            f.beleg = (z["beleg"] as? [String] ?? []).filter { !$0.isEmpty }
            f.geprueft = z["geprueft"] as? Bool
            f.ergebnis = text(z["ergebnis"])
            f.worum = text(z["worum"])
            if let e = z["empfehlung"] as? [String: Any] {
                f.empfehlung = text(e["text"])
                f.empfohlen = text(e["key"]).isEmpty ? nil : text(e["key"])
            } else { f.empfehlung = text(z["empfehlung"]) }
            f.frist = text(z["frist"])
            f.ueberfaellig = z["ueberfaellig"] as? Bool ?? false
            if art == .antwort {
                f.quelle = text(wartende.first { text($0["chat"]) == f.bereich && (f.von.isEmpty || text($0["wer"]) == f.von) }?["quelle"]).lowercased()
            }
            return f
        }
    }

    static func laeuft(_ roh: Any?) -> [LaeuftZeile]? {
        guard let liste = roh as? [[String: Any]] else { return nil }
        return liste.compactMap { z in
            let id = text(z["id"]), wortlaut = text(z["wortlaut"])
            let satz = text(z["satz"]).isEmpty ? wortlaut : text(z["satz"])
            guard !id.isEmpty, let art = LaeuftZeile.Art(rawValue: text(z["art"])), !satz.isEmpty else { return nil }
            return LaeuftZeile(id: id, art: art, satz: satz, wortlaut: wortlaut.isEmpty ? satz : wortlaut, von: text(z["von"]), bereich: text(z["bereich"]),
                               seit: TageslaufZeit.lesen(z["seit"]), stand: text(z["stand"]), runde: (z["runde"] as? NSNumber)?.intValue, zuletzt: TageslaufZeit.lesen(z["zuletzt"]))
        }
    }

    static func gilt(stand: Date?, jetzt: Date, versucht: Bool) -> Bool {
        guard let stand else { return false }
        return !versucht || jetzt.timeIntervalSince(stand) <= haltbar
    }

    static func braucht(_ zeilen: [FuerDichZeile], einzelheiten: [Entscheidung] = [], erledigt: Set<String> = []) -> [BrauchtDich] {
        let je = Dictionary(einzelheiten.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let dinge: [BrauchtDich] = zeilen.compactMap { z in
            switch z.art {
            case .antwort: return .person(AblaufWartet(wer: z.von.isEmpty ? "Jemand" : z.von, seit: z.seit, chat: z.bereich, worum: z.satz, quelle: z.quelle))
            case .rueckfrage: return .frage(Frage(id: z.id, satz: z.satz, wortlaut: z.wortlaut, wer: z.von, karte: z.id, seit: z.seit, worum: z.worum))
            case .entscheidung: return .entscheidung(entscheidung(z, je[z.id]), klartext: z.satz)
            case .abnahme: return .abnahme(karte: z.id, satz: z.satz)
            case .aufgabe: return nil
            }
        }
        return dinge.filter { !erledigt.contains($0.id) }
    }

    static func entscheidung(_ z: FuerDichZeile, _ e: Entscheidung?) -> Entscheidung {
        var d = e ?? Entscheidung(id: z.id, frage: z.wortlaut)
        if d.bereich.isEmpty { d.bereich = z.bereich }
        if d.empfehlung.isEmpty { d.empfehlung = z.empfehlung }
        if d.empfohlen == nil { d.empfohlen = z.empfohlen }
        return d
    }

    static func wahlFehlt(_ e: Entscheidung) -> Bool { e.optionen.isEmpty && e.empfohlen != nil }

    static func aufgaben(_ zeilen: [FuerDichZeile]) -> [FuerDichZeile] { zeilen.filter { $0.art == .aufgabe } }

    static func anzahl(_ zeilen: [FuerDichZeile]) -> [FuerDichZeile.Art: Int] {
        Dictionary(grouping: zeilen, by: \.art).mapValues(\.count)
    }

    static func kopfzeile(_ l: LaeuftZeile) -> String {
        guard l.art == .pruefung else { return l.von }
        return l.von.isEmpty ? "Liegt beim Prüfer" : "\(l.von) · liegt beim Prüfer"
    }

    static func istJaNein(_ frage: String) -> Bool {
        let klein = frage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if klein.contains(" oder ") { return false }
        return !["welche", "was ", "wie ", "wann ", "wer ", "wo ", "warum ", "wieso ", "wohin ", "wozu ", "wie viel"].contains { klein.hasPrefix($0) }
    }
}
