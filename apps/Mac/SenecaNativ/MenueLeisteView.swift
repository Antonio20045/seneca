import SwiftUI

struct MenueLeisteZeichen: View {
    var modell: AppModell
    @ObservedObject var zeichen: MenueZeichenModell
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    init(modell: AppModell, dienste: MacDienste) {
        self.modell = modell
        self.zeichen = dienste.zeichen
    }

    var body: some View {
        let z = zeichen.zeichen
        HStack(spacing: 3) {
            if z.rot { Image(nsImage: MenueZeichenModell.roterPunkt) } else { Image(systemName: z.symbol) }
            if let t = z.text { Text(t).monospacedDigit() }
        }
        .accessibilityLabel(z.ansage)
        .task {
            modell.fensterOeffner = { openWindow(id: "haupt") }
            modell.einstellungenOeffner = { if !Hintergrund.aktiv { NSApp.activate(ignoringOtherApps: true) }; openSettings() }
            try? await Task.sleep(for: .milliseconds(600))
            if modell.hauptfenster == nil { openWindow(id: "haupt") }
        }
    }
}

struct MenueLeisteView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var dienste: MacDienste

    var body: some View {
        let s = dienste.stand
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Seneca").font(Schrift.serif(24, kursiv: true)).foregroundStyle(Farbe.ink1)
                Spacer()
                Text(verbindung).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !MacPfade.nebenher { sprechenZeile }
                grosseZeile(symbol: "display", farbe: Farbe.himmel, titel: "Bildschirm zeigen",
                            unter: dienste.schnellfrage.beschaeftigt ? "Geht, sobald Senecas Antwort im Fragefeld fertig ist" : "Seneca sieht, was du gerade vor dir hast",
                            kuerzel: nil, kennung: "menue-bildschirm") { dienste.zeigeBildschirm() }
                meetingZeile
            }
            zuletzt
            if modell.zustand == .bereit {
                VStack(spacing: 6) {
                    if s.bekannt {
                        zeile(punkt: s.braucht > 0 ? Farbe.bernstein : Farbe.ink4, text: "\(s.braucht) braucht dich", an: s.braucht > 0, kennung: "menue-braucht") {
                            modell.zeigeFenster(Route(MacPfade.profil.echteDaten ? .heute : .entscheidungen))
                        }
                        zeile(punkt: s.laeuft > 0 ? Farbe.himmel : Farbe.ink4, text: "\(s.laeuft) läuft", an: s.laeuft > 0, kennung: "menue-laeuft") {
                            modell.zeigeFenster(Route(.heute))
                        }
                    } else {
                        zeile(punkt: Farbe.ink4, text: "Gerade liegt kein Stand vor.", an: false, kennung: "menue-kein-stand") {
                            modell.zeigeFenster(Route(.heute))
                        }
                    }
                    zeile(punkt: s.ungelesen > 0 ? Farbe.gruen : Farbe.ink4, text: s.ungelesen == 1 ? "1 ungelesener Bericht" : "\(s.ungelesen) ungelesene Berichte", an: s.ungelesen > 0, kennung: "menue-berichte") {
                        modell.zeigeFenster(Route(.berichte))
                    }
                }
                termin(s.termin)
                SchnellfrageFeld(modell: dienste.schnellfrage, imFenster: { modell.zeigeFenster(Route(.heute), gespraech: true) })
            } else {
                Text(modell.zustand == .einrichten ? "Seneca ist noch nicht eingerichtet." : "Seneca ist gerade nicht verbunden.")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
            }
            Divider().overlay(Farbe.linie2)
            HStack {
                Button("Fenster öffnen") { modell.zeigeFenster(nil) }.buttonStyle(NebenKnopfStil()).fixedSize().accessibilityIdentifier("menue-fenster")
                Spacer()
                SettingsLink { Text("Einstellungen") }.buttonStyle(.plain).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
                Button("Beenden") { NSApp.terminate(nil) }.buttonStyle(.plain).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(MenueFensterLeser(geoeffnet: {
            VorneMerker.gemeinsam.menueGeoeffnet()
            AblageZuletztModell.gemeinsam.lade()
        }))
        .background(Farbe.papier)
        .preferredColorScheme(.dark)
    }

    @ObservedObject private var meeting = MeetingDienst.gemeinsam
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var diktat = DiktatDienst.gemeinsam
    @ObservedObject private var vorne = VorneMerker.gemeinsam
    @ObservedObject private var ablage = AblageZuletztModell.gemeinsam

    private var sprechenZeile: some View {
        let hoert = diktat.zustand == .hoert, erkennt = diktat.zustand == .erkennt
        return grosseZeile(symbol: hoert ? "stop.fill" : "mic.fill", farbe: hoert ? Farbe.koralle : Farbe.himmel,
                           titel: hoert ? "Fertig – Text einfügen" : erkennt ? "Erkenne …" : "Sprechen",
                           unter: hoert ? "Seneca hört zu · " + vorne.zielSatz : erkennt ? nil : vorne.zielSatz,
                           kuerzel: "rechte ⌘", kennung: "menue-sprechen") { dienste.sprechen() }
    }

    private var meetingZeile: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let v = meeting.vorschlag, !meeting.beschaeftigt {
                Text("Das Mikrofon läuft in \(v). Meeting aufnehmen?").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
            }
            grosseZeile(symbol: meeting.nimmtAuf ? "stop.circle.fill" : "record.circle", farbe: meeting.nimmtAuf ? Farbe.koralle : Farbe.himmel,
                        titel: meetingTitel, unter: meetingUnter, kuerzel: "⌘⇧R", kennung: "menue-meeting") {
                if !meeting.beschaeftigt || meeting.nimmtAuf { meeting.umschalten() }
                openWindow(id: "meeting")
            }
        }
    }

    private var meetingTitel: String {
        switch meeting.zustand {
        case .nimmtAuf: return "Meeting beenden · " + MeetingTranskript.zeit(meeting.dauer)
        case .startet: return "Meeting startet …"
        case .wertAus: return "Meeting wird ausgewertet …"
        default: return "Meeting aufnehmen"
        }
    }

    private var meetingUnter: String? {
        switch meeting.zustand {
        case .nimmtAuf: return "Die Aufnahme läuft"
        case .wertAus(let schritt): return schritt.isEmpty ? nil : schritt
        default: return "Mitschrift und Zusammenfassung entstehen auf dem Mac"
        }
    }

    @ViewBuilder private var zuletzt: some View {
        if !ablage.eintraege.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Abschnittstitel(text: ablage.titel)
                ForEach(ablage.eintraege) { e in AblageZeile(eintrag: e) }
            }
            .accessibilityIdentifier("menue-zuletzt")
        }
    }

    private func grosseZeile(symbol: String, farbe: Color, titel: String, unter: String?, kuerzel: String?, kennung: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(farbe).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink).lineLimit(1)
                    if let unter, !unter.isEmpty { Text(unter).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if let kuerzel { Text(kuerzel).font(Schrift.grotesk(11)).foregroundStyle(Farbe.ink4).fixedSize() }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Farbe.pille, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kennung)
    }

    private var verbindung: String {
        switch modell.zustand {
        case .bereit: return "verbunden"
        case .verbindet: return "verbindet …"
        case .einrichten: return "nicht eingerichtet"
        case .fehler: return "nicht verbunden"
        }
    }

    private func zeile(punkt: Color, text: String, an: Bool, kennung: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            HStack(spacing: 10) {
                Circle().fill(punkt).frame(width: 7, height: 7)
                Text(text).font(Schrift.grotesk(14, .medium)).foregroundStyle(an ? Farbe.ink : Farbe.ink3)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(Farbe.ink4)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Farbe.pille, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kennung)
    }

    private func termin(_ t: MenueStand.NaechsterTermin?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Abschnittstitel(text: t?.jetzt == true ? "Jetzt" : "Nächster Termin")
            if let t {
                Text(t.titel).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.ink).lineLimit(2)
                Text(t.wann).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
            } else {
                Text("Heute nichts mehr.").font(Schrift.serif(15, kursiv: true)).foregroundStyle(Farbe.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("menue-termin")
    }
}

private struct AblageZeile: View {
    let eintrag: AblageEintrag
    @State private var hover = false

    private var url: URL { URL(fileURLWithPath: eintrag.pfad) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(eintrag.name).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink).lineLimit(1).truncationMode(.middle)
                if !eintrag.unter.isEmpty {
                    Text(eintrag.unter).font(Schrift.grotesk(11)).foregroundStyle(Farbe.ink3).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Farbe.ink3)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Im Finder zeigen")
            .accessibilityLabel("Im Finder zeigen")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(hover ? Farbe.pilleLauf : Farbe.pille, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help("Klick öffnet die Datei · ⌥-Klick zeigt sie im Finder · lässt sich in eine E-Mail ziehen")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("menue-abgelegt")
    }
}
