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
            if let p = z.punkt { Image(nsImage: MenueZeichenModell.punkt(p)) } else { Image(systemName: z.symbol) }
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

typealias ML = MenueTafelLogik

struct MenueLeisteView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var dienste: MacDienste
    @ObservedObject private var meeting = MeetingDienst.gemeinsam
    @ObservedObject private var diktat = DiktatDienst.gemeinsam
    @State private var gesendet: (id: String, um: Date)?

    var body: some View {
        MenueTafel(stand: modell.store.stand, verbunden: modell.zustand == .bereit, meeting: meeting.nimmtAuf ? (MeetingTranskript.zeit(meeting.dauer), meeting.live.last) : nil,
                   hoert: diktat.zustand == .hoert, gesendet: gesendet,
                   antworte: { f, w in modell.store.antworte(frage: f.id, wahl: w); gesendet = w == "spaeter" ? nil : (f.id, Date()) },
                   zuruecknehmen: { f in modell.store.handle("rueckgaengig", ziel: f.id); gesendet = nil },
                   oeffne: { r in modell.zeigeFenster(r) }, mehr: { f in modell.zeigeFenster(nil); modell.zeigeMehr(f) },
                   sprechen: { dienste.sprechen() }, bildschirm: { dienste.zeigeBildschirm() },
                   meetingSchalten: { meeting.umschalten() }, merken: { meeting.merke() }, mitschrift: { openWindow(id: "meeting") },
                   frage: { SchnellfrageFeld(modell: dienste.schnellfrage, imFenster: { modell.zeigeFenster(Route(.heute), gespraech: true) }) })
            .background(MenueFensterLeser(geoeffnet: { VorneMerker.gemeinsam.menueGeoeffnet() }))
    }

    @Environment(\.openWindow) private var openWindow
}

struct MenueTafel<Feld: View>: View {
    var stand: SenecaStand?
    var verbunden: Bool
    var meeting: (dauer: String, zeile: MeetingSegment?)?
    var hoert = false
    var gesendet: (id: String, um: Date)?
    var antworte: (SenecaStand.Frage, String) -> Void = { _, _ in }
    var zuruecknehmen: (SenecaStand.Frage) -> Void = { _ in }
    var oeffne: (Route?) -> Void = { _ in }
    var mehr: (SenecaStand.Frage) -> Void = { _ in }
    var sprechen: () -> Void = {}
    var bildschirm: () -> Void = {}
    var meetingSchalten: () -> Void = {}
    var merken: () -> Void = {}
    var mitschrift: () -> Void = {}
    @ViewBuilder var frage: () -> Feld

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seneca").font(Schrift.serif(26)).foregroundStyle(.white)
                Spacer()
                if let b = stand.flatMap(ML.fokusBis), meeting == nil { Text("◐ FOKUS BIS \(HeuteTafelLogik.uhr(b))").font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.zweit) }
                if !verbunden { Text("nicht verbunden").font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.leise) }
            }
            if let s = stand { inhalt(s) }
            HStack(spacing: 8) {
                werkzeug(hoert ? "stop.fill" : "mic", "Sprechen", "rechte ⌘", sprechen)
                werkzeug("display", "Bildschirm", "⌥ Leertaste", bildschirm)
                werkzeug(meeting == nil ? "record.circle" : "circle.fill", "Meeting", meeting.map { "läuft · \($0.dauer)" } ?? "⌘⇧R", meetingSchalten, an: meeting != nil)
            }
            frage()
            HStack {
                Button { oeffne(nil) } label: { (Text("Seneca öffnen ").foregroundColor(TafelFarbe.text) + Text("⌘0").font(Schrift.mono(11)).foregroundColor(TafelFarbe.leise)) }
                    .buttonStyle(.plain).keyboardShortcut("0", modifiers: .command).accessibilityIdentifier("menue-fenster")
                Spacer()
                SettingsLink { Text("Einstellungen") }.buttonStyle(.plain).foregroundStyle(TafelFarbe.leise)
            }
            .font(Schrift.grotesk(13)).padding(.horizontal, 2).padding(.top, 2)
        }
        .padding(18)
        .frame(width: 390)
        .background(ZStack {
            LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [TafelFarbe.himmel.opacity(0.26), TafelFarbe.himmel.opacity(0.11), .clear], center: UnitPoint(x: 0.76, y: 0.1), startRadius: 0, endRadius: 230)
        })
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func inhalt(_ s: SenecaStand) -> some View {
        if let m = meeting {
            aufnahme(m, s)
            if let z = ML.imFenster(s) { karte(z) }
            if let z = ML.jetzt(s) { karte(z) }
        } else if let bis = ML.fokusBis(s) {
            VStack(alignment: .leading, spacing: 0) {
                kopf("JETZT")
                Text("Fokus, noch \(max(0, Int((bis - s.jetzt) / 60_000))) Min").font(Schrift.grotesk(16, .medium)).foregroundStyle(.white)
                Text("Seneca hält alles zurück, was dich braucht.").font(Schrift.grotesk(13.5)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.leise).padding(.top, 2)
            }
            .modifier(MenueKarte())
            if let z = ML.danach(s) { karte(z) }
            if let z = ML.laeuft(s) { karte(z) }
            if let z = ML.termin(s) { karte(z) }
        } else {
            if let f = ML.fragen(s).first { brauchtDich(f, s) }
            if let z = ML.laeuft(s) { karte(z) }
            if let z = ML.termin(s) { karte(z) }
        }
    }

    private func kopf(_ t: String, _ farbe: Color = TafelFarbe.leise) -> some View {
        Text(t).font(Schrift.mono(10.5, .medium)).kerning(1.3).foregroundStyle(farbe).padding(.bottom, 6)
    }

    private func karte(_ z: ML.Zeile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf(z.kopf, z.punkt == "bernstein" ? TafelFarbe.bernstein : TafelFarbe.leise)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(z.punkt == "gruen" ? TafelFarbe.gruen : z.punkt == "bernstein" ? TafelFarbe.bernstein : Color.white.opacity(0.3)).frame(width: 7, height: 7)
                    .background { if z.punkt == "gruen" { Circle().fill(TafelFarbe.gruen.opacity(0.18)).frame(width: 15, height: 15) } }
                (Text(z.text).foregroundColor(TafelFarbe.text) + Text(z.leise.map { " · \($0)" } ?? "").foregroundColor(TafelFarbe.leise))
                    .font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(MenueKarte())
    }

    private func brauchtDich(_ f: SenecaStand.Frage, _ s: SenecaStand) -> some View {
        let h = GL.haupt(f), n = ML.fragen(s).count
        return VStack(alignment: .leading, spacing: 0) {
            kopf(n == 1 ? "1 BRAUCHT DICH" : "\(n) BRAUCHEN DICH", TafelFarbe.bernstein)
            Text(f.text).font(Schrift.grotesk(16, .medium)).lineHeight(.exact(points: 22)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            Text(ML.unter(f)).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.zweit).padding(.top, 4).padding(.bottom, 12)
            if let g = gesendet, g.id == f.id {
                TimelineView(.periodic(from: g.um, by: 0.5)) { t in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                        Text(h?.quittung ?? h?.text ?? "").font(Schrift.grotesk(13, .medium)).foregroundStyle(.white)
                        Spacer()
                        if t.date.timeIntervalSince(g.um) < (s.regeln?["rueckgaengig_s"] ?? 5) {
                            Button("Rückgängig") { zuruecknehmen(f) }.buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if let h { Button(h.knopf ?? h.text ?? "Ja") { antworte(f, h.wert ?? "ja") }.buttonStyle(SnTafelKnopf(groesse: 13)) }
                    Button("Später") { antworte(f, "spaeter") }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                    Button("Mehr") { mehr(f) }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                }
            }
            if !ML.weitere(s).isEmpty {
                HStack {
                    Text(ML.weitere(s)).foregroundStyle(TafelFarbe.zweit).lineLimit(1)
                    Spacer()
                    Button("Entscheiden ›") { oeffne(Route(.entscheidungen)) }.buttonStyle(.plain).foregroundStyle(TafelFarbe.text).fixedSize()
                }
                .font(Schrift.grotesk(13)).padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }.padding(.top, 12)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TafelFarbe.bernstein.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(TafelFarbe.bernstein.opacity(0.3), lineWidth: 1))
    }

    private func aufnahme(_ m: (dauer: String, zeile: MeetingSegment?), _ s: SenecaStand) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.jetzt).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.jetzt.opacity(0.18)).frame(width: 16, height: 16))
                Text("AUFNAHME · \(m.dauer)").font(Schrift.mono(11)).kerning(1.2).foregroundStyle(.white).monospacedDigit()
                Spacer()
                if let t = ML.jetzt(s) { Text(t.text.components(separatedBy: " bis ")[0]).font(Schrift.grotesk(12.5)).foregroundStyle(TafelFarbe.zweit).lineLimit(1) }
            }
            .padding(.bottom, 8)
            if let z = m.zeile {
                (Text("Sprecher \(z.sprecher + 1) ").foregroundColor(.white).fontWeight(.medium) + Text(z.text).foregroundColor(TafelFarbe.zweit))
                    .font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).lineLimit(2).padding(.bottom, 12)
            }
            HStack(spacing: 8) {
                Button(action: merken) { HStack(spacing: 6) { Text("Merken"); MeetingTaste(t: "⌘⇧M") } }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                Button(action: mitschrift) { Text("Mitschrift") }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                Spacer()
                Button(action: meetingSchalten) { HStack(spacing: 6) { Text("Beenden"); Text("⌘⇧R").font(Schrift.mono(11)) } }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(.white))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TafelFarbe.jetzt.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(TafelFarbe.jetzt.opacity(0.3), lineWidth: 1))
    }

    private func werkzeug(_ bild: String, _ titel: String, _ kuerzel: String, _ tun: @escaping () -> Void, an: Bool = false) -> some View {
        Button(action: tun) {
            VStack(spacing: 6) {
                Image(systemName: bild).font(.system(size: an ? 8 : 15)).foregroundStyle(an ? TafelFarbe.jetzt : TafelFarbe.akzent).frame(height: 18)
                Text(titel).font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.text).lineLimit(1)
                Text(kuerzel).font(Schrift.mono(10.5)).foregroundStyle(an ? TafelFarbe.jetzt : TafelFarbe.leise)
            }
            .padding(.top, 12).padding(.bottom, 10).padding(.horizontal, 6).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MenueKarte: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1))
    }
}

struct SnMenueBild: View {
    var stand: SenecaStand
    var art: String

    var body: some View {
        let meeting = art == "menue-meeting" ? ("12:04", MeetingSegment(start: 0, ende: 1, sprecher: 1, text: "Und die Domain, wer verlängert die")) : nil
        let z = MenueZeichen.entscheide(diktat: .ruht, meetingNimmtAuf: meeting != nil, meetingDauer: 724, meetingArbeitet: false, braucht: stand.zaehler?.braucht ?? 0, fokus: stand.ruhe?.grund == "fokus")
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [TafelFarbe.hex(0x48618A), TafelFarbe.hex(0x1D2A44)], startPoint: .topLeading, endPoint: .bottom)
            HStack(spacing: 18) {
                Spacer()
                HStack(spacing: 6) {
                    SnKugel(groesse: 12, atmet: false)
                    if let p = z.punkt { Image(nsImage: MenueZeichenModell.punkt(p)) } else { Image(systemName: z.symbol) }
                    if let t = z.text { Text(t).monospacedDigit() }
                }
                .padding(.horizontal, 8).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.16)))
                Text("Do. 26. Nov. \(HeuteTafelLogik.uhr(stand.jetzt))").monospacedDigit()
            }
            .font(Schrift.grotesk(14, .medium)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 28).background(Color.black.opacity(0.25))
            MenueTafel(stand: stand, verbunden: true, meeting: meeting) {
                HStack(spacing: 10) {
                    SnKugel(groesse: 10, atmet: false)
                    Text("Frag Seneca etwas").font(Schrift.grotesk(14.5)).foregroundStyle(TafelFarbe.leise)
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .padding(.leading, 14).padding(.trailing, 8).frame(height: 44).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).shadow(color: .black.opacity(0.7), radius: 35, y: 30)
            .padding(.leading, 470).padding(.top, 36)
        }
    }
}
