import Foundation

struct Gespraech: Equatable {
    enum Phase: String, Equatable {
        case aus
        case hoert
        case wartet
        case spricht
    }

    enum Ende: Equatable {
        case beendet
        case schluss
        case stille
        case getippt
        case verlassen
        case fehler
    }

    enum Ereignis: Equatable {
        case start
        case erkannt(String)
        case stille
        case leerlauf
        case antwort(String)
        case antwortBeginnt(String)
        case satzDazu(String)
        case vorgelesen
        case unterbrochen
        case fehlgeschlagen
        case beenden(Ende)
    }

    enum Aktion: Equatable {
        case hoeren
        case neueRunde
        case mikroAus
        case sende(String)
        case lesVor
        case stoppeVorlesen
        case ende(Ende)
    }

    static let stilleSekunden = 1.4
    static let leerlaufSekunden = 20.0

    private(set) var phase: Phase = .aus
    private(set) var text = ""
    private(set) var vorgelesen = ""

    var aktiv: Bool { phase != .aus }

    @discardableResult
    mutating func handle(_ ereignis: Ereignis) -> [Aktion] {
        switch (phase, ereignis) {
        case (.aus, .start):
            phase = .hoert
            text = ""
            return [.hoeren]

        case (.hoert, .erkannt(let neu)):
            if !neu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = neu }
            return []

        case (.hoert, .stille):
            let satz = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !satz.isEmpty else { return [] }
            if Self.istSchluss(satz) { return beende(.schluss) }
            phase = .wartet
            text = ""
            return [.mikroAus, .sende(satz)]

        case (.hoert, .leerlauf):
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return beende(.stille)

        case (.wartet, .antwort(let gelesen)):
            if gelesen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                phase = .hoert
                text = ""
                return [.hoeren]
            }
            phase = .spricht
            vorgelesen = gelesen
            return [.hoeren, .lesVor]

        case (.wartet, .antwortBeginnt(let satz)):
            phase = .spricht
            vorgelesen = satz
            return [.hoeren]

        case (.spricht, .satzDazu(let satz)):
            vorgelesen += " " + satz
            return []

        case (.spricht, .erkannt(let gehoert)):
            guard Self.istUnterbrechung(gehoert, vorgelesen: vorgelesen) else { return [] }
            phase = .hoert
            text = gehoert
            vorgelesen = ""
            return [.stoppeVorlesen]

        case (.spricht, .vorgelesen):
            phase = .hoert
            text = ""
            vorgelesen = ""
            return [.neueRunde]

        case (.spricht, .unterbrochen):
            phase = .hoert
            text = ""
            vorgelesen = ""
            return [.stoppeVorlesen, .neueRunde]

        case (.wartet, .fehlgeschlagen):
            return beende(.fehler)

        case (.aus, _):
            return []

        case (_, .beenden(let grund)):
            return beende(grund)

        default:
            return []
        }
    }

    private mutating func beende(_ grund: Ende) -> [Aktion] {
        let sprach = phase == .spricht
        phase = .aus
        text = ""
        vorgelesen = ""
        return (sprach ? [.stoppeVorlesen] : []) + [.mikroAus, .ende(grund)]
    }

    static func woerter(_ text: String) -> [String] {
        let glatt = text.replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        return glatt.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static let schlussSaetze: Set<[String]> = [
        ["schluss"], ["schluss", "damit"], ["schluss", "fuer", "heute"], ["das", "wars"], ["das", "war", "alles"],
        ["das", "ist", "alles"], ["ende"], ["tschuss"], ["tschuess"], ["gesprach", "beenden"], ["gespraech", "beenden"],
    ]
    private static let schlussVor: Set<String> = ["ok", "okay", "gut", "so", "also", "ja", "danke", "dankeschon", "dankeschoen"]
    private static let schlussNach: Set<String> = ["danke", "dankeschon", "dankeschoen", "seneca", "jetzt", "bitte", "dir"]

    static func istSchluss(_ text: String) -> Bool {
        var w = woerter(text)
        while let erstes = w.first, schlussVor.contains(erstes), w.count > 1 { w.removeFirst() }
        while let letztes = w.last, schlussNach.contains(letztes), w.count > 1 { w.removeLast() }
        return schlussSaetze.contains(w)
    }

    static func istUnterbrechung(_ gehoert: String, vorgelesen: String) -> Bool {
        let w = woerter(gehoert)
        guard !w.isEmpty else { return false }
        let eigene = Set(woerter(vorgelesen))
        if w.allSatisfy({ eigene.contains($0) }) { return false }
        return w.count >= 2 || (w.first?.count ?? 0) >= 4
    }
}

struct SatzStrom: Equatable {
    private(set) var gegeben: [String] = []

    mutating func neu(_ text: String, ende: Bool = false) -> [String] {
        let alle = Self.saetze(text, ende: ende)
        guard alle.count > gegeben.count else { return [] }
        let neue = Array(alle[gegeben.count...])
        gegeben += neue
        return neue
    }

    static func saetze(_ text: String, ende: Bool) -> [String] {
        let zeilen = text.components(separatedBy: .newlines)
        var out: [String] = []
        var imCode = false
        for (i, roh) in zeilen.enumerated() {
            let offen = !ende && i == zeilen.count - 1
            let kopf = roh.trimmingCharacters(in: .whitespaces)
            if kopf.hasPrefix("```") || kopf.hasPrefix("~~~") { imCode.toggle(); continue }
            if imCode || kopf.hasPrefix("|") || istLinie(kopf) { continue }
            let zeile = sprechzeile(kopf)
            guard zeile.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            var teile = SpeechLogic.sentences(zeile)
            if offen {
                let rest = teile.popLast() ?? ""
                if let letzter = teile.last, letzter.hasSuffix("."), istMonatsanfang(rest) { teile.removeLast() }
            } else if let letzter = teile.popLast() {
                teile.append(".!?…:".contains(letzter.last ?? " ") ? letzter : letzter + ".")
            }
            out += teile.filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        }
        return out
    }

    private static func istLinie(_ zeile: String) -> Bool {
        zeile.count >= 3 && zeile.allSatisfy { "-=_*·—– ".contains($0) } && zeile.contains(where: { "-=_*—–".contains($0) })
    }

    private static func istMonatsanfang(_ wort: String) -> Bool {
        let w = wort.lowercased()
        guard !w.isEmpty, w.allSatisfy(\.isLetter) else { return false }
        return SpeechLogic.months.contains { $0.hasPrefix(w) }
    }

    private static let uhrzeile = try! NSRegularExpression(pattern: #"^(?:[-–•*]\s*)?(?:\*\*)?(\d{1,2}):(\d{2})(?:\s*Uhr)?(?:\*\*)?\s*(?:[-–—:·|]\s*)?(.+)$"#)
    private static let listenpunkt = try! NSRegularExpression(pattern: #"^(?:[-–•*>]|\d+[.)])\s+"#)

    static func sprechzeile(_ zeile: String) -> String {
        var t = AnswerParser.clean(zeile)
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        let ns = t as NSString
        if let m = uhrzeile.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
           let h = Int(ns.substring(with: m.range(at: 1))), h < 24 {
            let rest = ns.substring(with: m.range(at: 3)).replacingOccurrences(of: "*", with: "")
            let geteilt = AnswerParser.splitDay(rest)
            let zeit = AnswerParser.spokenTime("\(h):\(ns.substring(with: m.range(at: 2)))")
            if geteilt.day.isEmpty { t = "\(zeit) \(rest)" }
            else { t = "\(geteilt.day.prefix(1).uppercased() + geteilt.day.dropFirst()) um \(zeit) \(geteilt.text)" }
        } else {
            t = listenpunkt.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        t = t.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "~~", with: "")
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}
