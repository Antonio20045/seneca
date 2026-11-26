import SwiftUI
import AppKit
import UserNotifications

struct EinstellungenView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var dienste: MacDienste
    @ObservedObject var einst: MacEinstellungen
    @ObservedObject var diktat: DiktatDienst
    @ObservedObject var diktatEinst: DiktatEinstellungen
    @ObservedObject var rechte: DiktatRechte
    @State private var frageEntfernen = false
    @State private var entfernt = false
    @State private var mikrofone: [MikrofonAuswahl.Geraet] = []
    @State private var schluesselDa = false

    init(modell: AppModell) {
        self.modell = modell
        self.dienste = modell.dienste
        self.einst = modell.dienste.einstellungen
        self.diktat = DiktatDienst.gemeinsam
        self.diktatEinst = DiktatDienst.gemeinsam.einstellungen
        self.rechte = DiktatRechte.gemeinsam
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                abschnitt("Verbindung") { verbindung }
                abschnitt("Schnellfrage") { kuerzel }
                abschnitt("Spracheingabe") { spracheingabe }
                abschnitt("Mikrofon") { mikrofon }
                abschnitt("Mitteilungen") { mitteilungen }
                abschnitt("Dock") {
                    schalter("Zahl „braucht dich“ am Dock-Symbol", $einst.dockZahl).accessibilityIdentifier("einst-dock")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 780)
        .background(Farbe.grund)
        .tint(Farbe.himmel)
        .toggleStyle(.switch)
        .task { while !Task.isCancelled { rechte.aktualisiere(); try? await Task.sleep(for: .seconds(1.5)) } }
        .task { schluesselDa = await Zugang.schluesselAbseits() != nil }
        .task { mikrofone = MikrofonGeraete.verfuegbare() }
        .preferredColorScheme(.dark)
        .confirmationDialog("Zugangsschlüssel entfernen?", isPresented: $frageEntfernen, titleVisibility: .visible) {
            Button("Schlüssel entfernen", role: .destructive) { entferneSchluessel() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Eintrag verschwindet aus dem Schlüsselbund. Danach musst du Seneca neu verbinden.")
        }
    }

    private func abschnitt<I: View>(_ titel: String, @ViewBuilder _ inhalt: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Abschnittstitel(text: titel)
            VStack(alignment: .leading, spacing: 12) { inhalt() }
                .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.linie2, lineWidth: 1))
        }
    }

    private func schalter(_ titel: String, _ an: Binding<Bool>) -> some View {
        HStack { Text(titel); Spacer(); Toggle(titel, isOn: an).labelsHidden() }
    }

    private var zustandText: String {
        switch modell.zustand {
        case .bereit: return "Verbunden"
        case .verbindet: return "Verbindet …"
        case .einrichten: return "Nicht eingerichtet"
        case .fehler: return "Nicht verbunden"
        }
    }

    @ViewBuilder private var verbindung: some View {
        HStack(spacing: 8) {
            Circle().fill(modell.zustand == .bereit ? Farbe.gruen : Farbe.bernstein).frame(width: 8, height: 8)
            Text(zustandText).accessibilityIdentifier("einst-zustand")
        }
        HStack {
            Text("Adresse").foregroundStyle(Farbe.ink2)
            Spacer()
            Text(Zugang.adresse ?? modell.adresse).font(Schrift.mono(13)).foregroundStyle(Farbe.ink).textSelection(.enabled)
                .accessibilityIdentifier("einst-adresse")
        }
        HStack {
            Text("Zugangsschlüssel").foregroundStyle(Farbe.ink2)
            Spacer()
            Text(entfernt || !schluesselDa ? "nicht gespeichert" : "im Schlüsselbund").foregroundStyle(Farbe.ink)
                .accessibilityIdentifier("einst-schluessel")
        }
        HStack(spacing: 10) {
            Button("Erneut verbinden") { Task { await modell.verbinde() } }.buttonStyle(NebenKnopfStil())
                .disabled(modell.zustand == .einrichten || modell.zustand == .verbindet)
            Button("Schlüssel entfernen …") { frageEntfernen = true }.buttonStyle(NebenKnopfStil())
                .disabled(!schluesselDa)
                .accessibilityIdentifier("einst-entfernen")
        }
    }

    func entferneSchluessel() {
        modell.zugangZuruecksetzen()
        entfernt = true
        schluesselDa = false
    }

    @ViewBuilder private var kuerzel: some View {
        Text("Dieses Kürzel öffnet das Schnellfrage-Feld, auch wenn eine andere App vorne ist. Es braucht keine Freigabe in den Systemeinstellungen.")
            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            KuerzelAufnehmer(kuerzel: $einst.kuerzel)
            Button("Vorgabe (⌥ Leertaste)") { einst.kuerzel = .standard }.buttonStyle(NebenKnopfStil()).disabled(einst.kuerzel == .standard)
            Button("Aus") { einst.kuerzel = nil }.buttonStyle(NebenKnopfStil()).disabled(einst.kuerzel == nil)
        }
        if dienste.kuerzel.aktuell != nil, dienste.kuerzel.status != noErr {
            Text("Dieses Kürzel ist schon vergeben. Wähle ein anderes.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle)
        }
    }

    @ViewBuilder private var mikrofon: some View {
        Text("Welches Mikrofon Diktat und Meeting benutzen. Ein Bluetooth-Headset kann mitten in der Aufnahme aussetzen; das eingebaute Mikrofon ist darum die Vorgabe.")
            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
        Picker("Mikrofon", selection: $einst.mikrofonQuelle) {
            Text(MikrofonAuswahl.anzeigeName(fuer: .eingebaut, verfuegbare: mikrofone)).tag(MikrofonQuelle.eingebaut)
            Text(MikrofonAuswahl.anzeigeName(fuer: .systemstandard, verfuegbare: mikrofone)).tag(MikrofonQuelle.systemstandard)
            ForEach(mikrofone.filter { !$0.istEingebaut }, id: \.uid) { g in
                Text(g.name).tag(MikrofonQuelle.geraet(g.uid))
            }
        }
        .labelsHidden().frame(maxWidth: 320).accessibilityIdentifier("einst-mikrofon")
    }

    @ViewBuilder private var spracheingabe: some View {
        Text("Tippe einmal kurz auf die rechte ⌘-Taste: Seneca nimmt auf, in jeder App. Tippe noch einmal: der Text wird auf diesem Mac erkannt (Parakeet v3, deutsch) und dort eingefügt, wo dein Cursor steht. Escape bricht ab. Nichts geht ins Netz. Läuft auch, wenn das Fenster zu ist.")
            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
        schalter("Spracheingabe (Diktat)", $diktatEinst.an).accessibilityIdentifier("einst-diktat")
        Text("Nur ein Tippen der rechten ⌘ allein (unter 0,4 Sekunden, keine andere Taste dazu) zählt. ⌘C, ⌘Tab und andere Kürzel lösen nichts aus.")
            .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
        recht("Mikrofon", "zum Aufnehmen", ok: rechte.mikrofonErteilt, art: .mikrofon, kennung: "einst-diktat-mikrofon")
        recht("Eingabeüberwachung", "damit das Tippen der rechten ⌘ in anderen Apps bemerkt wird", ok: rechte.eingabe, art: .eingabe, kennung: "einst-diktat-eingabe")
        recht("Bedienungshilfen", "um den Text in andere Apps einzufügen", ok: rechte.bedienung, art: .bedienung, kennung: "einst-diktat-bedienung")
        if !rechte.eingabe, rechte.bedienung {
            Text("Eingabeüberwachung fehlt, aber Bedienungshilfen genügen für die Tasten-Erkennung.")
                .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 8) {
            Circle().fill(diktat.modellBereit ? Farbe.gruen : Farbe.bernstein).frame(width: 8, height: 8)
            Text(diktat.modellBereit ? "Sprachmodell geladen" : "Sprachmodell lädt …")
                .accessibilityIdentifier("einst-diktat-modell")
        }
        if let f = diktat.modellFehler {
            Text(f).font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func recht(_ name: String, _ wozu: String, ok: Bool, art: DiktatRechte.Art, kennung: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(ok ? Farbe.gruen : Farbe.koralle).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(name): \(ok ? "erteilt" : "nicht erteilt")").foregroundStyle(Farbe.ink1)
                Text(wozu).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
            Spacer()
            if !ok {
                Button("Freigeben …") { Task { await rechte.frage(art) } }.buttonStyle(NebenKnopfStil())
            }
            Button("Systemeinstellungen") { rechte.oeffne(art) }.buttonStyle(NebenKnopfStil())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(kennung)
    }

    @ViewBuilder private var mitteilungen: some View {
        schalter("Mitteilungen von Seneca", Binding(get: { einst.mitteilungenAn }, set: { dienste.setzeMitteilungen($0) }))
            .accessibilityIdentifier("einst-mitteilungen")
        Group {
            schalter("Neue Entscheidung", $einst.artEntscheidung)
            schalter("Fertiger Lauf mit Bericht", $einst.artBericht)
            schalter("Störung", $einst.artStoerung)
        }
        .padding(.leading, 18).disabled(!einst.mitteilungenAn)
        schalter("Aufgaben melden (fertig, abgebrochen, hängt, Frage)", Binding(get: { einst.aufgabenMelden }, set: { dienste.setzeAufgabenMelden($0) }))
            .accessibilityIdentifier("einst-aufgaben-melden")
        Text("Es gibt sie nur, solange Seneca läuft. Ein Klick öffnet die Stelle in der App.")
            .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
        if let h = dienste.mitteilungsHinweis {
            Text(h).font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KuerzelAufnehmer: View {
    @Binding var kuerzel: Kuerzel?
    @State private var hoert = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            hoert ? stoppe() : starte()
        } label: {
            Text(hoert ? "Tasten drücken …" : (kuerzel?.beschreibung ?? "aus"))
                .font(Schrift.grotesk(14, .medium)).foregroundStyle(hoert ? Farbe.himmel : Farbe.ink)
                .frame(minWidth: 130)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Farbe.feld, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(hoert ? Farbe.himmel.opacity(0.6) : Farbe.linie, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Kurve.ease(), value: hoert)
        .accessibilityIdentifier("einst-kuerzel")
        .onDisappear { stoppe() }
    }

    private func starte() {
        hoert = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stoppe(); return nil }
            if let k = Kuerzel.aus(tastencode: e.keyCode, cocoaModifier: e.modifierFlags.rawValue, zeichen: e.charactersIgnoringModifiers) {
                kuerzel = k
                stoppe()
            }
            return nil
        }
    }

    private func stoppe() {
        hoert = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
