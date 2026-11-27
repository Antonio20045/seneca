import SwiftUI

struct KopfSatz: Equatable {
    var vor = ""
    var akzent = ""
    var nach = ""
    var leise = ""
}

struct HeuteSatzText: View {
    var satz: KopfSatz

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            (Text(satz.vor) + Text(satz.akzent).font(Stil.Schrift.gross.kursiv) + Text(Self.fest(satz.nach)))
                .schrift(.gross)
                .foregroundStyle(Stil.tinte.voll)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if !satz.leise.isEmpty {
                Text(Self.fest(satz.leise))
                    .schrift(.text)
                    .foregroundStyle(Stil.tinte.zweit)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func fest(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard let letzte = t.lastIndex(of: " ") else { return s.hasPrefix(" ") ? "\u{00A0}" + t : s }
        t.replaceSubrange(letzte...letzte, with: "\u{00A0}")
        return (s.hasPrefix(" ") ? " " : "") + t
    }
}

enum HeuteLogik {
    static func uhr(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.minute ?? 0) == 0 ? "\(c.hour ?? 0) Uhr" : String(format: "%d:%02d Uhr", c.hour ?? 0, c.minute ?? 0)
    }

    static func anzeigeTitel(_ titel: String) -> String {
        let bereinigt = titel.replacingOccurrences(of: #"\s*\([A-Z]{1,2}-\d+[a-z]*\)\s*$"#, with: "", options: .regularExpression)
        return bereinigt.isEmpty ? titel : bereinigt
    }

    static func kontext(_ t: SenecaTask) -> (lang: String, kurz: String)? {
        switch (t.bereichName, t.projektName) {
        case let (b?, p?) where b != p: return ("\(b) · \(p)", b)
        case let (b?, _): return (b, b)
        case let (nil, p?): return (p, p)
        default: return nil
        }
    }

    static func seit(_ d: Date?, jetzt: Date) -> String? {
        guard let d, d < jetzt else { return nil }
        return "seit " + seitText(d, jetzt: jetzt).replacingOccurrences(of: " Uhr", with: "")
    }
    static func seitText(_ seit: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: seit), to: cal.startOfDay(for: jetzt)).day ?? 0
        switch tage {
        case ...0: return uhr(seit, cal)
        case 1: return "gestern"
        case 2: return "vorgestern"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE"); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "EEEE"
            return f.string(from: seit)
        }
    }
    static func datum(_ zahl: Double) -> Date? {
        if zahl > 1e12 { return Date(timeIntervalSince1970: zahl / 1000) }
        if zahl > 1e9 { return Date(timeIntervalSince1970: zahl) }
        return nil
    }
}
