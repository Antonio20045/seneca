import Foundation

enum Plan {
    struct Teil: Equatable {
        enum Zustand: String { case unbekannt, wirdGeklaert = "wird-geklaert", klar, fertig }
        var name: String
        var zustand: Zustand
        var wer: String?
        var fertigWenn: String?
        var zustandText: String {
            switch zustand {
            case .unbekannt: return "noch nicht begonnen"
            case .wirdGeklaert: return "wird geklärt"
            case .klar: return "klar, wird erledigt"
            case .fertig: return "fertig"
            }
        }
    }

    enum Risiko: String {
        case bequem, knapp, passtNicht = "passt-nicht"
        var text: String { self == .passtNicht ? "passt nicht" : rawValue }
    }

    enum Freigabe: String { case offen, erteilt }

    struct Inhalt: Equatable {
        var ziel: String?
        var fertig: String?
        var frist: String?
        var budget: String?
        var teile: [Teil] = []
        var offen: [String] = []
        var stand: String?
        var risiko: Risiko?
        var naechster: String?
        var freigabe: Freigabe?
    }

    struct Kurz: Equatable {
        var ziel: String?
        var frist: String?
        var risiko: Risiko?
        var naechster: String?
    }

    private static func txt(_ v: Any?, _ max: Int = 400) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(max))
    }

    static func aus(_ md: String) -> Inhalt? {
        guard let m = Muster.erster(md, #"```seneca-plan\s*\n([\s\S]*?)```"#), let roh = m[1],
              let daten = roh.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] else { return nil }
        var plan = Inhalt()
        plan.teile = (j["teile"] as? [Any] ?? []).compactMap { e in
            guard let t = e as? [String: Any], let name = txt(t["name"], 60) else { return nil }
            let z = (t["zustand"] as? String).flatMap(Teil.Zustand.init(rawValue:)) ?? .unbekannt
            return Teil(name: name, zustand: z, wer: txt(t["wer"], 60), fertigWenn: txt(t["fertigWenn"]))
        }
        plan.offen = (j["offen"] as? [Any] ?? []).compactMap { txt($0) }
        plan.ziel = txt(j["ziel"]); plan.fertig = txt(j["fertig"]); plan.frist = txt(j["frist"], 20); plan.budget = txt(j["budget"], 80)
        plan.stand = txt(j["stand"])
        plan.risiko = (j["risiko"] as? String).flatMap(Risiko.init(rawValue:))
        plan.naechster = naechsterSchritt(md)
        plan.freigabe = (j["freigabe"] as? String).flatMap(Freigabe.init(rawValue:))
        return plan
    }

    static func anfrage(bereichId: String?, boardId: String) -> (pfad: String, workspaceVon: String?) {
        if let b = bereichId, !b.isEmpty { return ("~/Bereiche/\(b)/projekte/\(boardId)/PLAN.md", nil) }
        return ("projekte/\(boardId)/PLAN.md", Hauptagent.id)
    }
    static func anfrageParameter(bereichId: String?, boardId: String) -> [String: Any] {
        let a = anfrage(bereichId: bereichId, boardId: boardId)
        var p: [String: Any] = ["pfad": a.pfad]
        if let w = a.workspaceVon { p["workspaceVon"] = w }
        return p
    }

    static func naechsterSchritt(_ md: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\*\*\s*Nächster Schritt\s*:?\s*\*\*\s*:?\s*(.+)$"#, options: [.caseInsensitive, .anchorsMatchLines]) else { return nil }
        let ns = md as NSString
        guard let m = re.firstMatch(in: md, range: NSRange(location: 0, length: ns.length)), m.range(at: 1).location != NSNotFound else { return nil }
        let s = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : String(s.prefix(300))
    }

    static func kurz(_ md: String) -> Kurz {
        let p = aus(md)
        return Kurz(ziel: p?.ziel, frist: p?.frist, risiko: p?.risiko, naechster: naechsterSchritt(md))
    }
}
