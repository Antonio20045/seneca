import SwiftUI
import AppKit
import AVFoundation
import CoreAudio
import Combine

@MainActor
final class MeetingDienst: ObservableObject {
    static let gemeinsam = MeetingDienst()

    enum Zustand: Equatable {
        case ruht
        case startet
        case nimmtAuf
        case wertAus(String)
        case fertig
        case fehler(String)
    }

    struct Antwort: Identifiable, Equatable {
        let id = UUID()
        var frage: String
        var text: String
        var laedt: Bool
    }

    struct Ablage {
        var datei: URL
        var ergebnis: MeetingErgebnis
    }

    @Published private(set) var zustand: Zustand = .ruht
    @Published private(set) var dauer: TimeInterval = 0
    @Published private(set) var pegel: Double = 0
    @Published private(set) var live: [MeetingSegment] = []
    @Published private(set) var antworten: [Antwort] = []
    @Published private(set) var ablage: Ablage?
    @Published private(set) var hinweise: [String] = []
    @Published private(set) var ollama: OllamaStand?
    @Published private(set) var vorschlag: String?
    @Published private(set) var uebernahme = ""
    @Published private(set) var marken: [TimeInterval] = []
    @Published private(set) var uebernommen = 0
    @Published private(set) var fruehere: [MeetingAufnahme] = []

    var uebersicht: OverviewStore?
    var oeffneFenster: (() -> Void)?

    let prozess = OllamaProzessEcht()
    private lazy var starter = OllamaStarter(prozess: prozess, vorgabeModell: ProcessInfo.processInfo.environment["SENECA_MEETING_MODELL"] ?? "gemma3:12b")
    private var mikrofon: MeetingMikrofon?
    private var systemton: MeetingSystemton?
    private var schreiberMikro: MeetingSchreiber?
    private var schreiberSystem: MeetingSchreiber?
    private var beginn = Date()
    private var aufnahmeOrdner: URL?
    private var liveKanal: [Int: [MeetingSegment]] = [:]
    private var takt: Task<Void, Never>?
    private var wache: Task<Void, Never>?
    private var micSeit: Date?
    private var schonGefragt = false
    private var ollamaTask: Task<OllamaStand, Never>?
    private var liveLaeuft = false
    private var titelVorgabe: String?
    private var ablageAufnahme: URL?
    private var zusammenfassung: Task<MeetingAnalyse, Error>?
    private var abbruch = false
    let protokoll = MeetingProtokoll(datei: MacPfade.datenOrdner?.appendingPathComponent("meeting-log.jsonl"))
    private var aufnahmeName: String? { aufnahmeOrdner?.lastPathComponent }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [prozess] _ in prozess.beendeKind() }
    }

    var nimmtAuf: Bool { zustand == .nimmtAuf }
    var beschaeftigt: Bool { if case .ruht = zustand { return false }; if case .fertig = zustand { return false }; if case .fehler = zustand { return false }; return true }

    static var ordner: URL {
        if let p = ProcessInfo.processInfo.environment["SENECA_MEETING_ORDNER"], !p.isEmpty { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true) }
        if MacPfade.profil != .echt, let d = MacPfade.datenOrdner { return d.appendingPathComponent("meetings", isDirectory: true) }
        return MeetingDokument.ordnerStandard()
    }

    static var aufnahmenOrdner: URL? {
        if let p = ProcessInfo.processInfo.environment["SENECA_MEETING_AUFNAHMEN"], !p.isEmpty { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true) }
        return MacPfade.datenOrdner?.appendingPathComponent("meetings-aufnahmen", isDirectory: true)
    }

    func starteWache() {
        guard wache == nil, !Hintergrund.aktiv else { return }
        wache = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.pruefeKonferenz()
            }
        }
    }

    private func pruefeKonferenz() {
        let laeuft = Self.mikrofonLaeuft()
        if laeuft { if micSeit == nil { micSeit = Date() } } else { micSeit = nil; schonGefragt = false; if vorschlag != nil { vorschlag = nil } }
        let apps = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let v = MeetingErkennung.vorschlag(mikrofonSeit: micSeit, laufendeApps: apps, nimmtAuf: beschaeftigt, schonGefragt: schonGefragt, jetzt: Date())
        if let v, vorschlag != v { vorschlag = v }
        if vorschlag != nil, beschaeftigt { vorschlag = nil }
    }

    func vorschlagVerwerfen() { schonGefragt = true; vorschlag = nil }

    nonisolated static func mikrofonLaeuft() -> Bool {
        var geraet = AudioDeviceID(0)
        var groesse = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &groesse, &geraet) == noErr else { return false }
        var an: UInt32 = 0
        groesse = UInt32(MemoryLayout<UInt32>.size)
        a.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(geraet, &a, 0, nil, &groesse, &an) == noErr && an != 0
    }

    func merke() { if nimmtAuf { marken.append(dauer) } }

    func umschalten() { if nimmtAuf { Task { await stoppe() } } else { Task { await starte() } } }

    func starte() async {
        guard !beschaeftigt else { return }
        zustand = .startet
        vorschlag = nil; schonGefragt = true
        hinweise = []; live = []; liveKanal = [:]; antworten = []; ablage = nil; uebernahme = ""; uebernommen = 0; dauer = 0
        guard await DiktatAufnahme.freigabe() else { zustand = .fehler((DiktatAufnahme.Fehler.keineFreigabe).errorDescription ?? "Kein Zugriff auf das Mikrofon."); return }
        guard let basis = Self.aufnahmenOrdner else { zustand = .fehler("Der Ordner für Aufnahmen lässt sich nicht anlegen."); return }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let ordner = basis.appendingPathComponent(f.string(from: Date()), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let sm = try MeetingSchreiber(url: ordner.appendingPathComponent("mikrofon.wav"))
            let mik = MeetingMikrofon()
            mik.pegel = { [weak self] p in Task { @MainActor in self?.pegel = Double(p) } }
            mik.fehlgeschlagen = { [weak self] nachricht in Task { @MainActor in await self?.beendeAufnahme(abbruch: nachricht) } }
            try mik.starte(in: sm)
            mikrofon = mik; schreiberMikro = sm; aufnahmeOrdner = ordner
            pruefeStilleNachStart(sm, geraeteName: mik.geraeteName, start: Date())
        } catch {
            protokoll.schreibe("start", aufnahme: ordner.lastPathComponent, fehler: error.localizedDescription)
            zustand = .fehler("Das Mikrofon ließ sich nicht starten: \(error.localizedDescription)"); return
        }
        beginn = Date()
        marken = []
        await starteSystemton(in: ordner)
        zustand = .nimmtAuf
        protokoll.schreibe("start", aufnahme: ordner.lastPathComponent, zahlen: ["systemton": systemton == nil ? 0 : 1])
        ollamaTask = Task { [starter] in await starter.sichereBereit() }
        Task { if let t = await ollamaTask?.value { ollama = t } }
        takt = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.dauer = Date().timeIntervalSince(self.beginn)
                n += 1
                if n % 20 == 0 { await self.aktualisiereLive() }
            }
        }
        Task { await DiktatDienst.gemeinsam.waermeVor() }
    }

    private func starteSystemton(in ordner: URL) async {
        if !MeetingSystemton.freigegeben() {
            MeetingSystemton.frageFreigabe()
            hinweise.append("Systemton nicht aufgenommen: Für „Seneca Nativ“ fehlt die Freigabe „Bildschirm- und Systemaudioaufnahme“ (Systemeinstellungen, Datenschutz & Sicherheit). Aufgenommen wird nur das Mikrofon.")
            return
        }
        do {
            let s = try MeetingSchreiber(url: ordner.appendingPathComponent("systemton.wav"))
            let st = MeetingSystemton()
            st.abgebrochen = { [weak self] e in Task { @MainActor in
                guard let self, self.nimmtAuf else { return }
                self.hinweise.append("Der Systemton brach ab (\(e.localizedDescription)). Ab da ist nur noch das Mikrofon aufgenommen.")
                self.protokoll.schreibe("systemton-abbruch", aufnahme: self.aufnahmeName, fehler: e.localizedDescription)
            } }
            try await st.starte(in: s)
            systemton = st; schreiberSystem = s
        } catch {
            hinweise.append("Systemton nicht aufgenommen: \(error.localizedDescription). Aufgenommen wird nur das Mikrofon.")
        }
    }

    func stoppe() async { await beendeAufnahme(abbruch: nil) }

    private func beendeAufnahme(abbruch: String?) async {
        guard nimmtAuf else { return }
        takt?.cancel(); takt = nil
        let gesamt = Date().timeIntervalSince(beginn)
        zustand = .wertAus("Beende die Aufnahme …")
        mikrofon?.beende(); mikrofon = nil
        await systemton?.beende(); systemton = nil
        pegel = 0
        schreiberMikro?.schliesse(); schreiberSystem?.schliesse()
        if let abbruch { hinweise.append(abbruch + " Ausgewertet ist, was bis dahin aufgenommen war.") }
        let e = MeetingEingabe(mikro: schreiberMikro, system: schreiberSystem, beginn: beginn, dauer: gesamt, titelVorgabe: nil, vorHinweise: hinweise,
                               aufnahme: aufnahmeName)
        if let o = aufnahmeOrdner {
            MeetingArchiv.schreibeMeta(.init(beginn: beginn, dauer: gesamt,
                                             versatzMikro: schreiberMikro?.ersterPuffer.map { $0.timeIntervalSince(beginn) } ?? 0,
                                             versatzSystem: schreiberSystem?.ersterPuffer.map { $0.timeIntervalSince(beginn) } ?? 0, hinweise: hinweise), in: o)
        }
        protokoll.schreibe("stopp", aufnahme: aufnahmeName, dauer: gesamt, fehler: abbruch == nil ? nil : "Mikrofon abgebrochen")
        schreiberMikro = nil; schreiberSystem = nil
        await verarbeite(e, probe: false)
    }

    private func pruefeStilleNachStart(_ s: MeetingSchreiber, geraeteName: String, start: Date) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(MeetingStilleErkennung.frist))
            guard let self, self.nimmtAuf, self.schreiberMikro === s else { return }
            if MeetingStilleErkennung.stillGebliebene(ersterPuffer: s.ersterPuffer, start: start, jetzt: Date()) {
                self.hinweise.append("Kein Ton vom Mikrofon („\(geraeteName)“).")
            }
        }
    }

    private func aktualisiereLive() async {
        guard !liveLaeuft, DiktatDienst.gemeinsam.modellBereit else { return }
        liveLaeuft = true; defer { liveLaeuft = false }
        for (kanal, s) in [(1, schreiberMikro), (2, schreiberSystem)] {
            guard let s, let r = s.entnimm(mindestens: 16_000 * 3) else { continue }
            let versatz = (s.ersterPuffer ?? beginn).timeIntervalSince(beginn)
            guard let w = try? await DiktatDienst.gemeinsam.erkenner.woerter(proben: r.proben), !w.isEmpty else { continue }
            let verschoben = w.map { MeetingWort(text: $0.text, start: $0.start + r.ab + versatz, ende: $0.ende + r.ab + versatz) }
            liveKanal[kanal, default: []] += MeetingTranskript.segmente(woerter: verschoben, abschnitte: nil, grund: kanal)
        }
        if !liveKanal.isEmpty { live = MeetingTranskript.zusammenfuehren(Array(liveKanal.values)) }
    }

    func frage(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let a = Antwort(frage: t, text: "", laedt: true)
        antworten.append(a)
        let i = antworten.count - 1
        func setze(_ s: String) { if antworten.indices.contains(i) { antworten[i].text = s; antworten[i].laedt = false } }
        await aktualisiereLive()
        guard let klient = await ollamaKlient() else { setze(ollama?.meldung ?? "Ollama ist nicht bereit."); return }
        do { setze(try await MeetingAuswertung(klient: klient).nachfrage(t, segmente: live)) }
        catch { setze("Das ging nicht: \(error.localizedDescription)") }
    }

    private func ollamaKlient() async -> OllamaKlient? {
        let stand: OllamaStand
        if let t = ollamaTask { stand = await t.value } else { stand = await starter.sichereBereit() }
        ollama = stand
        if case .bereit(let m, _) = stand {
            return OllamaKlient.gemeinsam(modell: m, geladen: await starter.geladenerKontext(modell: m))
        }
        ollamaTask = nil
        return nil
    }

    struct MeetingEingabe {
        var mikro: MeetingSchreiber?
        var system: MeetingSchreiber?
        var beginn: Date
        var dauer: TimeInterval
        var titelVorgabe: String?
        var vorHinweise: [String]
        var mikroDatei: URL? = nil
        var systemDatei: URL? = nil
        var versatzMikro: Double? = nil
        var versatzSystem: Double? = nil
        var aufnahme: String? = nil
        var ersetzt: URL? = nil
    }

    @discardableResult
    func verarbeite(_ e: MeetingEingabe, probe: Bool, ordner: URL? = nil) async -> Ablage? {
        var hinweise = e.vorHinweise
        let name = e.aufnahme
        titelVorgabe = e.titelVorgabe
        let erkenner = DiktatDienst.gemeinsam.erkenner
        zustand = .wertAus("Erkenne das Gespräch …")
        if !DiktatDienst.gemeinsam.modellBereit { await DiktatDienst.gemeinsam.waermeVor() }
        guard DiktatDienst.gemeinsam.modellBereit else {
            let grund = DiktatDienst.gemeinsam.modellFehler ?? "Das Sprachmodell ist nicht geladen."
            protokoll.schreibe("mitschrift", aufnahme: name, fehler: grund)
            zustand = .fehler(grund + " Der Ton ist gesichert und lässt sich unter „Frühere Aufnahmen“ später auswerten.")
            ladeFruehere()
            return nil
        }

        let mikroURL = e.mikroDatei ?? e.mikro?.url
        let systemURL = e.systemDatei ?? e.system?.url
        let versatzMikro = e.versatzMikro ?? e.mikro?.ersterPuffer.map { $0.timeIntervalSince(e.beginn) } ?? 0
        let versatzSystem = e.versatzSystem ?? e.system?.ersterPuffer.map { $0.timeIntervalSince(e.beginn) } ?? 0
        let trennungDa = MeetingSprechertrennung.modelleDa()
        var listen: [[MeetingSegment]] = []
        var rollen: [Int: String] = [:]
        var gescheitert = 0

        func kanal(_ url: URL?, was: String, grund: Int, versatz: Double, mitTrennung: Bool) async {
            guard let url else { return }
            let kurz = was.lowercased()
            if (try? MeetingWav.repariere(url)) == true { protokoll.schreibe("wav-repariert-" + kurz, aufnahme: name) }
            let t0 = Date()
            let w: [MeetingWort]
            do {
                w = try await erkenner.woerter(datei: url).map { MeetingWort(text: $0.text, start: $0.start + versatz, ende: $0.ende + versatz) }
                protokoll.schreibe("mitschrift-" + kurz, aufnahme: name, dauer: Date().timeIntervalSince(t0),
                                   zahlen: ["woerter": Double(w.count), "tonSekunden": (MeetingWav.dauer(url) ?? 0).rounded()])
            } catch {
                gescheitert += 1
                hinweise.append("\(was): Die Erkennung schlug fehl (\(error.localizedDescription)). Dieser Kanal fehlt in der Mitschrift.")
                protokoll.schreibe("mitschrift-" + kurz, aufnahme: name, dauer: Date().timeIntervalSince(t0), fehler: error.localizedDescription)
                return
            }
            var abschnitte: [SprecherAbschnitt]?
            if mitTrennung && trennungDa && !w.isEmpty {
                let t1 = Date()
                do {
                    abschnitte = try await MeetingSprechertrennung.trenne(datei: url).map { SprecherAbschnitt(kennung: $0.kennung, start: $0.start + versatz, ende: $0.ende + versatz) }
                    protokoll.schreibe("sprechertrennung-" + kurz, aufnahme: name, dauer: Date().timeIntervalSince(t1))
                } catch {
                    hinweise.append("\(was): Die Sprechertrennung schlug fehl (\(error.localizedDescription)); die Stimmen dieses Kanals sind nicht getrennt.")
                    protokoll.schreibe("sprechertrennung-" + kurz, aufnahme: name, dauer: Date().timeIntervalSince(t1), fehler: error.localizedDescription)
                }
            }
            listen.append(MeetingTranskript.segmente(woerter: w, abschnitte: abschnitte, grund: grund))
        }
        await kanal(mikroURL, was: "Mikrofon", grund: 1, versatz: versatzMikro, mitTrennung: systemURL == nil)
        await kanal(systemURL, was: "Systemton", grund: 2, versatz: versatzSystem, mitTrennung: true)
        let segmente = MeetingTranskript.zusammenfuehren(listen)
        if mikroURL != nil && systemURL != nil { rollen[1] = "Mikrofon, Antonio" }
        for n in MeetingTranskript.sprecherAnzahl(segmente) where n >= 2 && systemURL != nil { rollen[n] = "Systemton" }
        if systemURL == nil, !trennungDa {
            hinweise.append("Nur das Mikrofon, und die Modelle der Sprechertrennung liegen nicht lokal: Alle Beiträge stehen unter „Sprecher 1“.")
        } else if systemURL != nil, !trennungDa {
            hinweise.append("Mehrere Stimmen im Systemton sind nicht getrennt (Modelle der Sprechertrennung fehlen lokal): Die Gegenseite steht als „Sprecher 2“.")
        }
        if segmente.isEmpty { hinweise.append(gescheitert > 0 ? "Es ließ sich nichts erkennen." : "Im Gespräch war nichts zu erkennen.") }
        live = segmente

        var titel = "Meeting"
        if let v = e.titelVorgabe { titel = v + ": " + titel }
        let erg = MeetingErgebnis(titel: titel, beginn: e.beginn, dauer: e.dauer, segmente: segmente, zusammenfassung: "", aufgaben: [], rollen: rollen,
                                  hinweise: hinweise, stand: segmente.isEmpty ? .vollstaendig : .laeuft, aufnahme: name)
        let datei: URL
        let alt = e.ersetzt.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        if alt != nil, segmente.isEmpty {
            protokoll.schreibe("datei-mitschrift", aufnahme: name, fehler: "Nichts erkannt, vorhandene Datei behalten")
            self.hinweise = hinweise
            zustand = .fehler("Beim erneuten Auswerten ließ sich nichts erkennen. Die vorhandene Datei bleibt unverändert.")
            ladeFruehere()
            return nil
        }
        do {
            if let alt { datei = try MeetingDokument.nachtrage(erg, datei: alt) }
            else { datei = try MeetingDokument.schreibe(erg, in: ordner ?? Self.ordner) }
        } catch {
            protokoll.schreibe("datei-mitschrift", aufnahme: name, fehler: Self.dateiFehler(error))
            zustand = .fehler("Die Datei ließ sich nicht schreiben: \(error.localizedDescription)")
            return nil
        }
        protokoll.schreibe("datei-mitschrift", aufnahme: name, zahlen: ["beitraege": Double(segmente.count)])
        ablage = Ablage(datei: datei, ergebnis: erg); self.hinweise = hinweise
        ablageAufnahme = name == nil ? nil : (mikroURL ?? systemURL)?.deletingLastPathComponent()
        if segmente.isEmpty { zustand = .fertig; ladeFruehere(); return ablage }

        await fasseZusammen()
        return ablage
    }

    private func fasseZusammen() async {
        guard var a = ablage, !a.ergebnis.segmente.isEmpty else { return }
        zustand = .wertAus("Fasse zusammen …")
        abbruch = false
        var erg = a.ergebnis
        let name = erg.aufnahme
        let text = MeetingTranskript.text(erg.segmente)
        let t0 = Date()
        if let klient = await ollamaKlient() {
            var auswertung = MeetingAuswertung(klient: klient)
            auswertung.gescheitert = { [protokoll, weak self] versuch, fehler in
                protokoll.schreibe("zusammenfassung-versuch", aufnahme: name, fehler: fehler, zahlen: ["versuch": Double(versuch)])
                Task { @MainActor in if versuch == 1, self?.beschaeftigt == true { self?.zustand = .wertAus("Fasse zusammen (zweiter Versuch) …") } }
            }
            let zahlen: [String: Double] = ["zeichen": Double(text.count), "kontext": Double(klient.kontext ?? 0),
                                            "teile": Double(MeetingAufgaben.stuecke(text, zeichen: MeetingAufgaben.stueckGroesse(kontext: klient.kontext)).count)]
            let lauf = Task { [auswertung] in try await auswertung.analysiere(transkript: text) }
            zusammenfassung = lauf
            if abbruch { lauf.cancel() }
            do {
                let an = try await lauf.value
                var titel = an.titel.isEmpty ? "Meeting" : an.titel
                if let v = titelVorgabe { titel = v + ": " + titel }
                erg.titel = titel; erg.zusammenfassung = an.zusammenfassung; erg.aufgaben = an.aufgaben
                erg.entscheidungen = an.entscheidungen; erg.alleAufgaben = an.alleAufgaben; erg.offeneFragen = an.offeneFragen
                erg.stand = .vollstaendig
                protokoll.schreibe("zusammenfassung", aufnahme: name, dauer: Date().timeIntervalSince(t0), zahlen: zahlen)
            } catch {
                let grund = lauf.isCancelled ? "abgebrochen" : error.localizedDescription
                erg.stand = .ohneZusammenfassung(grund)
                protokoll.schreibe("zusammenfassung", aufnahme: name, dauer: Date().timeIntervalSince(t0), fehler: grund, zahlen: zahlen)
            }
            zusammenfassung = nil
        } else {
            let grund = ollama?.meldung ?? "Ollama ist nicht bereit."
            erg.stand = .ohneZusammenfassung(grund)
            protokoll.schreibe("zusammenfassung", aufnahme: name, fehler: grund)
        }
        do { a.datei = try MeetingArchiv.nachtrageSicher(erg, datei: a.datei, zuletzt: a.ergebnis, sicherung: ablageAufnahme) }
        catch {
            hinweise.append("Die Datei ließ sich nicht aktualisieren: \(error.localizedDescription)")
            protokoll.schreibe("datei-nachtrag", aufnahme: name, fehler: Self.dateiFehler(error))
        }
        a.ergebnis = erg
        ablage = a
        uebernahme = ""; uebernommen = 0
        zustand = .fertig
        ladeFruehere()
    }

    private static func dateiFehler(_ e: Error) -> String { let n = e as NSError; return "Datei nicht schreibbar (\(n.domain) \(n.code))" }

    func brichZusammenfassungAb() { abbruch = true; zusammenfassung?.cancel() }

    func erneutZusammenfassen() async {
        guard !beschaeftigt, ablage != nil else { return }
        await fasseZusammen()
    }

    func ladeFruehere() { fruehere = MeetingArchiv.eintraege(aufnahmen: Self.aufnahmenOrdner, dokumente: Self.ordner) }

    func werteErneutAus(_ auf: MeetingAufnahme) async {
        guard !beschaeftigt else { return }
        zustand = .wertAus("Erkenne das Gespräch …")
        hinweise = []; live = []; liveKanal = [:]; antworten = []; ablage = nil; uebernahme = ""; uebernommen = 0
        let fm = FileManager.default
        let mik = auf.ordner.appendingPathComponent("mikrofon.wav"), sys = auf.ordner.appendingPathComponent("systemton.wav")
        let mikDa = fm.fileExists(atPath: mik.path), sysDa = fm.fileExists(atPath: sys.path)
        guard mikDa || sysDa else { zustand = .fehler("In dieser Aufnahme liegen keine Tondateien."); return }
        let meta = MeetingArchiv.liesMeta(auf.ordner)
        let geschaetzt = MeetingArchiv.versatz(mikroDauer: mikDa ? MeetingWav.dauer(mik) : nil, systemDauer: sysDa ? MeetingWav.dauer(sys) : nil)
        var ersetzt: URL?
        var vorHinweise = meta?.hinweise ?? []
        if let d = auf.dokument {
            if auf.dokumentSicher, (try? MeetingArchiv.sichere(d, in: auf.ordner)) != nil { ersetzt = d }
            else { vorHinweise.append("Die frühere Datei „\(d.lastPathComponent)“ blieb unverändert; diese Auswertung liegt als neue Datei daneben.") }
        }
        protokoll.schreibe("erneut-auswerten", aufnahme: auf.name, zahlen: ["tonSekunden": auf.dauer.rounded(), "zeitenGemerkt": meta == nil ? 0 : 1])
        let e = MeetingEingabe(mikro: nil, system: nil, beginn: meta?.beginn ?? auf.beginn, dauer: meta?.dauer ?? auf.dauer, titelVorgabe: nil,
                               vorHinweise: vorHinweise, mikroDatei: mikDa ? mik : nil, systemDatei: sysDa ? sys : nil,
                               versatzMikro: meta?.versatzMikro ?? geschaetzt.mikro, versatzSystem: meta?.versatzSystem ?? geschaetzt.system,
                               aufnahme: auf.name, ersetzt: ersetzt)
        await verarbeite(e, probe: false)
    }

    func uebergebeAufgaben(trocken: Bool) async {
        guard let a = ablage, !a.ergebnis.aufgaben.isEmpty else { return }
        let name = a.datei.lastPathComponent
        if trocken { uebernahme = "Trockenlauf, nichts gesendet:\n" + MeetingAufgaben.trockenlauf(aufgaben: a.ergebnis.aufgaben, meetingDatei: name); return }
        guard let u = uebersicht else { uebernahme = "Keine Verbindung zu Seneca."; return }
        var ok = 0
        var fehler = ""
        for t in a.ergebnis.aufgaben {
            do { try await u.legeMeetingAufgabeAn(t, meetingDatei: name); ok += 1 } catch { fehler = OverviewStore.fehlertext(error); break }
        }
        uebernommen = ok
        uebernahme = fehler.isEmpty ? "\(ok) Aufgabe\(ok == 1 ? "" : "n") an Seneca übergeben." : "\(ok) übergeben, dann: \(fehler)"
    }

    func zeigeInFinder() { if let a = ablage { NSWorkspace.shared.activateFileViewerSelecting([a.datei]) } }
    func oeffneDatei() { if let a = ablage { NSWorkspace.shared.open(a.datei) } }
    func oeffne(_ auf: MeetingAufnahme) { if let d = auf.dokument { NSWorkspace.shared.open(d) } }
    func schliesse() { if case .fertig = zustand { zustand = .ruht } else if case .fehler = zustand { zustand = .ruht } }
}
