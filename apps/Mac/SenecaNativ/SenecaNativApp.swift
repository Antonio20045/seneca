import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var haeltEinzelinstanzSperre = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if MacPfade.profil == .echt, !Hintergrund.aktiv, let sperre = MacPfade.instanzSperrdatei {
            if PfadSperre.istFremdBelegt(bei: sperre), !PfadSperre.wartetBisFrei(bei: sperre) {
                NSApp.terminate(nil)
                return
            }
            PfadSperre.belege(bei: sperre)
            haeltEinzelinstanzSperre = true
        }
        Leistungsmessung.starte()
        TageslaufHaken.gemeinsam.starte()
        if Hintergrund.aktiv {
            NSApp.setActivationPolicy(.accessory)
            for versuch in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(versuch) * 0.7) {
                    for w in NSApp.windows where w.canBecomeMain { Hintergrund.legeAb(w) }
                }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        #if DEBUG
        if MacPfade.profil == .demo, let r = ProcessInfo.processInfo.environment["SENECA_TEST_RAHMEN"] {
            let z = r.split(separator: ",").compactMap { Double($0) }
            if z.count == 4 {
                Task { @MainActor in
                    for _ in 0..<5 {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { continue }
                        if w.styleMask.contains(.fullScreen), !Hintergrund.aktiv { w.toggleFullScreen(nil); try? await Task.sleep(for: .seconds(2.5)) }
                        w.setFrame(CGRect(x: z[0], y: z[1], width: z[2], height: z[3]), display: true)
                    }
                }
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        guard haeltEinzelinstanzSperre, let sperre = MacPfade.instanzSperrdatei else { return }
        PfadSperre.gibFrei(bei: sperre)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { for w in NSApp.windows where w.canBecomeMain { Hintergrund.zeige(w) } }
        return true
    }
}

struct SenecaNativApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var modell = AppModell()
    private let diktat = DiktatDienst.gemeinsam
    @StateObject private var meeting = MeetingDienst.gemeinsam
    @Environment(\.openWindow) private var openWindow
    #if DEBUG
    @StateObject private var messFeld = DiktatMessFeld()
    #endif

    var body: some Scene {
        Window("Seneca", id: "haupt") {
            fensterInhalt
                .frame(minWidth: 1100, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("Seneca") {
                Button("Schnellfrage …") { modell.dienste.panel.schalte() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Neuer Chat") { Task { await modell.neuerChat() } }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(modell.zustand != .bereit)
                Button("Fenster öffnen") { modell.zeigeFenster(nil) }
                Divider()
                Button(meeting.nimmtAuf ? "Meeting beenden" : "Meeting aufnehmen") { meeting.umschalten(); if !Hintergrund.aktiv { openWindow(id: "meeting") } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(meeting.beschaeftigt && !meeting.nimmtAuf)
                Button("Meeting-Fenster") { openWindow(id: "meeting") }
            }
            CommandMenu("Seiten") {
                ForEach(Array(Seite.leiste.enumerated()), id: \.element) { i, s in
                    Button(s.titel) { modell.gehe(s) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                        .disabled(modell.zustand != .bereit)
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Suchen …") { modell.schalteSuche() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Modell für diesen Chat wählen …") { modell.oeffneModellwahl() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Tastenkürzel") { modell.hilfeOffen = true }
                    .disabled(modell.zustand != .bereit)
            }
            CommandGroup(after: .sidebar) {
                Button(modell.gespraechAn ? "Gespräch ausblenden" : "Gespräch einblenden") { modell.schalteGespraech() }
                    .keyboardShortcut("\\", modifiers: .command)
                    .disabled(modell.zustand != .bereit)
            }
            CommandGroup(after: .appSettings) {
                Button("Zugang neu eingeben …") { modell.zugangZuruecksetzen() }
                Button("Erneut verbinden") { Task { await modell.verbinde() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(modell.zustand == .einrichten)
            }
        }

        Window("Meeting", id: "meeting") {
            MeetingView(dienst: meeting)
        }
        .defaultSize(width: 560, height: 620)

        MenuBarExtra(isInserted: .constant(!MacPfade.nebenher && (!Hintergrund.aktiv || ProcessInfo.processInfo.environment["SENECA_HINTERGRUND_MENUE"] == "1"))) {
            MenueLeisteView(modell: modell, dienste: modell.dienste)
        } label: {
            MenueLeisteZeichen(modell: modell, dienste: modell.dienste)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EinstellungenView(modell: modell)
        }
    }

    @ViewBuilder private var fensterInhalt: some View {
        #if DEBUG
        if DiktatMessung.aktiv {
            DiktatMessungView(feld: messFeld, dienst: diktat)
                .task { await DiktatMessung.laufe(feld: messFeld, dienst: diktat) }
        } else {
            WurzelView(modell: modell)
                .task { await modell.starte() }
                .task { await starteDiktat() }
                .task { Selbstfoto.starte(modell: modell) }
        }
        #else
        WurzelView(modell: modell)
            .task { await modell.starte() }
            .task { await starteDiktat() }
            .task { Selbstfoto.starte(modell: modell) }
        #endif
    }

    private func starteDiktat() async {
        diktat.chatZiel = { [weak modell] text in
            guard let modell, modell.zustand == .bereit else { return false }
            let partner = modell.gegenueber.partner
            let neu = DiktatEinfueger.zusammen(modell.chat.entwurf(fuer: partner), text)
            modell.chat.setzeEntwurf(neu, fuer: partner)
            if modell.chat.isShowing {
                modell.ansichten.vorschlagen(neu)
            } else {
                modell.zeigeFenster(nil, gespraech: true)
            }
            return true
        }
        meeting.uebersicht = modell.uebersicht
        if !MacPfade.nebenher { meeting.starteWache() }
        #if DEBUG
        if let datei = ProcessInfo.processInfo.environment["SENECA_MEETING_PROBE"], !datei.isEmpty {
            Task { await MeetingProbe.laufe(datei: URL(fileURLWithPath: datei), dienst: meeting) }
        }
        if ProcessInfo.processInfo.environment["SENECA_MENUE_PROBE"] != nil {
            Task { await MenueProbe.laufe(dienste: modell.dienste) }
        }
        if let art = ProcessInfo.processInfo.environment["SENECA_DIKTAT_BLASE"] {
            Task { try? await Task.sleep(for: .seconds(1.5)); diktat.blasenProbe(art) }
        }
        #endif
        if !MacPfade.nebenher { await diktat.starte() }
    }
}
