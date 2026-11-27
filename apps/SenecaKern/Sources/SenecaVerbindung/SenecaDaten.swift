import Foundation
import Combine

@MainActor
public final class SenecaDaten: ObservableObject {
    @Published public private(set) var zustand: Verbindungszustand = .aus
    @Published public private(set) var stand: SenecaStand?
    @Published public private(set) var passtNicht = false
    @Published public private(set) var gestrichelt: [Handlung] = []
    @Published public private(set) var letztesErgebnis: (handlung: Handlung, ergebnis: HandlungsErgebnis)?
    @Published public private(set) var rechte: [String] = []
    @Published public private(set) var netz = true

    public let verbindung: Verbindung
    public var aufEreignis: ((String, [String: Any]) -> Void)?
    private let speicher: StandSpeicher
    private let korb: Ausgangskorb
    private let profil: ClientProfil

    public init(_ einstellung: Verbindung.Einstellung, ordner: URL?) {
        profil = einstellung.profil
        verbindung = Verbindung(einstellung)
        speicher = StandSpeicher(datei: ordner?.appendingPathComponent("stand.json"))
        korb = Ausgangskorb(datei: ordner?.appendingPathComponent("ausgangskorb.json"), geraet: einstellung.profil.geraet)
        stand = speicher.stand
        gestrichelt = korb.offen
        if let r = speicher.stand?.regeln { var v = verbindung.regeln; v.uebernehme(r); verbindung.regeln = v; AppRegel.werte = r }
        speicher.aufNeu = { [weak self] s in
            guard let self else { return }
            self.stand = s
            if let r = s.regeln { var v = self.verbindung.regeln; v.uebernehme(r); self.verbindung.regeln = v; AppRegel.werte = r }
        }
        speicher.aufPasstNicht = { [weak self] in self?.passtNicht = true }
        korb.aufAenderung = { [weak self] in self?.gestrichelt = self?.korb.offen ?? [] }
        korb.aufErgebnis = { [weak self] h, e, revision in
            guard let self else { return }
            self.letztesErgebnis = (h, e)
            if revision > self.speicher.revision { self.holen() }
        }
        verbindung.aufZustand = { [weak self] z in
            guard let self else { return }
            self.zustand = z
            if z == .verbunden {
                self.holen()
                self.senden()
            } else if case .getrennt = z {
                self.korb.verwerfeNurOnline()
            }
        }
        verbindung.aufVerbunden = { [weak self] r in self?.rechte = r }
        verbindung.aufNetz = { [weak self] da in self?.netz = da }
        verbindung.aufEreignis = { [weak self] name, inhalt in
            guard let self else { return }
            if name == "plugin.seneca.stand", let r = (inhalt["revision"] as? NSNumber)?.intValue {
                self.speicher.ereignis(revision: r) { [weak self] in await self?.abrufen() }
                return
            }
            self.aufEreignis?(name, inhalt)
        }
    }

    public func starten() { verbindung.starten() }
    public func stoppen() { verbindung.stoppen() }
    public func jetztVersuchen() { verbindung.jetztVersuchen() }

    public func rufe(_ methode: String, _ params: [String: Any] = [:], frist: Double? = nil) async throws -> [String: Any] {
        try await verbindung.rufe(methode, params, frist: frist)
    }

    @discardableResult
    public func handeln(_ art: String, ziel: String? = nil, wert: JSONWert? = nil) -> Handlung? {
        let h = korb.neu(art: art, ziel: ziel, wert: wert, gesehen: speicher.revision, verbunden: zustand == .verbunden, passtNicht: passtNicht)
        senden()
        return h
    }

    public func istGestrichelt(_ kennung: String) -> Bool { korb.istGestrichelt(kennung) }

    private func holen() {
        speicher.abrufen { [weak self] in await self?.abrufen() }
    }

    private func abrufen() async -> Data? {
        var p: [String: Any] = ["geraet": profil.geraet]
        if speicher.revision > 0 { p["revision"] = speicher.revision }
        guard let antwort = try? await verbindung.rufe("seneca.stand", p), let roh = try? JSONSerialization.data(withJSONObject: antwort) else { return nil }
        return roh
    }

    private func senden() {
        guard zustand == .verbunden, !passtNicht else { return }
        korb.senden { [weak self] h in
            guard let self else { throw VerbindungsFehler.offline }
            let a = try await self.verbindung.rufe("seneca.handeln", h.params)
            return (a["ergebnis"] as? String ?? "abgelehnt:leer", (a["revision"] as? NSNumber)?.intValue ?? 0)
        }
    }
}

public enum AppRegel {
    nonisolated(unsafe) public static var werte: [String: Double] = [:]
    public static func wert(_ name: String, _ vorgabe: Double) -> Double { werte[name] ?? vorgabe }
}
