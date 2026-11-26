import Foundation

enum NotizblockUebernahme {
    struct Eintrag: Equatable { let id: String; let titel: String }

    static let sicherungsEndung = "vor-runde2-20261110"

    @discardableResult
    static func sichere(_ datei: URL, fm: FileManager = .default) -> URL? {
        guard fm.fileExists(atPath: datei.path) else { return nil }
        let ziel = datei.appendingPathExtension(sicherungsEndung)
        if fm.fileExists(atPath: ziel.path) { return ziel }
        return (try? fm.copyItem(at: datei, to: ziel)) != nil ? ziel : nil
    }

    static func offene(_ datei: URL) -> [Eintrag] {
        guard let wurzel = lies(datei) else { return [] }
        let erledigt = Set((wurzel["erledigt"] as? [String]) ?? [])
        return ((wurzel["eintraege"] as? [[String: Any]]) ?? []).compactMap { e in
            guard let id = e["id"] as? String, let titel = (e["titel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !titel.isEmpty, !erledigt.contains(id) else { return nil }
            return Eintrag(id: id, titel: titel)
        }
    }

    static func entferne(_ id: String, aus datei: URL) {
        guard var wurzel = lies(datei) else { return }
        wurzel["eintraege"] = ((wurzel["eintraege"] as? [[String: Any]]) ?? []).filter { ($0["id"] as? String) != id }
        wurzel["erledigt"] = ((wurzel["erledigt"] as? [String]) ?? []).filter { $0 != id }
        if let d = try? JSONSerialization.data(withJSONObject: wurzel, options: [.sortedKeys]) { try? d.write(to: datei, options: .atomic) }
    }

    private static func lies(_ datei: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: datei) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
