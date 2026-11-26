import Foundation

public struct Verbindungsregeln: Equatable, Sendable {
    public var startS: Double = 1
    public var maxS: Double = 30
    public var anmeldefehlerMax: Int = 3
    public var getrenntNachS: Double = 30
    public var antwortFristS: Double = 30

    public init() {}

    public mutating func uebernehme(_ regeln: [String: Double]) {
        if let v = regeln["verbinden_start_s"] { startS = v }
        if let v = regeln["verbinden_max_s"] { maxS = v }
        if let v = regeln["anmeldefehler_max"] { anmeldefehlerMax = Int(v) }
        if let v = regeln["getrennt_nach_s"] { getrenntNachS = v }
    }
}

public struct Wiederverbinden: Equatable, Sendable {
    public enum Schritt: Equatable, Sendable { case warte(Double), neuKoppeln }

    public private(set) var versuche = 0
    public private(set) var anmeldefehler = 0
    public var regeln: Verbindungsregeln

    public init(regeln: Verbindungsregeln = Verbindungsregeln()) { self.regeln = regeln }

    public mutating func nachFehler(anmeldung: Bool, zufall: Double = Double.random(in: 0...1)) -> Schritt {
        if anmeldung {
            anmeldefehler += 1
            if anmeldefehler >= regeln.anmeldefehlerMax { return .neuKoppeln }
        }
        versuche += 1
        let grenze = min(regeln.maxS, regeln.startS * pow(2, Double(versuche - 1)))
        return .warte(max(regeln.startS, grenze * (0.5 + 0.5 * zufall)))
    }

    public mutating func verbunden() {
        versuche = 0
        anmeldefehler = 0
    }

    public mutating func sofort() { versuche = 0 }

    public static func istAnmeldefehler(_ code: String) -> Bool {
        let c = code.uppercased()
        return !c.contains("PAIRING") && (c.contains("TOKEN_MISMATCH") || c.contains("UNAUTHORIZED") || c.contains("AUTH"))
    }
}
