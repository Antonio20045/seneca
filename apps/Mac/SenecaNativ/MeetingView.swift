import SwiftUI

struct MeetingView: View {
    @ObservedObject var dienst: MeetingDienst

    var body: some View {
        ZStack {
            Farbe.grund.ignoresSafeArea()
            if dienst.nimmtAuf { MeetingLiveTafel(dienst: dienst, live: dienst.live, marken: dienst.marken, luecken: dienst.luecken, antworten: dienst.antworten, dauer: dienst.dauer) } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kopf
                    if let v = dienst.vorschlag, !dienst.beschaeftigt { vorschlag(v) }
                    if case .fehler(let t) = dienst.zustand { warnung(t) }
                    if let b = dienst.bescheid { MeetingKarte { Text("Sag \(b) kurz, dass Seneca mitschreibt.").font(Schrift.grotesk(15)).foregroundStyle(.white)
                        HStack(spacing: 10) { Button("Gesagt, los") { dienst.bescheidGesagt(true) }.buttonStyle(MeetingKnopf()); Button("Doch nicht") { dienst.bescheidGesagt(false) }.buttonStyle(MeetingKnopf(voll: false)) } } }
                    if case .wertAus(let t) = dienst.zustand, dienst.fasstSeit == nil { Text(t).font(Schrift.serif(16, kursiv: true)).foregroundStyle(Farbe.ink2) }
                    if let a = dienst.ablage { SnMeetingErgebnis(e: a.ergebnis, datei: a.datei, dienst: dienst, zurueck: nil) }
                    ForEach(Array(dienst.hinweise.enumerated()), id: \.offset) { _, h in
                        Text(h).font(Schrift.grotesk(12)).foregroundStyle(Farbe.warnText).fixedSize(horizontal: false, vertical: true)
                    }
                    if !dienst.nimmtAuf, !dienst.fruehere.isEmpty { fruehere }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .preferredColorScheme(.dark)
        .task { dienst.ladeFruehere() }
        .onAppear { dienst.fensterOffen = true }.onDisappear { dienst.fensterOffen = false }
    }

    private var kopf: some View {
        HStack(spacing: 14) {
            SnKugel(groesse: 38, atmet: dienst.nimmtAuf)
            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting").font(Schrift.serif(26, kursiv: true)).foregroundStyle(Farbe.ink1)
                Text(untertitel).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
            }
            Spacer()
            if dienst.nimmtAuf {
                Button("Beenden") { Task { await dienst.stoppe() } }.buttonStyle(HauptKnopfStil()).accessibilityIdentifier("meeting-stopp")
            } else if !dienst.beschaeftigt {
                Button(dienst.ablage == nil ? "Meeting aufnehmen" : "Neue Aufnahme") { Task { await dienst.starte() } }
                    .buttonStyle(HauptKnopfStil()).accessibilityIdentifier("meeting-start")
            }
        }
    }

    private var untertitel: String {
        switch dienst.zustand {
        case .ruht, .fehler: return "Bleibt auf diesem Mac. Nichts geht ins Netz."
        case .startet: return "Startet …"
        case .nimmtAuf: return "Nimmt auf · " + MeetingTranskript.zeit(dienst.dauer)
        case .wertAus: return "Wird ausgewertet"
        case .fertig: return "Fertig"
        }
    }

    private func vorschlag(_ app: String) -> some View {
        HStack {
            Text("Das Mikrofon läuft in \(app). Soll ich das Gespräch aufnehmen?").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink)
            Spacer()
            Button("Aufnehmen") { Task { await dienst.starte() } }.buttonStyle(NebenKnopfStil())
            Button("Nein") { dienst.vorschlagVerwerfen() }.buttonStyle(.plain).foregroundStyle(Farbe.ink3)
        }
        .padding(12).snGlas(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
    }

    private func warnung(_ t: String) -> some View {
        Text(t).font(Schrift.grotesk(13)).foregroundStyle(Farbe.warnText).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Farbe.warnFlaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.warnKante, lineWidth: 1))
    }

    private static let datum: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d. MMM yyyy, HH:mm 'Uhr'"
        return f
    }()

    private var fruehere: some View {
        VStack(alignment: .leading, spacing: 10) {
            Abschnittstitel(text: "Frühere Aufnahmen")
            Text("„Auswerten“ erzeugt Mitschrift und Zusammenfassung neu aus dem gespeicherten Ton. Eine Datei, die die App zu dieser Aufnahme angelegt hat, wird ersetzt (ihr alter Stand bleibt im Aufnahmeordner gesichert); ältere Dateien bleiben unverändert, die neue liegt daneben.")
                .font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
            ForEach(dienst.fruehere.prefix(8)) { a in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.datum.string(from: a.beginn) + " · " + MeetingDokument.dauerText(a.dauer)).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink)
                        Text(a.standText).font(Schrift.grotesk(11.5)).foregroundStyle(a.stand == .vollstaendig ? Farbe.ink3 : Farbe.warnText)
                    }
                    Spacer()
                    if a.dokument != nil {
                        Button("Datei öffnen") { dienst.oeffne(a) }.buttonStyle(.plain).font(Schrift.grotesk(12)).foregroundStyle(Farbe.himmel)
                    }
                    Button(a.stand == .ohneDatei ? "Auswerten" : "Erneut auswerten") { Task { await dienst.werteErneutAus(a) } }
                        .buttonStyle(NebenKnopfStil()).disabled(dienst.beschaeftigt).accessibilityIdentifier("meeting-erneut-\(a.name)")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .snGlas(RoundedRectangle(cornerRadius: Mass.radius, style: .continuous))
    }
}

struct MeetingLueckeZeile: View {
    var dauer: Double
    var body: some View {
        Text("— LÜCKE \(VerlaufLogik.uhrDauer(dauer)) · MIKROFON GEWECHSELT —").font(Schrift.mono(10)).kerning(1.1).foregroundStyle(TafelFarbe.leise)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
    }
}

struct MeetingLiveTafel: View {
    var dienst: MeetingDienst?
    var live: [MeetingSegment]
    var marken: [TimeInterval]
    var luecken: [[Double]] = []
    var antworten: [MeetingDienst.Antwort]
    var dauer: TimeInterval
    var beginn = Date()
    @State private var frage = ""

    private func uhr(_ s: Double) -> String { HeuteTafelLogik.uhr((beginn.timeIntervalSince1970 - dauer + s) * 1000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(TafelFarbe.jetzt).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.jetzt.opacity(0.18)).frame(width: 16, height: 16))
                Text("AUFNAHME · \(MeetingTranskript.zeit(dauer))").font(Schrift.mono(13)).kerning(1.2).foregroundStyle(.white).monospacedDigit()
                Spacer()
            }
            Text("Du sprichst ins Mikrofon, das Gegenüber kommt über den Systemton. So trennt Seneca die Stimmen schon jetzt.").font(Schrift.grotesk(12)).lineHeight(.exact(points: 16)).foregroundStyle(TafelFarbe.leise)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18).padding(.bottom, 18)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if live.isEmpty { Text("Das Gespräch erscheint hier, sobald jemand spricht.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise) }
                    let zeilen = MeetingTranskript.letzte(live, minuten: 5)
                    ForEach(Array(zeilen.enumerated()), id: \.offset) { i, z in
                        if let l = luecken.first(where: { $0[0] <= z.start && $0[0] > (i > 0 ? zeilen[i - 1].start : -1) }) { MeetingLueckeZeile(dauer: l[1]) }
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(uhr(z.start)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).frame(width: 52, alignment: .leading)
                            Text(z.sprecher == 1 ? "Du" : z.sprecherName).font(Schrift.grotesk(14, .medium)).foregroundStyle(.white).lineLimit(1).frame(width: 88, alignment: .leading)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(z.text).font(Schrift.grotesk(14)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                                if marken.contains(where: { $0 >= z.start - 1 && $0 <= z.ende + 2 }) {
                                    Label("GEMERKT", systemImage: "bookmark").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.akzent).padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(TafelFarbe.himmel.opacity(0.16))).fixedSize()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
            }
            if let n = dienst?.endetIn {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) { Text("Anruf beendet").font(Schrift.grotesk(15, .medium)).foregroundStyle(.white); Text("· Aufnahme endet in \(n) s").font(Schrift.grotesk(13.5)).foregroundStyle(TafelFarbe.leise); Spacer()
                        Button("Weiter aufnehmen") { dienst?.weiterAufnehmen() }.buttonStyle(MeetingKnopf(voll: false)) }
                    GeometryReader { g in Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.himmel).frame(width: g.size.width * Double(n) / MeetingDienst.regel("meeting_ende_s", 10)) } }.frame(height: 2)
                }
                .padding(.horizontal, 18).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))).padding(.top, 12)
            }
            if dienst?.ohneSystemton == true {
                MeetingKarte { Text("Ich höre nur dich. Für die Stimme deines Gegenübers brauche ich die Freigabe für Systemton.").font(Schrift.grotesk(14)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Button("Freigabe öffnen") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }.buttonStyle(MeetingKnopf()) }.padding(.top, 12)
            }
            if let a = antworten.last {
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.frage).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                    Text(a.laedt ? "Einen Moment …" : a.text).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("NUR DU SIEHST DAS").font(Schrift.mono(10)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.horizontal, 15).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))).padding(.top, 12)
            }
            HStack(spacing: 10) {
                TextField("", text: $frage, prompt: Text("Frag Seneca zum Gespräch …").foregroundColor(TafelFarbe.leise))
                    .textFieldStyle(.plain).font(Schrift.grotesk(13.5)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 38)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .onSubmit { let f = frage; frage = ""; Task { await dienst?.frage(f) } }.accessibilityIdentifier("meeting-frage")
                Button { dienst?.merke() } label: { HStack(spacing: 6) { Text("Merken"); MeetingTaste(t: "⌘⇧M") } }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.text).padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)).keyboardShortcut("m", modifiers: [.command, .shift])
                Button { dienst?.umschalten() } label: { HStack(spacing: 6) { Text("Beenden"); MeetingTaste(t: "⌘⇧R", farbe: TafelFarbe.aufHimmel) } }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(.white)).accessibilityIdentifier("meeting-stopp")
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZStack {
            LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [TafelFarbe.himmel.opacity(0.26), TafelFarbe.himmel.opacity(0.11), .clear], center: UnitPoint(x: 0.76, y: 0.1), startRadius: 0, endRadius: 260)
        }.ignoresSafeArea())
    }
}

struct MeetingTaste: View {
    var t: String
    var farbe = TafelFarbe.zweit
    var body: some View {
        Text(t).font(Schrift.mono(11)).foregroundStyle(farbe).padding(.horizontal, 6).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
    }
}
