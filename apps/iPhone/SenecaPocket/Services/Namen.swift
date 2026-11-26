import Foundation

@MainActor
enum Namen {
    static func mitarbeiter(_ kennung: String) -> String {
        var bekannt: [String: String] = ChatPartner.agentNamen
        for p in GespraechsPartner.alle { bekannt[p.id] = p.kopfName }
        return anzeige(kennung, bekannt: bekannt)
    }

    nonisolated static func anzeige(_ kennung: String, bekannt: [String: String]) -> String {
        let id = reineKennung(kennung)
        if Hauptagent.ist(id) { return "Seneca" }
        if let name = bekannt[id]?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        return id.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    nonisolated static func reineKennung(_ kennung: String) -> String {
        let teile = kennung.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        if teile.count >= 2, teile[0] == "agent" { return teile[1].lowercased() }
        return (teile.first ?? "").lowercased()
    }
}
