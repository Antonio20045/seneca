import Foundation

enum StatistikLogik {
    static func zeitraum(_ kopf: String, stand: Double) -> String {
        let t = kopf.components(separatedBy: " · ")
        let tage = (t.last ?? "").replacingOccurrences(of: ". bis ", with: ".–")
        return ([tage, t.first ?? ""] + ["Stand " + HeuteTafelLogik.uhr(stand)]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func heuteSatz(_ z: SenecaStatistik.Zeile?) -> String? {
        guard let z, z.links.hasPrefix("HEUTE") else { return nil }
        return "Heute " + z.wert + (z.unter.isEmpty ? "." : ", \(z.unter).")
    }

    static func achtWochen(_ u: SenecaStatistik.Uebung) -> [SenecaStatistik.Punkt] { Array(u.wochen.suffix(8)) }
}
