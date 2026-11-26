import Foundation

struct PlanVorschlag: Equatable {
    var meilensteine: [OvMeilenstein]
    var pakete: [String]
    var risiko: String
    var lokal: Bool

    init(meilensteine: [OvMeilenstein], pakete: [String], risiko: String, lokal: Bool) {
        self.meilensteine = meilensteine; self.pakete = pakete; self.risiko = risiko; self.lokal = lokal
    }
}

enum PlanVorschlagAufgabe {
    static let system = """
    Du bist der Leiter eines Bereichs und sollst für ein neues Projekt einen kurzen Plan vorschlagen. \
    Antworte ausschließlich als JSON-Objekt mit den Feldern "meilensteine" (Liste von Objekten mit "name" und \
    optional "datum" als Text wie "15. Dezember"), "pakete" (Liste von 2-4 kurzen Titeln erster Arbeitspakete) \
    und "risiko" (ein Satz: "bequem", "knapp" oder "passt nicht" mit kurzer Begründung). Kein Fließtext außerhalb des JSON.
    """

    static func nutzer(bereich: String, ziel: String, terminText: String) -> String {
        "Bereich: \(bereich)\nZiel: \(ziel)\nTermin: \(terminText.isEmpty ? "kein fester Termin" : terminText)"
    }

    static func lies(_ antwort: String, lokal: Bool) -> PlanVorschlag? {
        guard let start = antwort.firstIndex(of: "{"), let ende = antwort.lastIndex(of: "}") else { return nil }
        let stueck = String(antwort[start...ende])
        guard let daten = stueck.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { return nil }
        let meilensteine = (o["meilensteine"] as? [[String: Any]])?.compactMap { m -> OvMeilenstein? in
            guard let n = (m["name"] as? String)?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
            if let d = m["datum"] as? String, !d.isEmpty { return OvMeilenstein(name: "\(n) (\(d))") }
            return OvMeilenstein(name: n)
        } ?? []
        let pakete = (o["pakete"] as? [String])?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let risiko = (o["risiko"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !meilensteine.isEmpty || !pakete.isEmpty else { return nil }
        return PlanVorschlag(meilensteine: meilensteine, pakete: pakete, risiko: risiko, lokal: lokal)
    }

    static func erstelle(klient: OllamaKlient, bereich: String, ziel: String, terminText: String) async throws -> PlanVorschlag {
        let antwort = try await klient.antwort(system: system, nutzer: nutzer(bereich: bereich, ziel: ziel, terminText: terminText), json: true, zeitlimit: 90)
        guard let vorschlag = lies(antwort, lokal: true) else { throw OllamaFehler(text: "Konnte den Plan-Entwurf nicht lesen.") }
        return vorschlag
    }
}
