import Foundation

struct DiktatTippErkennung {
    enum Ereignis {
        case flaggen(code: UInt16, flags: UInt, zeit: TimeInterval)
        case taste(code: UInt16, zeit: TimeInterval)
        case zeiger(zeit: TimeInterval)
    }

    enum Ergebnis: Equatable {
        case nichts
        case tipp
        case escape
    }

    static let rechteBefehlCode: UInt16 = 54
    static let escapeCode: UInt16 = 53
    static let rechteBefehlMaske: UInt = 0x10
    static let linkeBefehlMaske: UInt = 0x08

    private static let befehl: UInt = 0x100000
    private static let andereZusatz: UInt = 0x20000 | 0x80000 | 0x40000 | 0x800000

    var grenze: TimeInterval = 0.4
    private var seit: TimeInterval?

    mutating func verarbeite(_ e: Ereignis) -> Ergebnis {
        switch e {
        case .zeiger:
            seit = nil
            return .nichts
        case .taste(let code, _):
            seit = nil
            return code == Self.escapeCode ? .escape : .nichts
        case .flaggen(let code, let flags, let zeit):
            guard code == Self.rechteBefehlCode else {
                seit = nil
                return .nichts
            }
            let unten = flags & Self.rechteBefehlMaske != 0
            if unten {
                let allein = flags & Self.befehl != 0
                    && flags & Self.linkeBefehlMaske == 0
                    && flags & Self.andereZusatz == 0
                seit = allein ? zeit : nil
                return .nichts
            }
            defer { seit = nil }
            guard let beginn = seit else { return .nichts }
            let dauer = zeit - beginn
            return dauer >= 0 && dauer < grenze ? .tipp : .nichts
        }
    }
}
