import Foundation

struct TastenDoppelSperre {
    struct Druck: Equatable {
        var code: UInt16
        var zeichen: String
        var tasten: UInt
        var zeit: TimeInterval
        var wiederholung = false
        var vomGeraet = true
    }
    static let abstand: TimeInterval = 0.012
    private var letzter: Druck?
    private(set) var verworfen = 0

    mutating func istDoppelt(_ d: Druck) -> Bool {
        defer { letzter = d }
        guard let l = letzter, !d.wiederholung, d.vomGeraet, l.vomGeraet, d.code == l.code, d.zeichen == l.zeichen, d.tasten == l.tasten,
              abs(d.zeit - l.zeit) < Self.abstand else { return false }
        verworfen += 1
        return true
    }
}

struct EinfuegeSperre {
    private var druck: TimeInterval?
    private var text = ""
    private(set) var verworfen = 0

    mutating func istDoppelt(_ neu: String, druck d: TimeInterval?, ersetzt: Bool) -> Bool {
        guard let d, !ersetzt, neu.count == 1 else { druck = nil; return false }
        defer { druck = d; text = neu }
        guard druck == d, text == neu else { return false }
        verworfen += 1
        return true
    }
}
