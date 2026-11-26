import Foundation

public enum JSONWert: Codable, Equatable, Sendable {
    case text(String), zahl(Double), wahr(Bool), liste([JSONWert]), objekt([String: JSONWert]), leer

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .leer }
        else if let b = try? c.decode(Bool.self) { self = .wahr(b) }
        else if let d = try? c.decode(Double.self) { self = .zahl(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else if let l = try? c.decode([JSONWert].self) { self = .liste(l) }
        else { self = .objekt(try c.decode([String: JSONWert].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .zahl(let d): try c.encode(d)
        case .wahr(let b): try c.encode(b)
        case .liste(let l): try c.encode(l)
        case .objekt(let o): try c.encode(o)
        case .leer: try c.encodeNil()
        }
    }

    var roh: Any {
        switch self {
        case .text(let s): return s
        case .zahl(let d): return d
        case .wahr(let b): return b
        case .liste(let l): return l.map(\.roh)
        case .objekt(let o): return o.mapValues(\.roh)
        case .leer: return NSNull()
        }
    }
}

public struct Handlung: Codable, Equatable, Sendable, Identifiable {
    public var kennung: String
    public var geraet: String
    public var art: String
    public var ziel: String?
    public var wert: JSONWert?
    public var zeit_geraet: Double
    public var gesehen_revision: Int
    public var id: String { kennung }

    var params: [String: Any] {
        var p: [String: Any] = ["kennung": kennung, "geraet": geraet, "art": art, "zeit_geraet": zeit_geraet, "gesehen_revision": gesehen_revision]
        if let ziel { p["ziel"] = ziel }
        if let wert { p["wert"] = wert.roh }
        return p
    }
}

public enum HandlungsErgebnis: Equatable, Sendable {
    case angenommen, doppelt, ueberholt
    case schonBeantwortet(wahl: String, geraet: String, um: Double?)
    case abgelehnt(String)

    public init(_ roh: String) {
        if roh == "angenommen" { self = .angenommen }
        else if roh == "doppelt" { self = .doppelt }
        else if roh == "ueberholt" { self = .ueberholt }
        else if roh.hasPrefix("schon_beantwortet") {
            let teile = roh.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) } ?? []
            self = .schonBeantwortet(wahl: teile.first ?? "", geraet: teile.count > 1 ? teile[1] : "", um: teile.count > 2 ? Double(teile[2]) : nil)
        } else {
            self = .abgelehnt(roh.hasPrefix("abgelehnt:") ? String(roh.dropFirst("abgelehnt:".count)) : roh)
        }
    }
}

@MainActor
public final class Ausgangskorb {
    public static let nurMitVerbindung: Set<String> = ["frage.antwort", "frage.gesehen", "rueckgaengig", "praesenz", "geraet.aktivitaet"]

    public private(set) var offen: [Handlung] = []
    public private(set) var ergebnisse: [String: HandlungsErgebnis] = [:]
    public var aufAenderung: (() -> Void)?
    public var aufErgebnis: ((Handlung, HandlungsErgebnis, Int) -> Void)?

    private let datei: URL?
    private let geraet: String
    private var sendet = false

    public init(datei: URL?, geraet: String) {
        self.datei = datei
        self.geraet = geraet
        if let datei, let roh = try? Data(contentsOf: datei), let liste = try? JSONDecoder().decode([Handlung].self, from: roh) { offen = liste }
    }

    public func istGestrichelt(_ kennung: String) -> Bool { offen.contains { $0.kennung == kennung } }

    public func neu(art: String, ziel: String? = nil, wert: JSONWert? = nil, gesehen: Int, verbunden: Bool, passtNicht: Bool, jetzt: Date = Date()) -> Handlung? {
        guard !passtNicht else { return nil }
        guard verbunden || !Self.nurMitVerbindung.contains(art) else { return nil }
        let h = Handlung(kennung: UUID().uuidString.lowercased(), geraet: geraet, art: art, ziel: ziel, wert: wert,
                         zeit_geraet: (jetzt.timeIntervalSince1970 * 1000).rounded(), gesehen_revision: gesehen)
        offen.append(h)
        sichern()
        aufAenderung?()
        return h
    }

    public func senden(_ rufe: @escaping (Handlung) async throws -> (String, Int)) {
        guard !sendet, !offen.isEmpty else { return }
        sendet = true
        Task {
            while let h = offen.first {
                guard let (roh, revision) = try? await rufe(h) else { break }
                let e = HandlungsErgebnis(roh)
                offen.removeAll { $0.kennung == h.kennung }
                ergebnisse[h.kennung] = e
                sichern()
                aufErgebnis?(h, e, revision)
                aufAenderung?()
            }
            sendet = false
        }
    }

    public func verwerfeNurOnline() {
        let vorher = offen.count
        offen.removeAll { Self.nurMitVerbindung.contains($0.art) }
        if offen.count != vorher { sichern(); aufAenderung?() }
    }

    private func sichern() {
        guard let datei else { return }
        if let roh = try? JSONEncoder().encode(offen) { try? roh.write(to: datei, options: .atomic) }
    }
}
