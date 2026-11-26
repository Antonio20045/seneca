import Foundation

struct Meldung: Equatable, Codable, Identifiable {
    var id: String
    var zeit: Date? = nil
    var titel: String
    var text: String
    var knoepfe: [String] = []
    var dringend = false
}

struct MeldungAntwort: Equatable, Codable {
    var id: String
    var wahl: String
}

enum MeldungLogik {
    static let kategorieVorsatz = "seneca.meldung."
    static let aktionVorsatz = "wahl:"
    static let ganzLesen = "Ganz lesen"
    static let hoechstensGemerkt = 200

    static func lesen(_ json: [String: Any]) -> [Meldung] {
        guard json["ok"] as? Bool != false else { return [] }
        return (json["meldungen"] as? [[String: Any]] ?? []).compactMap { m in
            guard let id = m["id"] as? String, !id.isEmpty else { return nil }
            let titel = (m["titel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = (m["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titel.isEmpty || !text.isEmpty else { return nil }
            let knoepfe = (m["knoepfe"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return Meldung(id: id, zeit: TageslaufZeit.lesen(m["zeit"]), titel: titel.isEmpty ? "Seneca" : titel, text: text,
                           knoepfe: Array(knoepfe.prefix(4)), dringend: m["dringend"] as? Bool ?? false)
        }
    }

    static func neue(_ alle: [Meldung], gezeigt: [String]) -> [Meldung] {
        let schon = Set(gezeigt)
        var gesehen = Set<String>()
        return alle.filter { !schon.contains($0.id) && gesehen.insert($0.id).inserted }
    }

    static func merke(_ gezeigt: [String], _ id: String) -> [String] {
        Array((gezeigt.filter { $0 != id } + [id]).suffix(hoechstensGemerkt))
    }

    static func kategorie(_ knoepfe: [String]) -> String {
        var h: UInt64 = 1469598103934665603
        for b in knoepfe.joined(separator: "\u{1F}").utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return kategorieVorsatz + String(h, radix: 36)
    }

    static func aktion(_ nr: Int) -> String { aktionVorsatz + String(nr) }

    static func wahl(aktion: String, knoepfe: [String]) -> String? {
        guard aktion.hasPrefix(aktionVorsatz), let nr = Int(aktion.dropFirst(aktionVorsatz.count)), knoepfe.indices.contains(nr) else { return nil }
        return knoepfe[nr]
    }

    static func kurz(_ text: String, _ laenge: Int = 300) -> String { Tagesablauf.kurz(text, laenge) }
}
