import Foundation

struct TageslaufMeldung: Equatable, Identifiable {
    var id: String
    var zeit: Date?
    var titel: String
    var text: String
    var knoepfe: [String]
    var dringend: Bool

    static func lies(_ daten: Data, jetzt: Date = Date(), kalender: Calendar = .current) -> [TageslaufMeldung] {
        guard let liste = (try? JSONSerialization.jsonObject(with: daten)) as? [Any] else { return [] }
        var gesehen = Set<String>()
        return liste.compactMap { $0 as? [String: Any] }.compactMap { m in
            let id = (m["id"] as? String ?? (m["id"] as? NSNumber)?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            let titel = (m["titel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = (m["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !(titel.isEmpty && text.isEmpty), gesehen.insert(id).inserted else { return nil }
            let knoepfe = ((m["knoepfe"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return TageslaufMeldung(id: id, zeit: TageslaufZeit.lies(m["zeit"], heute: jetzt, kalender: kalender), titel: titel.isEmpty ? "Seneca" : titel, text: text,
                                    knoepfe: Array(knoepfe.prefix(4)), dringend: (m["dringend"] as? Bool) ?? ((m["dringend"] as? NSNumber)?.boolValue ?? false))
        }
    }

    var gruppe: String? {
        guard !knoepfe.isEmpty else { return nil }
        var h: UInt64 = 0xcbf29ce484222325
        for b in knoepfe.joined(separator: "\u{1F}").utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "seneca.meldung." + String(h, radix: 36)
    }

    static func knopfKennung(_ i: Int) -> String { "seneca.knopf.\(i)" }
    static func wahl(aktion: String, knoepfe: [String]) -> String? {
        guard aktion.hasPrefix("seneca.knopf."), let i = Int(aktion.dropFirst("seneca.knopf.".count)), knoepfe.indices.contains(i) else { return nil }
        return knoepfe[i]
    }
}

enum MenueTag {
    private static let zeigbar: Set<String> = ["termin", "kalender", "besprechung", "meeting", "training", "ort", "verabredung"]

    static func kurz(_ t: String, _ max: Int = 24) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= max { return s }
        let k = String(s.prefix(max))
        let schnitt = k.lastIndex(of: " ").map { String(k[..<$0]) } ?? k
        return (schnitt.count >= max / 2 ? schnitt : k).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    static func jetzt(_ t: Tageslauf, jetzt: Date) -> TageslaufEreignis? {
        (t.ereignisse + t.kommt).filter { e in
            guard let a = e.zeit, let b = e.ende, !e.ganztags, !e.routine, zeigbar.contains(e.art) else { return false }
            return a <= jetzt && jetzt < b
        }.max { ($0.zeit ?? .distantPast) < ($1.zeit ?? .distantPast) }
    }

    static func kommt(_ t: Tageslauf, jetzt: Date) -> TageslaufEreignis? {
        (t.kommt + t.ereignisse).filter { e in
            guard let a = e.zeit, !e.ganztags else { return false }
            return a > jetzt
        }.min { $0.zeit! < $1.zeit! }
    }

    static func zeile(_ t: Tageslauf?, jetzt: Date, kalender: Calendar = .current) -> String {
        guard let t else { return "" }
        var teile: [String] = []
        if let j = self.jetzt(t, jetzt: jetzt), let ende = j.ende {
            teile.append("\(kurz(j.titel)) bis \(TageslaufZeit.hhmm(ende, kalender: kalender))")
        } else if !t.jetztText.isEmpty {
            teile.append(kurz(t.jetztText))
        }
        if let k = kommt(t, jetzt: jetzt), let z = k.zeit, kalender.isDate(z, inSameDayAs: jetzt) {
            teile.append("\(TageslaufZeit.hhmm(z, kalender: kalender)) \(kurz(k.titel))")
        }
        return teile.joined(separator: " · ")
    }
}
