import SwiftUI

struct MeetingView: View {
    @ObservedObject var dienst: MeetingDienst
    @State private var frage = ""

    var body: some View {
        ZStack {
            Farbe.grund.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kopf
                    if let v = dienst.vorschlag, !dienst.beschaeftigt { vorschlag(v) }
                    if case .fehler(let t) = dienst.zustand { warnung(t) }
                    if dienst.nimmtAuf { laufend }
                    if case .wertAus(let t) = dienst.zustand {
                        HStack(spacing: 12) {
                            Text(t).font(Schrift.serif(16, kursiv: true)).foregroundStyle(Farbe.ink2)
                            if dienst.ablage != nil {
                                Button("Abbrechen") { dienst.brichZusammenfassungAb() }.buttonStyle(.plain).font(Schrift.grotesk(12)).foregroundStyle(Farbe.himmel)
                                    .accessibilityIdentifier("meeting-zusammenfassung-abbrechen")
                            }
                        }
                    }
                    if dienst.ablage != nil { ergebnis }
                    ForEach(Array(dienst.hinweise.enumerated()), id: \.offset) { _, h in
                        Text(h).font(Schrift.grotesk(12)).foregroundStyle(Farbe.warnText).fixedSize(horizontal: false, vertical: true)
                    }
                    if !dienst.nimmtAuf, !dienst.fruehere.isEmpty { fruehere }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .preferredColorScheme(.dark)
        .task { dienst.ladeFruehere() }
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

    private var laufend: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { g in
                Capsule().fill(Farbe.pille).overlay(alignment: .leading) {
                    Capsule().fill(Farbe.himmel).frame(width: max(4, g.size.width * min(1, dienst.pegel)))
                }
            }
            .frame(height: 5)
            ScrollView {
                Text(dienst.live.isEmpty ? "Das Gespräch erscheint hier, sobald jemand spricht." : MeetingTranskript.text(MeetingTranskript.letzte(dienst.live, minuten: 3)))
                    .font(Schrift.grotesk(12.5)).foregroundStyle(dienst.live.isEmpty ? Farbe.ink3 : Farbe.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 170)
            .padding(12).snGlas(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            nachfragen
        }
    }

    private var nachfragen: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Frag Seneca … (z. B. „Was wurde zuletzt gesagt?“)", text: $frage)
                .textFieldStyle(.plain).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink)
                .padding(.horizontal, 14).padding(.vertical, 10).background(Farbe.feld, in: Capsule())
                .onSubmit { let f = frage; frage = ""; Task { await dienst.frage(f) } }
                .accessibilityIdentifier("meeting-frage")
            ForEach(dienst.antworten.suffix(3)) { a in
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.frage).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                    Text(a.laedt ? "Einen Moment …" : a.text).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var ergebnis: some View {
        if let a = dienst.ablage {
            let e = a.ergebnis
            VStack(alignment: .leading, spacing: 12) {
                Text(e.titel).font(Schrift.serif(20, kursiv: true)).foregroundStyle(Farbe.ink1)
                switch e.stand {
                case .laeuft:
                    Text("Die Mitschrift ist abgelegt. Die Zusammenfassung wird noch erstellt …").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                case .ohneZusammenfassung(let grund):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Die Zusammenfassung fehlt (\(grund)). Die Mitschrift ist abgelegt.")
                            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.warnText).fixedSize(horizontal: false, vertical: true)
                        Button("Erneut zusammenfassen") { Task { await dienst.erneutZusammenfassen() } }
                            .buttonStyle(NebenKnopfStil()).disabled(dienst.beschaeftigt).accessibilityIdentifier("meeting-erneut-zusammenfassen")
                    }
                case .vollstaendig:
                    if !e.segmente.isEmpty { zusammenfassung(e) }
                }
                mitschrift(e)
                HStack(spacing: 14) {
                    Text(a.datei.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(Schrift.mono(11)).foregroundStyle(Farbe.ink3).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("Datei öffnen") { dienst.oeffneDatei() }.buttonStyle(.plain).font(Schrift.grotesk(12)).foregroundStyle(Farbe.himmel)
                        .accessibilityIdentifier("meeting-datei-oeffnen")
                    Button("Im Finder zeigen") { dienst.zeigeInFinder() }.buttonStyle(.plain).font(Schrift.grotesk(12)).foregroundStyle(Farbe.himmel)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .snGlas(RoundedRectangle(cornerRadius: Mass.radius, style: .continuous))
        }
    }

    @ViewBuilder private func zusammenfassung(_ e: MeetingErgebnis) -> some View {
        let alle = e.alleAufgaben.isEmpty ? e.aufgaben.map { MeetingAufgabe(wer: "Antonio", text: $0, termin: nil) } : e.alleAufgaben
        liste("Worum es ging", e.zusammenfassung.isEmpty ? [] : [e.zusammenfassung], punkte: false)
        liste("Entscheidungen", e.entscheidungen)
        liste("Aufgaben", alle.map { ($0.fuerAntonio ? "Antonio" : $0.wer) + ": " + $0.alsToDo })
        if !e.aufgaben.isEmpty {
            HStack {
                Button(e.aufgaben.count == 1 ? "Antonios Aufgabe als To-do an Seneca" : "Antonios \(e.aufgaben.count) Aufgaben als To-do an Seneca") {
                    Task { await dienst.uebergebeAufgaben(trocken: false) }
                }
                .buttonStyle(NebenKnopfStil()).disabled(dienst.uebernommen > 0).accessibilityIdentifier("meeting-todo")
                if !dienst.uebernahme.isEmpty { Text(dienst.uebernahme).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3) }
            }
        }
        liste("Offene Fragen", e.offeneFragen)
    }

    private func liste(_ titel: String, _ zeilen: [String], punkte: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Abschnittstitel(text: titel)
            if zeilen.isEmpty { Text("keine").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3) }
            ForEach(Array(zeilen.enumerated()), id: \.offset) { _, t in
                Text((punkte ? "• " : "") + t).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func mitschrift(_ e: MeetingErgebnis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Abschnittstitel(text: "Mitschrift")
            if e.segmente.isEmpty {
                Text("Nichts erkannt.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(e.segmente.enumerated()), id: \.offset) { _, s in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.sprecherName + " · " + MeetingTranskript.zeit(s.start)).font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                                Text(s.text).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .padding(12).snGlas(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                .accessibilityIdentifier("meeting-mitschrift")
            }
        }
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
