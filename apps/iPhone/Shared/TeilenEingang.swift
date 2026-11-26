import Foundation

struct TeilenEintrag: Codable, Equatable, Identifiable {
    var id: String
    var zeit: Date
    var frage: String = ""
    var titel: String = ""
    var adresse: String? = nil
    var text: String? = nil
    var dateien: [String] = []
    var bilder = 0

    var nurMerken: Bool { frage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum TeilenEingang {
    static let gruppe = "group.de.antonio.senecapocket"
    static let textGrenze = 4000

    static var ordner: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppe)?.appendingPathComponent("Eingang", isDirectory: true)
    }

    static func ablegen(_ e: TeilenEintrag, in ordner: URL? = ordner) throws {
        guard let ordner else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try JSONEncoder().encode(e).write(to: ordner.appendingPathComponent("eintrag-\(e.id).json"), options: .atomic)
    }

    static func alle(in ordner: URL? = ordner) -> [TeilenEintrag] {
        guard let ordner, let namen = try? FileManager.default.contentsOfDirectory(atPath: ordner.path) else { return [] }
        return namen.filter { $0.hasPrefix("eintrag-") && $0.hasSuffix(".json") }
            .compactMap { try? JSONDecoder().decode(TeilenEintrag.self, from: Data(contentsOf: ordner.appendingPathComponent($0))) }
            .sorted { $0.zeit < $1.zeit }
    }

    static func entfernen(_ e: TeilenEintrag, in ordner: URL? = ordner) {
        guard let ordner else { return }
        for name in e.dateien + ["eintrag-\(e.id).json"] { try? FileManager.default.removeItem(at: ordner.appendingPathComponent(name)) }
    }

    static func kurz(_ e: TeilenEintrag) -> String {
        let titel = e.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titel.isEmpty { return titel }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let a = e.adresse, !a.isEmpty { return ort(a) ?? a }
        if e.bilder == 1 { return "Ein Bild" }
        if e.bilder > 1 { return "\(e.bilder) Bilder" }
        if e.dateien.count == 1 { return "Eine Datei" }
        return e.dateien.isEmpty ? "Nichts erkannt" : "\(e.dateien.count) Dateien"
    }

    static func ort(_ adresse: String) -> String? {
        guard let host = URL(string: adresse)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func nachricht(_ e: TeilenEintrag, gelesen: String? = nil) -> String {
        var teile = [e.frage.trimmingCharacters(in: .whitespacesAndNewlines), "Das habe ich dir dazu vom iPhone geteilt:"]
        let titel = e.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titel.isEmpty { teile.append("Titel: \(titel)") }
        if let a = e.adresse, !a.isEmpty { teile.append("Adresse: \(a)") }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { teile.append("Text:\n" + String(t.prefix(textGrenze))) }
        if e.bilder > 0 { teile.append(e.bilder == 1 ? "Dazu gehört ein Bild." : "Dazu gehören \(e.bilder) Bilder.") }
        let andere = e.dateien.count - e.bilder
        if andere > 0 { teile.append(andere == 1 ? "Dazu gehört eine Datei." : "Dazu gehören \(andere) Dateien.") }
        if let g = gelesen?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { teile.append("Daraus gelesen:\n" + String(g.prefix(textGrenze))) }
        return teile.joined(separator: "\n\n")
    }

    static func merkzettel(_ e: TeilenEintrag, gelesen: String? = nil) -> (art: String, titel: String, detail: [String: Any]) {
        var d: [String: Any] = ["weg": "teilen", "von_mir": true]
        if let a = e.adresse, !a.isEmpty { d["adresse"] = a }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { d["text"] = String(t.prefix(textGrenze)) }
        if e.bilder > 0 { d["bilder"] = e.bilder }
        if e.dateien.count > e.bilder { d["dateien"] = e.dateien.count - e.bilder }
        if let g = gelesen?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { d["gelesen"] = String(g.prefix(textGrenze)) }
        let nurText = (e.adresse ?? "").isEmpty && e.dateien.isEmpty
        return (nurText ? "nachricht" : "datei", String(kurz(e).prefix(120)), d)
    }
}
