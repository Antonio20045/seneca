import SwiftUI

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
                    case "widget-mac":
                        HStack(spacing: 24) {
                            ForEach(WidgetLogik.faelle(s), id: \.0) { _, jetzt, l in
                                WidgetFace(lage: l, jetzt: jetzt, art: .mac).padding(.horizontal, 16).padding(.vertical, 14).frame(width: 344, height: 160)
                                    .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x1E2430, deckkraft: 0.86)))
                            }
                        }
                    case "start-code":
                        SnOrteKapsel(aktiv: .heute, fragen: SnOrt.fragen(s), waehle: { _ in }).opacity(0.5).padding(.top, 18).frame(maxHeight: .infinity, alignment: .top)
                        SnKopplungTafel(code: Kopplungscode(adresse: "https://seneca.beispiel.ts.net", schluessel: "beispiel", name: "MacBook Pro von Antonio", bis: Date().addingTimeInterval(582)), iphone: false, neu: {})
                            .frame(maxHeight: .infinity, alignment: .top)
                    case "projekte":
                        SnProjekteTafel(stand: s, zuDenFragen: {}, lauf: HeuteTafelLogik.beispielStatistik(env["SENECA_STATISTIK"])?.kennzahlen)
                        SnGeruestBild(stand: s, aktiv: .projekte)
                    case "kalender", "kalender-detail", "kalender-neu", "kalender-vorschlag":
                        SnKalenderTafel(stand: s, handeln: { _, _, _ in }, antworte: { _, _ in }, zumChat: { _ in }, rechneWeg: { _ in nil })
                            .onAppear { SnKalenderBild.zeige(env["SENECA_SEITE"] ?? "", s) }
                        SnGeruestBild(stand: s, aktiv: .kalender)
                    case "gespraeche", "gespraeche-team", "f-mehr":
                        SnGespraecheBild(stand: s, agent: env["SENECA_SEITE"] == "gespraeche" ? Hauptagent.id : "engineer", mehr: env["SENECA_SEITE"] == "f-mehr")
                        SnGeruestBild(stand: s, aktiv: .gespraeche, dock: false)
                    case "g-karten", "g-text", "g-lebenslauf", "g-fehler", "g-bild", "g-anhaenge", "g-verlauf", "g-ziehen", "z-konflikt", "t-todo-03":
                        SnGBild(seite: env["SENECA_SEITE"] ?? "", stand: s)
                    case "chat-echt":
                        SnChatBild(stand: s, agent: env["SENECA_AGENT"] ?? Hauptagent.id, frageId: env["SENECA_FRAGE"], strom: env["SENECA_STROM"])
                    case "statistik":
                        if let d = HeuteTafelLogik.beispielStatistik(env["SENECA_STATISTIK"]) {
                            SnStatistikTafel(daten: d, stand: Date().timeIntervalSince1970 * 1000, bereich: StatBereich.allCases.first { "\($0)" == env["SENECA_STAT_BEREICH"] },
                                             zeitraum: StatZeitraum(rawValue: env["SENECA_STAT_ZEITRAUM"] ?? "") ?? .woche)
                        }
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
                                         marken: [181], luecken: env["SENECA_LUECKE"] == nil ? [] : [[200, 12]], antworten: [MeetingDienst.Antwort(frage: "Wer zahlt die Domain?", text: "Laut deiner Notiz vom 14. Oktober zahlt Sundartha die Domain, du das Hosting.", laedt: false)], dauer: 724,
                                         beginn: Date(timeIntervalSince1970: (s.jetzt + 724_000 - 240_000) / 1000))
                    case "sprechen-fremd":
                        DiktatBlasenInhalt(dienst: .gemeinsam)
                        .onAppear {
                            #if DEBUG
                            DiktatDienst.gemeinsam.blasenProbe(env["SENECA_DIKTAT_BLASE"] ?? "hoert")
                            #endif
                        }
                    case "start-weiter", "start-antwortet-nicht", "start-wieder":
                        let art = env["SENECA_SEITE"] ?? ""
                        SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, notiere: { SnHeuteMass.notiert.append($0) },
                                     neu: art == "start-wieder" ? Set((s.team ?? []).filter { $0.name == "Prüfer" }.map(SnHeuteTafel.kennung)) : [], laeuft: false).opacity(art == "start-antwortet-nicht" ? 0.55 : 1)
                        SnGeruestBild(stand: s)
                        SnStartZeilen(stand: s, verbunden: art == "start-wieder", seit: art == "start-antwortet-nicht" ? Date(timeIntervalSince1970: s.jetzt / 1000 - 120) : nil, fehler: "", warum: .constant(false), wieder: art == "start-wieder" ? 1 : nil)
                    case "meeting-ansicht":
                        SnMeetingAnsicht(termin: (s.termine ?? []).first { $0.titel == "Telefonat Jonas" }!, todos: s.todos ?? [], zurueck: {}, notiere: { SnHeuteMass.notiert.append($0) }, uebernimm: { SnHeuteMass.notiert.append("auftrag:" + $0.quelle) })
                    case "meeting-ergebnis":
                        SnMeetingErgebnis(e: SnMeetingProbe.ergebnis(s), datei: URL(fileURLWithPath: NSHomeDirectory() + "/Ablage/sundartha/meetings/2026-11-26-telefonat-jonas.md"), zurueck: {},
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
                        SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, notiere: { SnHeuteMass.notiert.append($0) }, laeuft: false)
                        SnGeruestBild(stand: s)
                    }
                }
            }
            .frame(width: breite, height: hoehe)
            .preferredColorScheme(.dark)
            let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: env["SENECA_HEUTE_ABLAUF"] == nil ? [.borderless] : [.titled], backing: .buffered, defer: true)
            let host = NSHostingView(rootView: seite)
            fenster.contentView = host
            for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            if let ablauf = env["SENECA_STAT_ABLAUF"] { await SnStatistikProbe.ablauf(host, ablauf) }
            if let ablauf = env["SENECA_HEUTE_ABLAUF"] { await SnBedienProbe.heute(host, ablauf) }
            if let ablauf = env["SENECA_MEETING_ABLAUF"] { await SnBedienProbe.meeting(host, ablauf) }
            if let ablauf = env["SENECA_ZURUECK_ABLAUF"] { await SnBedienProbe.ablauf(host, ablauf) }
            if let mess = env["SENECA_MESS"] { await SnChatMessung.laufe(host, mess, dauer: env["SENECA_FILM_DAUER"].flatMap(Double.init) ?? 20) }
            if let film = env["SENECA_FILM"], let dauer = env["SENECA_FILM_DAUER"].flatMap(Double.init) {
                let t0 = Date()
                var nr = 0, zeiten: [String] = []
                let a = (env["SENECA_FILM_AUSSCHNITT"] ?? "").split(separator: ",").compactMap { Double($0) }
                let rahmen = a.count == 4 ? NSRect(x: a[0], y: hoehe - a[1] - a[3], width: a[2], height: a[3]) : host.bounds
                while Date().timeIntervalSince(t0) < dauer {
                    host.layoutSubtreeIfNeeded()
                    let m = 1.5
                    if let layer = host.layer, let ctx = CGContext(data: nil, width: Int(rahmen.width * m), height: Int(rahmen.height * m), bitsPerComponent: 8, bytesPerRow: 0,
                                                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                        ctx.setFillColor(CGColor(red: 0.05, green: 0.11, blue: 0.24, alpha: 1))
                        ctx.fill(CGRect(x: 0, y: 0, width: rahmen.width * m, height: rahmen.height * m))
                        ctx.translateBy(x: 0, y: rahmen.height * m)
                        ctx.scaleBy(x: m, y: -m)
                        ctx.translateBy(x: -rahmen.minX, y: -(hoehe - rahmen.maxY))
                        layer.render(in: ctx)
                        nr += 1
                        if let bild = ctx.makeImage() { try? NSBitmapImageRep(cgImage: bild).representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.write(to: URL(fileURLWithPath: film + String(format: "/b%05d.jpg", nr))) }
                        zeiten.append(String(format: "%.3f", Date().timeIntervalSince(t0)))
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                try? zeiten.joined(separator: "\n").write(toFile: film + "/zeiten.txt", atomically: true, encoding: .utf8)
            }
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
            alleAufgaben: [MeetingAufgabe(wer: "Antonio", text: "Texte für die Startseite an Jonas schicken", termin: "Freitag", minuten: 30), MeetingAufgabe(wer: "Prüfer", text: "Neue Website von Sundartha testen", termin: "heute Nacht ab 22:00"),
                           MeetingAufgabe(wer: "Antonio", text: "Steuerberater: Kleinunternehmer klären", termin: nil)],
            offeneFragen: ["Braucht die Seite einen Cookie-Hinweis? Jonas klärt das bis Montag."], aufnahme: "probe")
        e.marken = [661]; e.termin = "Telefonat · Jonas · Sundartha"; e.namen = [2: "Jonas"]
        return e
    }
}
