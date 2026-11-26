import Foundation
import Combine
import EventKit
import UIKit

@MainActor
final class TagesablaufQuelle: ObservableObject {
    static let shared = TagesablaufQuelle()

    @Published private(set) var punkte: [AblaufPunkt] = []
    @Published private(set) var fertig = 0
    @Published private(set) var fuerDich: [FuerDichZeile]?
    @Published private(set) var laeuft: [LaeuftZeile]?
    @Published private(set) var entscheidungen: [Entscheidung] = []
    @Published private(set) var erledigt: Set<String> = []
    private var offen: [AntwortOffen] = AntwortOffen.laden()
    private var fragenOffen: [FrageAntwort] = FrageAntwort.laden()
    private weak var store: SenecaStore?
    private var mac: TageslaufBild?
    private var sinks = Set<AnyCancellable>()
    private var takt: Task<Void, Never>?
    private var fragt = false
    private var versucht = false
    private var letzteFrage = Date.distantPast
    private var letztesLaden = Date()
    static let abstandFrage: TimeInterval = 60
    static let abstandLaden: TimeInterval = 5 * 60

    private init() {
        mac = AblaufSpeicher.lesen()
        if ProcessInfo.processInfo.environment["SENECA_DEMO"] != "1" { entscheidungen = AblaufSpeicher.leseEntscheidungen() }
        erledigt = Set(offen.map { "entscheidung:" + $0.id }).union(FrageAntwort.versteckt(Date()))
    }

    func starten(store: SenecaStore) {
        guard self.store == nil else { return }
        self.store = store
        store.$today.map { _ in () }.merge(with: store.$kalenderLang.map { _ in () })
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rechnen() }.store(in: &sinks)
        store.$isConnected.removeDuplicates().filter { $0 }
            .sink { [weak self] _ in Task { await self?.auffrischen(sofort: true) } }.store(in: &sinks)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rechnen() }.store(in: &sinks)
        rechnen()
        takt = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, let store = self.store, store.isActive else { continue }
                await self.auffrischen(sofort: false)
                if store.isConnected, !store.demo, Date().timeIntervalSince(self.letztesLaden) >= Self.abstandLaden {
                    self.letztesLaden = Date()
                    await store.loadToday()
                }
            }
        }
    }

    func auffrischen(sofort: Bool) async {
        guard !fragt, sofort || Date().timeIntervalSince(letzteFrage) >= Self.abstandFrage else { rechnen(); return }
        fragt = true
        defer { fragt = false }
        letzteFrage = Date()
        if store?.demo != true, !Sinne.stumm || store?.isConnected == true {
            var antwort = try? await Sinne.shared.rufe("seneca.tageslauf.heute", [:], zeitlimit: 8)
            if antwort == nil, store?.isConnected == true {
                try? await Task.sleep(for: .seconds(3))
                antwort = try? await Sinne.shared.rufe("seneca.tageslauf.heute", [:], zeitlimit: 8)
            }
            if let antwort, let bild = TageslaufBild.lesen(antwort) {
                mac = bild
                AblaufSpeicher.schreiben(bild)
            }
            if let antwort { ListenModell.gemeinsam.nimm(antwort) }
            versucht = true
            await antwortenSenden()
            await Sinne.shared.nachliefern()
            if let antwort = try? await Sinne.shared.rufe("seneca.entscheidungen", [:], zeitlimit: 8), let liste = Entscheidung.liste(antwort) {
                let wartend = Set(offen.map(\.id))
                let neu = liste.filter { !wartend.contains($0.id) }
                if neu != entscheidungen { entscheidungen = neu }
                AblaufSpeicher.schreibeEntscheidungen(liste)
                let bleibt = erledigt.filter { k in !k.hasPrefix("entscheidung:") || wartend.contains(String(k.dropFirst(13))) }
                if bleibt != erledigt { erledigt = bleibt }
            }
        }
        rechnen()
    }

    func rechnen() {
        let jetzt = store?.clock() ?? Date()
        if let store, !store.demo, let bereiche = store.today?.areas?.areas {
            if GespraechsPartner.setze(bereiche: bereiche, namen: store.today?.agentNames ?? [:]) { store.chat.objectWillChange.send() }
        }
        let cal = Calendar.current
        var bild = mac
        #if DEBUG
        if store?.demo == true {
            let wahl = ProcessInfo.processInfo.environment["SENECA_DEMO_ABLAUF"] ?? ""
            var demo = wahl.isEmpty ? TageslaufBild(stand: jetzt) : TagesablaufDemo.bild(jetzt, wahl)
            demo.fuerDich = TagesablaufDemo.fuerDich(wahl, aufgaben: store?.heutigeAufgaben(jetzt: jetzt) ?? [], jetzt: jetzt)
            demo.laeuft = TagesablaufDemo.laeuft(wahl, jetzt)
            if ProcessInfo.processInfo.environment["SENECA_DEMO_HEUTE_TERMINE"] == "1" {
                demo.punkte += KalenderDemo.termine(now: jetzt, cal).map(Tagesablauf.punkt)
            }
            if ProcessInfo.processInfo.environment["SENECA_DEMO_OHNE_STAND"] == "1" { demo.fuerDich = nil; demo.laeuft = nil }
            bild = demo
        }
        #endif
        if let stand = bild?.stand, !cal.isDate(stand, inSameDayAs: jetzt) { bild = nil }
        let fenster = TerminLogik.fenster(jetzt: jetzt, cal)
        let geraet = Sinne.shared.termine(fenster.von, fenster.bis) ?? []
        var neu = Tagesablauf.punkte(mac: bild, kalender: store?.kalenderTermine ?? [], geraet: geraet, jetzt: jetzt, cal)
        let bekannt = Set(neu.map(Tagesablauf.schluessel))
        neu += Sinne.shared.orteHeute(jetzt).filter { !bekannt.contains(Tagesablauf.schluessel($0)) }
        neu.sort { $0.zeit < $1.zeit }
        if neu != punkte { punkte = neu }
        if (bild?.fertig ?? 0) != fertig { fertig = bild?.fertig ?? 0 }
        let gilt = store?.demo == true || FuerDich.gilt(stand: bild?.stand, jetzt: jetzt, versucht: versucht)
        let liste = gilt ? bild?.fuerDich : nil, lauf = gilt ? bild?.laeuft : nil
        if liste != fuerDich { fuerDich = liste }
        if lauf != laeuft { laeuft = lauf }
        #if DEBUG
        if store?.demo == true, ["1", "2", "voll", "abend"].contains(ProcessInfo.processInfo.environment["SENECA_DEMO_ABLAUF"] ?? ""), entscheidungen.isEmpty, erledigt.isEmpty { entscheidungen = TagesablaufDemo.entscheidungen }
        #endif
        AblaufSpeicher.schreibePunkte(neu)
        let stand: Date? = Sinne.shared.kalenderErlaubt ? nil : store?.kalenderStand
        if store?.today != nil || !neu.isEmpty { WidgetBridge.shared.ablauf(neu, stand: stand, now: jetzt) }
    }

    func entscheide(_ e: Entscheidung, wahl: String?, text: String?) {
        merke(AntwortOffen(id: e.id, wahl: wahl, text: text, spaeterBis: nil, erwartet: e.updatedAt))
    }

    func spaeter(_ e: Entscheidung, jetzt: Date = Date()) {
        let morgen = Calendar.current.date(byAdding: .day, value: 1, to: jetzt) ?? jetzt.addingTimeInterval(86_400)
        merke(AntwortOffen(id: e.id, wahl: nil, text: nil, spaeterBis: TageslaufZeit.tag(morgen, .current), erwartet: e.updatedAt))
    }

    func weglegen(_ ding: BrauchtDich) { erledigt.insert(ding.id) }

    func abnehmen(_ ding: BrauchtDich, karte: String, erwartet: Double?) {
        erledigt.insert(ding.id)
        Task {
            var params: [String: Any] = ["id": karte, "status": "done"]
            if let erwartet { params["expectedUpdatedAt"] = erwartet }
            do { _ = try await Sinne.shared.rufe("karte.verschieben", params, zeitlimit: 12) }
            catch { erledigt.remove(ding.id); return }
            await store?.loadToday()
        }
    }

    func beantworte(_ f: Frage, antwort: String, an: String) {
        let nachricht = "Antonio antwortet vom iPhone auf die Rückfrage „\(f.wortlaut)“\(f.karte.map { " (Karte \($0))" } ?? ""): \(antwort)."
        erledigt.insert("frage:" + f.id)
        FrageAntwort.verstecke(f.id, tage: 7)
        fragenOffen.removeAll { $0.id == f.id }
        fragenOffen.append(FrageAntwort(id: f.id, sitzung: an, nachricht: nachricht, karte: f.karte, kommentar: "Antonio (iPhone): \(antwort)."))
        FrageAntwort.sichern(fragenOffen)
        Task { await antwortenSenden() }
    }

    func spaeter(_ f: Frage) {
        erledigt.insert("frage:" + f.id)
        FrageAntwort.verstecke(f.id, tage: 1)
    }

    private func merke(_ a: AntwortOffen) {
        erledigt.insert("entscheidung:" + a.id)
        offen.removeAll { $0.id == a.id }
        offen.append(a)
        AntwortOffen.sichern(offen)
        Task { await antwortenSenden() }
    }

    private var sendet = false
    private func antwortenSenden() async {
        guard !sendet, !(offen.isEmpty && fragenOffen.isEmpty), store?.demo != true else { return }
        sendet = true
        defer { sendet = false }
        for f in fragenOffen {
            do {
                _ = try await Sinne.shared.rufe("chat.senden", ["sessionKey": f.sitzung, "agentId": AreasLogic.agentID(of: f.sitzung), "message": f.nachricht,
                                                                "idempotencyKey": "frage-\(f.id.hashValue)-\(f.nachricht.count)"], zeitlimit: 12)
                if let karte = f.karte { _ = try? await Sinne.shared.rufe("karte.kommentieren", ["id": karte, "body": f.kommentar], zeitlimit: 12) }
            } catch SenecaError.offline {
                break
            } catch {
                erledigt.remove("frage:" + f.id)
                FrageAntwort.verstecke(f.id, tage: 0)
            }
            fragenOffen.removeAll { $0.id == f.id }
            FrageAntwort.sichern(fragenOffen)
        }
        for a in offen {
            var params: [String: Any] = ["id": a.id]
            if let e = a.erwartet { params["erwartet"] = e }
            let fn: String
            if let bis = a.spaeterBis { fn = "seneca.entscheidung.spaeter"; params["bis"] = bis }
            else {
                fn = "seneca.entscheidung.treffen"
                if let w = a.wahl { params["wahl"] = w } else { params["text"] = a.text ?? "Ja" }
            }
            do {
                let antwort = try await Sinne.shared.rufe(fn, params, zeitlimit: 12)
                if let nachricht = antwort["nachricht"] as? String, !nachricht.isEmpty, let sitzung = antwort["leiterSession"] as? String, !sitzung.isEmpty {
                    _ = try? await Sinne.shared.rufe("chat.senden", ["sessionKey": sitzung, "agentId": AreasLogic.agentID(of: sitzung), "message": nachricht,
                                                                     "idempotencyKey": "entscheidung-\(a.id)-\(a.wahl ?? a.text ?? "")"], zeitlimit: 12)
                }
            } catch SenecaError.offline {
                break
            } catch {
                erledigt.remove("entscheidung:" + a.id)
            }
            offen.removeAll { $0.id == a.id }
            AntwortOffen.sichern(offen)
        }
    }

    static func punkteOhneOberflaeche(_ jetzt: Date = Date()) -> [AblaufPunkt] {
        let cal = Calendar.current
        var bild = AblaufSpeicher.lesen()
        if let stand = bild?.stand, !cal.isDate(stand, inSameDayAs: jetzt) { bild = nil }
        let fenster = TerminLogik.fenster(jetzt: jetzt, cal)
        let geraet = Sinne.shared.termine(fenster.von, fenster.bis)
        if bild == nil, geraet == nil { return AblaufSpeicher.lesePunkte().filter { $0.zeit >= cal.startOfDay(for: jetzt) } }
        return Tagesablauf.punkte(mac: bild, kalender: [], geraet: geraet ?? [], jetzt: jetzt, cal)
    }
}

enum AblaufSpeicher {
    static let bildKey = "seneca-ablauf.mac"
    static let punkteKey = "seneca-ablauf.punkte"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetStore.group) }

    static func lesen() -> TageslaufBild? {
        defaults?.data(forKey: bildKey).flatMap { try? JSONDecoder().decode(TageslaufBild.self, from: $0) }
    }
    static func schreiben(_ bild: TageslaufBild) {
        if let d = try? JSONEncoder().encode(bild) { defaults?.set(d, forKey: bildKey) }
    }
    static let entscheidungenKey = "seneca-ablauf.entscheidungen"
    static func leseEntscheidungen() -> [Entscheidung] {
        defaults?.data(forKey: entscheidungenKey).flatMap { try? JSONDecoder().decode([Entscheidung].self, from: $0) } ?? []
    }
    static func schreibeEntscheidungen(_ liste: [Entscheidung]) {
        if let d = try? JSONEncoder().encode(liste), d != defaults?.data(forKey: entscheidungenKey) { defaults?.set(d, forKey: entscheidungenKey) }
    }
    static func lesePunkte() -> [AblaufPunkt] {
        defaults?.data(forKey: punkteKey).flatMap { try? JSONDecoder().decode([AblaufPunkt].self, from: $0) } ?? []
    }
    static func schreibePunkte(_ punkte: [AblaufPunkt]) {
        if let d = try? JSONEncoder().encode(punkte), d != defaults?.data(forKey: punkteKey) { defaults?.set(d, forKey: punkteKey) }
    }
}

struct AntwortOffen: Codable, Equatable {
    var id: String
    var wahl: String?
    var text: String?
    var spaeterBis: String?
    var erwartet: Double?

    private static let key = "seneca-pocket.antworten-offen"
    static func laden() -> [AntwortOffen] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([AntwortOffen].self, from: $0) } ?? []
    }
    static func sichern(_ liste: [AntwortOffen]) {
        if let d = try? JSONEncoder().encode(liste) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct FrageAntwort: Codable, Equatable {
    var id: String
    var sitzung: String
    var nachricht: String
    var karte: String?
    var kommentar: String

    private static let key = "seneca-pocket.fragen-offen"
    private static let wegKey = "seneca-pocket.fragen-versteckt"
    static func laden() -> [FrageAntwort] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([FrageAntwort].self, from: $0) } ?? []
    }
    static func sichern(_ liste: [FrageAntwort]) {
        if let d = try? JSONEncoder().encode(liste) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func versteckt(_ jetzt: Date) -> Set<String> {
        let bis = UserDefaults.standard.dictionary(forKey: wegKey) as? [String: Double] ?? [:]
        return Set(bis.filter { $0.value > jetzt.timeIntervalSince1970 }.map { "frage:" + $0.key })
    }
    static func verstecke(_ id: String, tage: Int, jetzt: Date = Date()) {
        var bis = (UserDefaults.standard.dictionary(forKey: wegKey) as? [String: Double] ?? [:]).filter { $0.value > jetzt.timeIntervalSince1970 }
        let morgen = Calendar.current.startOfDay(for: jetzt).addingTimeInterval(Double(tage) * 86_400)
        bis[id] = tage > 0 ? morgen.timeIntervalSince1970 : nil
        UserDefaults.standard.set(bis, forKey: wegKey)
    }
}

#if DEBUG
enum TagesablaufDemo {
    static let alsEntscheidung = ["a-e7": "Soll Hermes mit Instagram anfangen?"]

    static func fuerDich(_ wahl: String, aufgaben: [SenecaTask], jetzt: Date) -> [FuerDichZeile] {
        var zeilen: [FuerDichZeile] = []
        if wahl == "1" {
            zeilen.append(FuerDichZeile(id: "antwort:Miriam", art: .antwort, satz: "Passt dir 19 Uhr, oder lieber etwas später?", wortlaut: "Passt dir 19 Uhr, oder lieber etwas später?",
                                        von: "Miriam", bereich: "Miriam", seit: Calendar.current.date(bySettingHour: 14, minute: 10, second: 0, of: jetzt), quelle: "whatsapp"))
        }
        if ["1", "2", "voll", "abend"].contains(wahl) {
            let saetze = ["demo-1": "Soll die schnellere Prüfung für den Shop eingeschaltet werden?"]
            zeilen += entscheidungen.map { FuerDichZeile(id: $0.id, art: .entscheidung, satz: saetze[$0.id] ?? $0.frage, wortlaut: $0.frage, bereich: $0.bereich) }
        }
        zeilen += aufgaben.filter { !$0.isDone && alsEntscheidung[$0.id] != nil }.map {
            FuerDichZeile(id: $0.id, art: .entscheidung, satz: alsEntscheidung[$0.id] ?? $0.title, wortlaut: AufgabenLogic.anzeigeTitel($0.title), bereich: $0.projektName ?? "")
        }
        let fragen = Set(zeilen.map(\.id)).union(alsEntscheidung.keys)
        return zeilen + aufgaben.filter { !fragen.contains($0.id) }.map { FuerDichZeile(id: $0.id, art: .aufgabe, satz: $0.title, wortlaut: $0.title) }
    }

    static func laeuft(_ wahl: String, _ jetzt: Date) -> [LaeuftZeile] {
        let newsletter = LaeuftZeile(id: "s2", art: .arbeit, satz: "Der Newsletter für Oktober wird gerade entworfen.", wortlaut: "Newsletter Oktober", von: "Newsletter", seit: jetzt.addingTimeInterval(-9 * 60))
        switch wahl {
        case "voll", "abend":
            return [LaeuftZeile(id: "d1", art: .auftrag, satz: "Die Ansagen für verpasste Anrufe werden neu geschnitten.", wortlaut: "Ansagen neu schneiden", von: "Hermes-Produkt", seit: jetzt.addingTimeInterval(-28 * 60),
                                stand: "Gemessen um 13:40 Uhr: Zwei von drei Ansagen sind neu geschnitten, die dritte läuft. Die fertigen Ansagen sind schon auf dem Server und werden bei neuen Anrufen benutzt.", runde: 2, zuletzt: jetzt.addingTimeInterval(-4 * 60)),
                    LaeuftZeile(id: "d2", art: .arbeit, satz: "Die Preise für Anrufe ins Ausland werden gerade nachgerechnet.", wortlaut: "Preise Ausland", von: "Hermes-Produkt", seit: jetzt.addingTimeInterval(-9 * 60)),
                    LaeuftZeile(id: "d3", art: .pruefung, satz: "Die Auftritte von drei Wettbewerbern sind ausgewertet.", wortlaut: "Wettbewerber auswerten", von: "Branding", seit: jetzt.addingTimeInterval(-41 * 60)),
                    newsletter]
        case "1", "2", "leer": return [newsletter]
        default: return []
        }
    }

    static func routinen(_ um: (Int, Int, Int) -> Date, _ tag: Int) -> [AblaufPunkt] {
        [AblaufPunkt(zeit: um(5, 0, tag), ende: um(5, 15, tag), titel: "Aufwachen", routine: true), AblaufPunkt(zeit: um(5, 30, tag), ende: um(6, 30, tag), titel: "Laufen", routine: true),
         AblaufPunkt(zeit: um(6, 30, tag), ende: um(7, 30, tag), titel: "Lesen", routine: true), AblaufPunkt(zeit: um(8, 0, tag), ende: um(8, 15, tag), titel: "To-dos sichten", routine: true)]
    }

    static func bild(_ jetzt: Date, _ wahl: String = "1") -> TageslaufBild {
        let cal = Calendar.current
        let tag = cal.startOfDay(for: jetzt)
        func um(_ h: Int, _ m: Int, _ tage: Int = 0) -> Date { cal.date(byAdding: .minute, value: h * 60 + m + tage * 1440, to: tag)! }
        switch wahl {
        case "voll":
            return TageslaufBild(stand: jetzt, punkte: routinen(um, 0) + [
                AblaufPunkt(zeit: um(8, 40), art: "ort_ankunft", titel: "Vodafone Campus"),
                AblaufPunkt(zeit: um(9, 30), ende: um(10, 15), art: "meeting", titel: "Wochenstart im Team"),
                AblaufPunkt(zeit: um(10, 15), ende: um(11, 0), titel: "Abstimmung zum Angebot"),
                AblaufPunkt(zeit: um(12, 15), ende: um(12, 57), art: "training", titel: "Laufen"),
                AblaufPunkt(zeit: um(13, 30), ende: um(14, 30), titel: "Lern-Café vorbereiten"),
                AblaufPunkt(zeit: um(15, 0), ende: um(15, 45), titel: "Rückruf Steuerberater"),
                AblaufPunkt(zeit: um(16, 0), ende: um(16, 30), titel: "Zahnarzt", ort: "Praxis am Markt, Hauptstraße 12"),
                AblaufPunkt(zeit: um(17, 30), ende: um(18, 0), titel: "Paket abholen"),
                AblaufPunkt(zeit: um(19, 0), ende: um(20, 30), titel: "Abendessen mit Miriam", ort: "Zur Post"),
            ] + routinen(um, 1), ort: AblaufOrt(name: "Vodafone Campus", seit: um(8, 40)), fertig: 3)
        case "leer":
            return TageslaufBild(stand: jetzt, punkte: [AblaufPunkt(zeit: um(16, 0), ende: um(16, 45), titel: "Zahnarzt", ort: "Praxis am Markt, Hauptstraße 12")] + routinen(um, 1))
        case "abend":
            return TageslaufBild(stand: jetzt, punkte: [
                AblaufPunkt(zeit: um(9, 30), ende: um(10, 15), art: "meeting", titel: "Wochenstart im Team"),
                AblaufPunkt(zeit: um(15, 0), ende: um(15, 45), titel: "Abstimmung zum Angebot"),
                AblaufPunkt(zeit: um(18, 10), art: "ort_ankunft", titel: "Zuhause"),
                AblaufPunkt(zeit: um(19, 0), ende: um(20, 30), titel: "Abendessen mit Miriam", ort: "Zur Post"),
            ] + routinen(um, 1) + [AblaufPunkt(zeit: um(9, 0, 1), ende: um(10, 0, 1), titel: "Lern-Café")], fertig: 3)
        default: break
        }
        return TageslaufBild(stand: jetzt, punkte: [
            AblaufPunkt(zeit: um(8, 40), art: "ort_ankunft", titel: "Vodafone Campus"),
            AblaufPunkt(zeit: um(9, 30), ende: um(10, 15), art: "meeting", titel: "Wochenstart im Team"),
            AblaufPunkt(zeit: um(12, 15), ende: um(12, 57), art: "training", titel: "Laufen"),
            AblaufPunkt(zeit: um(15, 0), ende: um(15, 45), titel: "Abstimmung zum Angebot"),
            AblaufPunkt(zeit: um(17, 30), ende: um(18, 0), titel: "Zahnarzt", ort: "Praxis am Markt, Hauptstraße 12"),
            AblaufPunkt(zeit: um(19, 0), ende: um(20, 30), titel: "Abendessen mit Miriam", ort: "Zur Post"),
            AblaufPunkt(zeit: um(9, 0, 1), ende: um(10, 0, 1), titel: "Lern-Café"),
        ], ort: AblaufOrt(name: "Vodafone Campus", seit: um(8, 40)), fertig: 3)
    }

    static let entscheidungen = [
        Entscheidung(id: "demo-1", frage: "Soll der Cache-Fix für den Shop gemergt und deployt werden?",
                     kurz: "Die Prüfung der Bestellungen dauert jetzt zwei statt neun Minuten. Die Änderung ist geprüft und wartet nur auf dein Ja.", bereich: "Shop", gestelltAm: 1),
        Entscheidung(id: "demo-2", frage: "Welche Übersicht soll die Startseite zuerst bekommen?", optionen: [.init(key: "A", titel: "Wartet auf dich"), .init(key: "B", titel: "Projekte")],
                     empfohlen: "A", empfehlung: "Zuerst das, was auf dich wartet.", bereich: "Seneca", gestelltAm: 2),
        Entscheidung(id: "demo-3", frage: "Sollen Sicherungen erst nach 30 statt nach 7 Tagen gelöscht werden?", bereich: "Technik", gestelltAm: 3),
    ]
}
#endif
