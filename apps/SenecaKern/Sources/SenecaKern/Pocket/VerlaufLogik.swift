import Foundation

enum VerlaufLogik {
    private static let zahlwort = ["", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn"]
    private static let geraete = ["mac": "AM MAC", "iphone": "AM IPHONE", "uhr": "AN DER UHR"]

    static func schluessel() -> String { "\(ClientProfil.aktuell.geraet)-\(UUID().uuidString)" }

    static func geraet(schluessel: String) -> String? {
        let g = schluessel.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        return geraete[g] == nil ? nil : g
    }

    static func vermerk(schluessel: String) -> String? {
        guard let g = geraet(schluessel: schluessel), g != ClientProfil.aktuell.geraet else { return nil }
        return geraete[g]
    }

    static func ohneFrage(_ z: Zug) -> Bool {
        if case .user? = z.start { return false }
        return z.antwort != nil
    }

    static func quittung(_ s: SenecaStand?, sitzung: String, von: Double?, bis: Double?) -> SenecaStand.Quittung? {
        guard let von else { return nil }
        return s?.verlauf?.quittungen?.first { $0.sitzung == sitzung && $0.von >= von - 2000 && $0.von < (bis ?? .infinity) }
    }

    static func anteil(_ z: SenecaStand.Zuruecklegen, jetzt: Double) -> Double { max(0, min(1, (z.bis - jetzt) / max(1, z.bis - z.ab))) }

    static func ruhtSeit(_ ms: Double, jetzt: Double, _ cal: Calendar = .current) -> String {
        let a = Date(timeIntervalSince1970: ms / 1000), j = Date(timeIntervalSince1970: jetzt / 1000)
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: j)).day ?? 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = tage < 7 ? "EEEE" : "d. MMM"
        return "ruht seit " + (tage == 0 ? HeuteTafelLogik.uhr(ms, cal) : tage == 1 ? "gestern" : f.string(from: a))
    }

    static func dauer(_ ms: Double) -> String {
        let s = Int((ms / 1000).rounded())
        return s < 20 ? "\(s) s" : "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private static func mehrzahl(_ w: String, _ n: Int) -> String {
        guard n > 1 else { return w }
        return "\(n < zahlwort.count ? zahlwort[n] : String(n)) " + w + (w.hasSuffix("e") ? "n" : w.hasSuffix("l") ? "s" : "en")
    }

    static func spur(_ schritte: [Schritt], dauerMs: Double) -> (titel: String, zeile: String) {
        let echt = schritte.filter { $0.art != .gedanke }
        let d = dauerMs > 0 ? " · " + dauer(dauerMs) : ""
        guard !echt.isEmpty, echt.allSatisfy({ [.lesen, .web, .suche].contains($0.art) }) else {
            return ((echt.count == 1 ? "1 Schritt" : "\(echt.count) Schritte") + d, "")
        }
        var namen: [(String, Int)] = []
        for s in echt {
            let n = s.detail ?? s.text
            if let i = namen.firstIndex(where: { $0.0 == n }) { namen[i].1 += 1 } else { namen.append((n, 1)) }
        }
        let teile = namen.map { mehrzahl($0.0, $0.1) }
        let liste = teile.count > 1 ? teile.dropLast().joined(separator: ", ") + " und " + teile.last! : teile[0]
        return ("So habe ich geplant", liste + " gelesen" + d)
    }
}
