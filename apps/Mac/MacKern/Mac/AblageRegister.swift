import Foundation

struct AblageEintrag: Equatable, Identifiable {
    var id: String { pfad }
    var name: String
    var unter: String
    var pfad: String
}

enum AblageRegister {
    static let hoechstens = 400_000
    private static let orte = ["fach", "liegt", "bleibt", "downloads"]

    static func neueste(_ text: String, anzahl: Int = 5, gibtEs: (String) -> Bool) -> [AblageEintrag] {
        var liste: [(zeit: String, nr: Int, e: AblageEintrag)] = []
        for (nr, roh) in text.split(whereSeparator: \.isNewline).enumerated() {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(roh.utf8))) as? [String: Any] else { continue }
            func s(_ k: String) -> String { (o[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            if s("stand") == "zurueckgenommen" { continue }
            guard let pfad = orte.map(s).first(where: { !$0.isEmpty && gibtEs($0) }) else { continue }
            let alt = s("alter_name")
            let name = (pfad as NSString).lastPathComponent
            let unter = !alt.isEmpty && alt != name ? "vorher: " + alt : s("satz")
            liste.append((s("zeit"), nr, AblageEintrag(name: name, unter: unter, pfad: pfad)))
        }
        liste.sort { $0.zeit != $1.zeit ? $0.zeit > $1.zeit : $0.nr > $1.nr }
        var gesehen = Set<String>(), aus: [AblageEintrag] = []
        for x in liste where gesehen.insert(x.e.pfad).inserted {
            aus.append(x.e)
            if aus.count == anzahl { break }
        }
        return aus
    }

    static func ende(_ url: URL, bytes: Int = hoechstens) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let laenge = (try? h.seekToEnd()) ?? 0
        let ab = laenge > UInt64(bytes) ? laenge - UInt64(bytes) : 0
        guard (try? h.seek(toOffset: ab)) != nil, let d = try? h.readToEnd() else { return nil }
        var text = String(decoding: d, as: UTF8.self)
        if ab > 0, let i = text.firstIndex(where: \.isNewline) { text = String(text[text.index(after: i)...]) }
        return text
    }

    static func notizen(in ordner: URL, anzahl: Int = 5, fm: FileManager = .default) -> [AblageEintrag] {
        guard let alle = try? fm.contentsOfDirectory(at: ordner, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM, HH:mm"
        return alle.filter { $0.pathExtension.lowercased() == "md" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(anzahl)
            .map { AblageEintrag(name: $0.0.deletingPathExtension().lastPathComponent, unter: f.string(from: $0.1), pfad: $0.0.path) }
    }

    static func zuletzt(register: URL?, meetings: URL?, anzahl: Int = 5, fm: FileManager = .default) -> (titel: String, eintraege: [AblageEintrag]) {
        if let register, let text = ende(register) {
            let e = neueste(text, anzahl: anzahl) { fm.fileExists(atPath: $0) }
            if !e.isEmpty { return ("Zuletzt abgelegt", e) }
        }
        if let meetings {
            let n = notizen(in: meetings, anzahl: anzahl, fm: fm)
            if !n.isEmpty { return ("Letzte Meeting-Notizen", n) }
        }
        return ("", [])
    }
}
