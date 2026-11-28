import Foundation
import Testing
@testable import SenecaVerbindung

@Suite("PF11 App und Server passen")
@MainActor
struct PF11AppUndServerPassen {
    func standDaten(_ revision: Int, schema: Int = 1, frage: String? = nil, unveraendert: Bool = false) -> Data {
        var s: [String: Any] = ["schema": schema, "revision": revision, "jetzt": 1_000]
        if unveraendert { s["unveraendert"] = true } else {
            s["zaehler"] = ["braucht": frage == nil ? 0 : 1]
            s["braucht_dich"] = frage.map { [["id": $0, "text": "Angebot freigeben?"]] } ?? []
        }
        return try! JSONSerialization.data(withJSONObject: s)
    }

    func ordner() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test("Wiederverbinden: Abstand wächst von 1 s bis 30 s, nie im 4-s-Takt")
    func abstand() {
        var w = Wiederverbinden()
        var warten: [Double] = []
        for _ in 0..<10 { if case .warte(let s) = w.nachFehler(anmeldung: false, zufall: 1) { warten.append(s) } }
        #expect(warten == [1, 2, 4, 8, 16, 30, 30, 30, 30, 30])
        for _ in 0..<50 { if case .warte(let s) = w.nachFehler(anmeldung: false) { #expect(s >= 1 && s <= 30) } }
        w.verbunden()
        #expect(w.nachFehler(anmeldung: false, zufall: 1) == .warte(1))
    }

    @Test("Anmeldefehler: nach drei Versuchen Neu koppeln statt Sturm")
    func anmeldefehler() {
        var w = Wiederverbinden()
        #expect(Wiederverbinden.istAnmeldefehler("AUTH_DEVICE_TOKEN_MISMATCH"))
        #expect(w.nachFehler(anmeldung: true, zufall: 0) != .neuKoppeln)
        #expect(w.nachFehler(anmeldung: true, zufall: 0) != .neuKoppeln)
        #expect(w.nachFehler(anmeldung: true, zufall: 0) == .neuKoppeln)
    }

    @Test("Stand: neuere Revision ersetzt alles, ältere und unveränderte werden verworfen, Kaltstart zeigt den letzten")
    func standErsetzt() {
        let o = ordner()
        let s = StandSpeicher(datei: o.appendingPathComponent("stand.json"))
        #expect(s.uebernehme(standDaten(5, frage: "f1")))
        #expect(s.stand?.braucht_dich?.first?.id == "f1")
        #expect(!s.uebernehme(standDaten(4, frage: "alt")))
        #expect(!s.uebernehme(standDaten(5, unveraendert: true)))
        #expect(s.uebernehme(standDaten(6)))
        #expect(s.stand?.braucht_dich?.isEmpty == true)
        let kalt = StandSpeicher(datei: o.appendingPathComponent("stand.json"))
        #expect(kalt.revision == 6)
    }

    @Test("Version passt nicht: kein halber Stand, keine schreibende Handlung")
    func versionPasstNicht() {
        let s = StandSpeicher(datei: nil)
        #expect(s.uebernehme(standDaten(3)))
        #expect(!s.uebernehme(standDaten(9, schema: 2, frage: "neu")))
        #expect(s.passtNicht)
        #expect(s.revision == 3)
        let korb = Ausgangskorb(datei: nil, geraet: "mac")
        #expect(korb.neu(art: "todo.erledigt", ziel: "t1", gesehen: 3, verbunden: true, passtNicht: s.passtNicht) == nil)
    }

    @Test("Getrennt: Korb geht genau einmal, mit fester Kennung und gesehener Revision; Fragen warten nicht")
    func korbGenauEinmal() async throws {
        let o = ordner()
        let korb = Ausgangskorb(datei: o.appendingPathComponent("korb.json"), geraet: "iphone")
        #expect(korb.neu(art: "frage.antwort", ziel: "f1", wert: .objekt(["wahl": .text("ja")]), gesehen: 7, verbunden: false, passtNicht: false) == nil)
        let h = try #require(korb.neu(art: "todo.erledigt", ziel: "t1", gesehen: 7, verbunden: false, passtNicht: false))
        #expect(korb.istGestrichelt(h.kennung))
        #expect(h.gesehen_revision == 7)
        let nachNeustart = Ausgangskorb(datei: o.appendingPathComponent("korb.json"), geraet: "iphone")
        #expect(nachNeustart.offen.map(\.kennung) == [h.kennung])
        var gesendet: [String] = []
        nachNeustart.senden { h in gesendet.append(h.kennung); return ("angenommen", 8) }
        nachNeustart.senden { h in gesendet.append(h.kennung); return ("angenommen", 8) }
        for _ in 0..<50 where !nachNeustart.offen.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gesendet == [h.kennung])
        #expect(!nachNeustart.istGestrichelt(h.kennung))
        #expect(nachNeustart.ergebnisse[h.kennung] == .angenommen)
    }

    @Test("Antworten des Servers: schon beantwortet trägt Wahl, Gerät und Zeit")
    func ergebnisse() {
        #expect(HandlungsErgebnis("schon_beantwortet:ja,uhr,1764160140000") == .schonBeantwortet(wahl: "ja", geraet: "uhr", um: 1_764_160_140_000))
        #expect(HandlungsErgebnis("abgelehnt:zu_spaet") == .abgelehnt("zu_spaet"))
        #expect(HandlungsErgebnis("doppelt") == .doppelt)
        #expect(HandlungsErgebnis("ueberholt") == .ueberholt)
    }

    @Test("Eigene Gerätekennung: Mac, iPhone und Simulator melden sich verschieden, keiner mit admin")
    func profile() {
        let alle = [ClientProfil.mac, .iphone, .simulator]
        #expect(Set(alle.map { $0.kennung + "|" + $0.anzeigename }).count == 3)
        #expect(alle.allSatisfy { !$0.scopes.contains("operator.admin") })
        #expect(ClientProfil.mac.scopes.contains("operator.pairing") && !ClientProfil.iphone.scopes.contains("operator.pairing"))
    }

    @Test("Statistik vom Server: Kennzahlen kommen vollständig in der App an")
    func statistikKennzahlen() throws {
        let datei = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/SenecaKern/Beispiel/Beispiel-Statistik.json")
        let k = try #require(try JSONDecoder().decode(SenecaStatistik.self, from: Data(contentsOf: datei)).kennzahlen)
        #expect(k.wochen.count == 52 && k.lauf.km.count == 52 && k.kraft.tage.count == 52)
        #expect(k.lauf.laengster?.first?.alsZahl == 30.4 && k.lauf.aufbau.first?.first?.alsText == k.wochen.last)
        #expect(k.kraft.bestwerte["Rudern"]?.compactMap(\.alsZahl) == [57, 45, 8])
        #expect(k.koerper.nacht.last?[7].alsZahl == 69)
    }

    @Test("Fragen zählen aus einer Quelle: dringende und Bündel, beantwortete nicht")
    func offeneFragenEineQuelle() throws {
        let frage = { (id: String) -> [String: Any] in ["id": id, "text": "Frage?"] }
        let beantwortet: [String: Any] = ["id": "c", "text": "Frage?", "antwort": ["wahl": "ja", "um": 1]]
        let s: [String: Any] = ["schema": 1, "revision": 1, "jetzt": 1, "braucht_dich": [frage("a")], "buendel": ["fragen": [frage("b"), beantwortet]]]
        let stand = try JSONDecoder().decode(SenecaStand.self, from: JSONSerialization.data(withJSONObject: s))
        #expect(stand.alleFragen.count == 3)
        #expect(stand.offeneFragen.map(\.id) == ["a", "b"])
    }
}
