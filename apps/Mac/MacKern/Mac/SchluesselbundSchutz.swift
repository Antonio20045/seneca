import Foundation

enum SchluesselbundSchutz {
    static func gesperrt(hintergrund: String?, daten: String?, profilTest: Bool) -> Bool {
        if let h = hintergrund, !h.isEmpty, h != "0" { return true }
        if let d = daten, !d.isEmpty { return true }
        return profilTest
    }
}
