import Foundation

enum StromSchnitt {
    struct Teile: Equatable, Sendable {
        var fest: [String]
        var offen: String
    }

    static func teile(_ text: String, buendel: Int = 8) -> Teile {
        let bytes = text.utf8
        var fest: [String] = []
        var schnitte = 0
        var stueckAnfang = bytes.startIndex
        var anfang = bytes.startIndex
        var imCode = false
        var leerDavor = false
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let ende = bytes[i...].firstIndex(of: 10)
            let zeile = text[i..<(ende ?? bytes.endIndex)]
            let erstes = zeile.utf8.first { $0 != 32 && $0 != 9 && $0 != 13 }
            let steht = ende != nil || zeile.utf8.count >= 8
            if !imCode, leerDavor, steht, erstes != nil, zeile.utf8.first != 32, zeile.utf8.first != 9, MDParser.listItem(String(zeile)) == nil {
                if text[anfang..<i].utf8.contains(where: { $0 != 32 && $0 != 9 && $0 != 13 && $0 != 10 }) {
                    schnitte += 1
                    if schnitte % buendel == 0 {
                        fest.append(text[stueckAnfang..<i].trimmingCharacters(in: .whitespacesAndNewlines))
                        stueckAnfang = i
                    }
                }
                anfang = i
            }
            if erstes == 96 {
                let kern = zeile.trimmingCharacters(in: .whitespacesAndNewlines)
                if imCode {
                    if kern.count >= 3, kern.allSatisfy({ $0 == "`" }) { imCode = false }
                } else if kern.hasPrefix("```"), !kern.drop(while: { $0 == "`" }).contains("`") {
                    imCode = true
                }
            }
            leerDavor = erstes == nil && !imCode
            guard let ende else { break }
            i = bytes.index(after: ende)
        }
        if stueckAnfang < anfang { fest.append(text[stueckAnfang..<anfang].trimmingCharacters(in: .whitespacesAndNewlines)) }
        return Teile(fest: fest, offen: String(text[anfang...]))
    }
}
