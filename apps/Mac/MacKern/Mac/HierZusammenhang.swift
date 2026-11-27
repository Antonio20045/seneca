import Foundation

struct HierZusammenhang: Equatable, Sendable {
    enum Art: String, Sendable { case browser, mail, finder, fenster }

    var art: Art = .fenster
    var programm = ""
    var titel = ""
    var adresse = ""
    var absender = ""
    var markiert = ""
    var text = ""
    var dateien: [URL] = []
    var hatFensterfoto = false
    var hatBildschirmfoto = false

    var istLeer: Bool { programm.isEmpty && titel.isEmpty && markiert.isEmpty && text.isEmpty && dateien.isEmpty }

    static let grenze = 6000
    static let grenzeMarkiert = 3000

    private static func rein(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t\x{00A0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ?\n ?"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func anWort(_ s: Substring, vorn: Bool) -> String {
        if vorn { if let i = s.prefix(40).firstIndex(where: { $0 == " " || $0 == "\n" }) { return String(s[s.index(after: i)...]) }; return String(s) }
        if let i = s.suffix(40).lastIndex(where: { $0 == " " || $0 == "\n" }) { return String(s[..<i]) }
        return String(s)
    }

    static func kuerze(_ roh: String, markiert: String = "", grenze: Int = grenze) -> String {
        let t = rein(roh)
        if t.count <= grenze { return t }
        let m = rein(markiert)
        let stelle = m.count >= 12 ? t.range(of: String(m.prefix(80))) : nil
        let luecke = "\n[…]\n"
        if let stelle {
            let anfang = grenze * 3 / 10, ende = grenze * 2 / 10, mitte = grenze - anfang - ende
            let pos = t.distance(from: t.startIndex, to: stelle.lowerBound)
            if pos + min(m.count, mitte) > anfang {
                let von = max(anfang, pos - mitte / 4), bis = min(t.count - ende, von + mitte)
                if von < bis {
                    let a = anWort(t.prefix(anfang), vorn: false)
                    let b = anWort(anWort(t.dropFirst(von).prefix(bis - von), vorn: true)[...], vorn: false)
                    let c = anWort(t.suffix(ende), vorn: true)
                    return [a, b, c].filter { !$0.isEmpty }.joined(separator: luecke)
                }
            }
        }
        let anfang = grenze * 3 / 4
        return anWort(t.prefix(anfang), vorn: false) + luecke + anWort(t.suffix(grenze - anfang), vorn: true)
    }

    var sichtKurz: String { [programm, kurzTitel].filter { !$0.isEmpty }.joined(separator: " · ") }

    private var kurzTitel: String { Menschlich.kuerzen(titel.trimmingCharacters(in: .whitespacesAndNewlines), 70) }

    var anhangText: String {
        if istLeer { return "" }
        if hatBildschirmfoto {
            var z = ["[Mitgegeben über „Bildschirm zeigen“ am Mac: Ein Foto meines ganzen Bildschirms liegt als Anhang bei.]"]
            if !programm.isEmpty { z.append("Vorn war: \(programm)" + (titel.isEmpty ? "" : " – \(titel)")) }
            return z.joined(separator: "\n")
        }
        var z: [String] = ["[Mitgegeben von „Seneca hier“ am Mac: das hatte ich beim Fragen vor mir.]", "Programm: \(programm)"]
        switch art {
        case .browser:
            if !titel.isEmpty { z.append("Seite: \(titel)") }
            if !adresse.isEmpty { z.append("Adresse: \(adresse)") }
        case .mail:
            if !titel.isEmpty { z.append("Betreff der Mail: \(titel)") }
            if !absender.isEmpty { z.append("Absender: \(absender)") }
        case .finder:
            if !dateien.isEmpty { z.append("Markierte Dateien (als Anhang dabei): " + dateien.map(\.lastPathComponent).joined(separator: ", ")) }
        case .fenster:
            if !titel.isEmpty { z.append("Fenster: \(titel)") }
            if hatFensterfoto { z.append("Ein Foto des Fensters liegt als Anhang bei.") }
        }
        let m = Self.kuerze(markiert, grenze: Self.grenzeMarkiert)
        if !m.isEmpty { z.append("Markierte Stelle:\n«\(m)»") }
        let roh = Self.rein(text)
        if !roh.isEmpty {
            let k = Self.kuerze(roh, markiert: markiert)
            let wort = art == .mail ? "Text der Mail" : "Text der Seite"
            z.append(k.count < roh.count ? "\(wort) (gekürzt auf \(k.count) von \(roh.count) Zeichen):\n\(k)" : "\(wort):\n\(k)")
        } else if art == .browser, !adresse.isEmpty {
            z.append("Den Seitentext konnte der Mac nicht lesen; die Adresse lässt sich abrufen.")
        }
        return z.joined(separator: "\n")
    }

    func nachricht(frage: String) -> String {
        let a = anhangText
        return a.isEmpty ? frage : frage + "\n\n" + a
    }

    var zeichen: Int { anhangText.count }
}
