import SwiftUI

enum PanelInhalt: Equatable {
    case widget(titel: String, docId: String)
    case html(titel: String, html: String)
    case karte(Karte, titel: String)
    case datei(pfad: String, titel: String)
    case angeheftet
    case projektKarte(id: String, titel: String)

    var kennung: String {
        switch self {
        case .widget(let t, let d): return "w-\(d)-\(t)"
        case .html(let t, let h): return "h-\(h.count)-\(t)"
        case .karte(_, let t): return "k-\(t)"
        case .datei(let p, _): return "d-\(p)"
        case .angeheftet: return "a"
        case .projektKarte(let id, _): return "p-\(id)"
        }
    }

    var titel: String {
        switch self {
        case .widget(let t, _), .html(let t, _), .karte(_, let t), .datei(_, let t), .projektKarte(_, let t): return t
        case .angeheftet: return "Angeheftet"
        }
    }
}

struct WidgetDokument: Equatable {
    var html: String
    var sandboxUrl: String
    var sandboxOrigin: String?
}

@MainActor
final class AnsichtModell: ObservableObject {
    @Published private(set) var panel: PanelInhalt?
    @Published private(set) var zuletzt: PanelInhalt = .angeheftet
    @Published private(set) var pins: [AngeheftetesPin] = []
    @Published private(set) var bewertungen = BewertungsStand()
    @Published var hinweis: String?
    @Published private(set) var zurueck: [PanelInhalt] = []

    let store: SenecaStore
    var gateway = ""
    var senden: (String) -> Void = { _ in }
    var vorschlagen: (String) -> Void = { _ in }

    private var dokumente: [String: WidgetDokument] = [:]
    let agentId = Hauptagent.id

    init(store: SenecaStore) { self.store = store }

    func oeffne(_ inhalt: PanelInhalt) {
        if let p = panel, p != inhalt { zurueck.append(p) }
        zuletzt = inhalt
        withAnimation(Kurve.ease(0.26)) { panel = inhalt }
    }

    func ersetze(_ inhalt: PanelInhalt) {
        zurueck = []
        zuletzt = inhalt
        withAnimation(Kurve.ease(0.26)) { panel = inhalt }
    }

    var zeigtProjektKarte: Bool { if case .projektKarte? = panel { return true } else { return false } }

    func zurueckGehen() {
        guard let p = zurueck.popLast() else { schliesse(); return }
        zuletzt = p
        panel = p
    }

    func schliesse() {
        zurueck = []
        withAnimation(Kurve.ease(0.26)) { panel = nil }
    }

    func umschaltenAngeheftet() {
        if panel == .angeheftet { schliesse() } else { zurueck = []; oeffne(.angeheftet) }
    }

    func ladePins() async {
        guard let r = try? await store.rufe("seneca.pins") else { return }
        let neu = AngeheftetesPin.lesen(r)
        if neu != pins { withAnimation(Kurve.ease(0.3)) { pins = neu } }
    }

    func pinName(fuer k: Karte) -> String? {
        pins.first { $0.art == .karte && (($0.name == k.name && k.name != nil) || $0.karte == k) }?.name
    }

    func heftAn(_ felder: [String: Any]) async {
        do { _ = try await store.rufe("seneca.pins.setzen", params: felder); await ladePins() }
        catch { hinweis = "Das Anheften hat nicht geklappt." }
    }

    func heftAn(karte k: Karte, titel: String? = nil) async { await heftAn(AngeheftetesPin.setzen(karte: k, titel: titel)) }

    func entferne(name: String) async {
        do { _ = try await store.rufe("seneca.pins.entfernen", params: ["name": name]); await ladePins() }
        catch { hinweis = "Das Entfernen hat nicht geklappt." }
    }

    func ladeBewertungen() async {
        guard let r = try? await store.rufe("seneca.bewertungen") else { return }
        bewertungen = BewertungsStand.lesen(r)
    }

    func bewerte(kartenId: String, urteil: BewertungsStand.Urteil) async {
        do {
            _ = try await store.rufe("seneca.bewerten", params: BewertungsStand.aufruf(agentId: agentId, kartenId: kartenId, urteil: urteil))
            await ladeBewertungen()
        } catch { hinweis = "Die Bewertung hat nicht geklappt." }
    }

    func dokument(docId: String) async -> Result<WidgetDokument, WidgetFehler> {
        if let d = dokumente[docId] { return .success(d) }
        do {
            let r = try await store.rufe("canvas.document.view", params: ["docId": docId])
            guard let html = r["html"] as? String, !html.isEmpty, let url = r["sandboxUrl"] as? String else { return .failure(.weg) }
            let d = WidgetDokument(html: html, sandboxUrl: url, sandboxOrigin: (r["sandboxOrigin"] as? String).flatMap { $0.isEmpty ? nil : $0 })
            dokumente[docId] = d
            return .success(d)
        } catch {
            return .failure(store.isConnected ? .weg : .offline)
        }
    }

    func datei(pfad: String) async -> [String: Any]? { try? await store.rufe("seneca.datei", params: ["pfad": pfad]) }

    enum WidgetFehler: Error, Equatable {
        case weg, offline, fremd
        var text: String {
            switch self {
            case .weg: return "Diese Ansicht gibt es nicht mehr. Seneca hebt pro Chat die letzten 32 auf."
            case .offline: return "Keine Verbindung zu Seneca."
            case .fremd: return "Dieses Widget kommt nicht vom Gateway und wird nicht geladen."
            }
        }
    }
}
