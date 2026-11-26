import Foundation

struct NachrichtVorschlag: Equatable, Identifiable {
    var id: String
    var art = ""
    var titel: String
    var wer = ""
    var chat = ""
    var zeit: Date?
    var zitat = ""
    var quelle = ""
    var sicherheit = ""
}

enum NachrichtVorschlaege {
    static let titel = "Vorschläge aus Nachrichten"

    static func lies(_ w: Any?, zeit: (Any?) -> Date?) -> [NachrichtVorschlag] {
        func text(_ v: Any?) -> String { (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return ((w as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { v in
            let id = text(v["id"]), titel = text(v["titel"])
            guard id.hasPrefix("vorschlag:"), !titel.isEmpty else { return nil }
            return NachrichtVorschlag(id: id, art: text(v["art"]), titel: titel, wer: text(v["wer"]), chat: text(v["chat"]), zeit: zeit(v["zeit"]),
                                      zitat: text(v["zitat"]), quelle: text(v["quelle"]), sicherheit: text(v["sicherheit"]))
        }
    }

    static func offen(_ alle: [NachrichtVorschlag], gesehen: [String: Double]) -> [NachrichtVorschlag] {
        alle.filter { gesehen[$0.id] == nil }
    }

    static func quelleName(_ q: String) -> String {
        switch q.lowercased() {
        case "whatsapp": "WhatsApp"
        case "imessage": "Nachrichten"
        case "mail": "Mail"
        default: q
        }
    }

    static func kopf(_ v: NachrichtVorschlag, jetzt: Date = Date(), kalender: Calendar = .current) -> String {
        [v.wer.isEmpty ? v.chat : v.wer, quelleName(v.quelle), v.zeit.map { ListenText.uhr($0, jetzt: jetzt, kalender: kalender) } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func kartenParameter(_ v: NachrichtVorschlag, jetzt: Date = Date(), kalender: Calendar = .current) -> [String: Any] {
        let woher = kopf(v, jetzt: jetzt, kalender: kalender)
        var notiz = "Vorschlag aus einer Nachricht" + (woher.isEmpty ? "" : " (" + woher + ")")
        if !v.zitat.isEmpty { notiz += ": „" + v.zitat + "“" }
        return ["title": v.titel, "status": "backlog", "labels": ["vorschlag"], "notes": notiz, "idempotencyKey": schluessel(v.id)]
    }

    static func schluessel(_ id: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "vorschlag-" + String(h, radix: 16)
    }
}
