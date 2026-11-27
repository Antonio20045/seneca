import SwiftUI

@MainActor
final class TageslaufModell: ObservableObject {
    static let gemeinsam = TageslaufModell()
    static var befehl: URL { TageslaufHaken.ordner.appendingPathComponent("tageslauf") }
    static var erlaubt: Bool { MacPfade.profil.echteDaten && !Hintergrund.aktiv && !MacPfade.pruefinstanz }

    @Published private(set) var tag: Tageslauf?
    @Published private(set) var gelesen = Date()
    @Published private(set) var einmalGelesen = false
    private var laedt = false
    private var zuletztGut: Date?

    func beobachte() async {
        guard Self.erlaubt else { return }
        while !Task.isCancelled {
            await lade()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    @discardableResult
    func lade() async -> Tageslauf? {
        guard !laedt else { return tag }
        laedt = true
        defer { laedt = false }
        let daten = await Kindprozess.laufe(Self.befehl, ["heute", "--json"], limit: 20)
        let alt = tag
        let ergebnis = await Task.detached(priority: .utility) { () -> (Tageslauf, Bool)? in
            guard let daten, let n = Tageslauf.lies(daten) else { return nil }
            return (n, n != alt)
        }.value
        let neu = ergebnis?.0
        if let (neu, geaendert) = ergebnis, !neu.istLeer {
            if geaendert { tag = neu }
            zuletztGut = Date()
        } else if let z = zuletztGut, Date().timeIntervalSince(z) > 15 * 60 {
            tag = nil
            zuletztGut = nil
        }
        gelesen = Date()
        einmalGelesen = true
        return neu
    }
}

enum HeuteBild {
    nonisolated static var ziel: String? {
        let env = ProcessInfo.processInfo.environment
        guard let z = env["SENECA_HEUTE_BILD"], !z.isEmpty, let d = env["SENECA_DATEN"], !d.isEmpty else { return nil }
        return z
    }

    static func laufe() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let env = ProcessInfo.processInfo.environment
            let breite = env["SENECA_HEUTE_BREITE"].flatMap { Double($0) } ?? 1440
            let hoehe = env["SENECA_HEUTE_HOEHE"].flatMap { Double($0) } ?? 1000
            let seite = ZStack {
                SnGrund(fortschritt: 0)
                if let s = HeuteTafelLogik.beispiel(env["SENECA_DEMO_STAND"] ?? "Beispiel-Stand") {
                    switch env["SENECA_SEITE"] {
                    case "projekte":
                        SnProjekteTafel(stand: s, zuDenFragen: {}, oeffne: { _ in })
                        SnGeruestBild(stand: s, aktiv: .projekte)
                    case "kalender", "kalender-detail", "kalender-neu", "kalender-vorschlag":
                        SnKalenderTafel(stand: s, handeln: { _, _, _ in }, antworte: { _, _ in }, zumChat: { _ in }, rechneWeg: { _ in nil })
                            .onAppear { SnKalenderBild.zeige(env["SENECA_SEITE"] ?? "", s) }
                        SnGeruestBild(stand: s, aktiv: .kalender)
                    case "gespraeche", "gespraeche-team", "f-mehr":
                        SnGespraecheBild(stand: s, agent: env["SENECA_SEITE"] == "gespraeche" ? Hauptagent.id : "engineer", mehr: env["SENECA_SEITE"] == "f-mehr")
                        SnGeruestBild(stand: s, aktiv: .gespraeche, dock: false)
                    case "g-karten", "g-text", "g-lebenslauf", "g-fehler", "g-bild", "g-anhaenge", "g-verlauf", "g-ziehen":
                        SnGBild(seite: env["SENECA_SEITE"] ?? "", stand: s)
                    case "statistik":
                        if let d = HeuteTafelLogik.beispielStatistik() { SnStatistikTafel(daten: d, stand: s.jetzt) }
                        SnGeruestBild(stand: s, aktiv: .statistik, dock: false)
                    case "buendel":
                        SnBuendelTafel(stand: s, handle: { _, _, _ in }, pause: {})
                    case "team":
                        SnTeamTafel(stand: s, handle: { _, _, _ in }, schreiben: { _ in })
                        SnGeruestBild(stand: s, dock: false)
                    case "menue-fokus", "menue-frage", "menue-meeting":
                        SnMenueBild(stand: s, art: env["SENECA_SEITE"] ?? "")
                    case "bildschirm-vorher", "bildschirm-antwort":
                        SnBildschirmBild(antwort: env["SENECA_SEITE"] == "bildschirm-antwort")
                    case "meeting-live":
                        MeetingLiveTafel(dienst: nil, live: [(0, 1, 2, "Die Texte für die Startseite fehlen noch, sonst ist alles drin."), (60, 1, 1, "Die schicke ich dir bis Freitag."), (120, 1, 2, "Dann testet euer Prüfer heute Nacht, und wir gehen Montag live?"), (180, 1, 1, "Genau, wenn er nichts findet."), (240, 1, 2, "Und die Domain, wer verlängert die")].map { MeetingSegment(start: $0.0, ende: $0.0 + Double($0.1) * 5, sprecher: $0.2, text: $0.3) },
                                         marken: [181], antworten: [MeetingDienst.Antwort(frage: "Wer zahlt die Domain?", text: "Laut deiner Notiz vom 14. Oktober zahlt Sundartha die Domain, du das Hosting.", laedt: false)], dauer: 724,
                                         beginn: Date(timeIntervalSince1970: (s.jetzt + 724_000 - 240_000) / 1000))
                    case "sprechen-fremd", "sprechen-seneca":
                        let feld = env["SENECA_SEITE"] == "sprechen-seneca"
                        Group {
                            if feld { DiktatPille(dienst: .gemeinsam, feld: true).frame(width: 760, height: 64).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.1)))
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(TafelFarbe.jetzt.opacity(0.45), lineWidth: 1)) }
                            else { DiktatBlasenInhalt(dienst: .gemeinsam) }
                        }
                        .onAppear { DiktatDienst.gemeinsam.blasenProbe("hoert") }
                    case "start-weiter", "start-antwortet-nicht", "start-wieder":
                        let art = env["SENECA_SEITE"] ?? ""
                        SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, zuDenFragen: {}, zurArbeit: {}).opacity(art == "start-antwortet-nicht" ? 0.55 : 1)
                        SnGeruestBild(stand: s)
                        SnStartZeilen(stand: s, verbunden: art == "start-wieder", seit: art == "start-antwortet-nicht" ? Date(timeIntervalSince1970: s.jetzt / 1000 - 120) : nil, fehler: "", warum: .constant(false), wieder: art == "start-wieder" ? 1 : nil)
                    case "meeting-ergebnis":
                        SnMeetingErgebnis(e: SnMeetingProbe.ergebnis(s), datei: URL(fileURLWithPath: NSHomeDirectory() + "/Bereiche/sundartha/meetings/2026-11-26-telefonat-jonas.md"), zurueck: {},
                                          todos: [try? JSONDecoder().decode(SenecaStand.Todo.self, from: Data(#"{"id":"t","titel":"Steuerberater: Kleinunternehmer klären","tag":"heute","dauer_min":15}"#.utf8))].compactMap { $0 })
                        SnGeruestBild(stand: s, dock: false)
                    case "f-auftrag":
                        SnAuftragLebenslaufBild(stand: s)
                    case "f-lebenslauf":
                        SnFrageLebenslaufBild(stand: s)
                    case "buendel-ablauf":
                        SnBuendelAblaufBild(stand: s)
                    case "entscheiden":
                        SnEntscheidenTafel(stand: s, antworte: { _, _ in }, handle: { _, _, _ in })
                        SnGeruestBild(stand: s, aktiv: .fragen)
                    default:
                        SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, zuDenFragen: {}, zurArbeit: {})
                        SnGeruestBild(stand: s)
                    }
                }
            }
            .frame(width: breite, height: hoehe)
            .preferredColorScheme(.dark)
            let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: true)
            let host = NSHostingView(rootView: seite)
            fenster.contentView = host
            for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let z = ziel {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: z))
            }
            exit(0)
        }
        app.run()
        exit(0)
    }
}

struct SnGeruestBild: View {
    var stand: SenecaStand
    var aktiv: SnOrt = .heute
    var dock = true

    var body: some View {
        VStack {
            SnOrteKapsel(aktiv: aktiv, fragen: SnOrt.fragen(stand), waehle: { _ in })
            Spacer()
            if dock { SnDockZu { SnKugel(groesse: 32, atmet: false) }.snGlas(RoundedRectangle(cornerRadius: 28, style: .continuous)) }
        }
        .padding(.top, 28).padding(.bottom, 28)
    }
}

enum SnMeetingProbe {
    static func ergebnis(_ s: SenecaStand) -> MeetingErgebnis {
        let b = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: s.jetzt / 1000)).addingTimeInterval(14.5 * 3600)
        var e = MeetingErgebnis(titel: "Telefonat Jonas: Website", beginn: b, dauer: 1692, segmente: [(600, 624, 2, "Dann testet euer Prüfer heute Nacht, und wir gehen Montag live?"), (660, 712, 1, "Genau, wenn er nichts findet."),
            (840, 864, 2, "Sundartha verlängert die Domain, das Hosting bleibt bei euch.")].map { MeetingSegment(start: $0.0, ende: $0.1, sprecher: $0.2, text: $0.3) },
            zusammenfassung: "Die Website geht Montag live, wenn Prüfer heute Nacht nichts findet. Danach verlängert Sundartha die Domain.", aufgaben: [], rollen: [1: "Mikrofon, Antonio", 2: "Systemton"],
            entscheidungen: ["Livegang Montag, 30. November, nach dem Test heute Nacht.", "Sundartha verlängert die Domain, das Hosting bleibt bei dir."],
            alleAufgaben: [MeetingAufgabe(wer: "Antonio", text: "Texte für die Startseite an Jonas schicken", termin: "Freitag"), MeetingAufgabe(wer: "Prüfer", text: "Neue Website von Sundartha testen", termin: "heute Nacht ab 22:00"),
                           MeetingAufgabe(wer: "Antonio", text: "Steuerberater: Kleinunternehmer klären", termin: nil)],
            offeneFragen: ["Braucht die Seite einen Cookie-Hinweis? Jonas klärt das bis Montag."], aufnahme: "probe")
        e.marken = [661]; e.termin = "Telefonat · Jonas · Sundartha"; e.namen = [2: "Jonas"]
        return e
    }
}
