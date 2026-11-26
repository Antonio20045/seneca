import SwiftUI

@MainActor
final class AufgabenModell: ObservableObject {
    static let gemeinsam = AufgabenModell()

    @Published private(set) var liste: AufgabenListe?
    @Published private(set) var einmalGelesen = false
    @Published private(set) var lesbar = true
    private var laedt = false
    private var schleifeLaeuft = false

    static var befehl: URL { TageslaufHaken.ordner.appendingPathComponent("aufgaben.py") }
    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("aufgaben.json") }

    init() {
        guard TageslaufModell.erlaubt || (Hintergrund.aktiv && Messung.aktiv && MacPfade.pruefinstanz), let url = Self.datei, let d = try? Data(contentsOf: url) else { return }
        liste = AufgabenListe.lies(d)
    }

    func beobachte() async {
        guard TageslaufModell.erlaubt, !schleifeLaeuft else { return }
        schleifeLaeuft = true
        defer { schleifeLaeuft = false }
        while !Task.isCancelled {
            await lade()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    func lade() async {
        guard TageslaufModell.erlaubt, !laedt else { return }
        laedt = true
        defer { laedt = false }
        let daten = await Kindprozess.laufe(Self.befehl, ["liste"], limit: 15)
        let alt = liste
        var ergebnisGeaendert = false
        let ergebnis = await Task.detached(priority: .utility) { () -> (AufgabenListe, Bool)? in
            guard let daten, let n = AufgabenListe.lies(daten) else { return nil }
            return (n, n != alt)
        }.value
        if let daten, let (neu, geaendert) = ergebnis {
            if geaendert { liste = neu }
            ergebnisGeaendert = geaendert
            if !lesbar { lesbar = true }
            if geaendert, let url = Self.datei { Task.detached(priority: .utility) { try? daten.write(to: url, options: .atomic) } }
        } else if lesbar {
            lesbar = false
        }
        if !einmalGelesen { einmalGelesen = true }
        if let l = liste, lesbar { await AufgabenMelder.gemeinsam.pruefe(l, geaendert: ergebnisGeaendert) }
    }
}

struct SnAbschnittKopf: View {
    let titel: String
    let zahl: Int
    var warn = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titel.uppercased()).font(Schrift.grotesk(12, .medium)).tracking(0.9).foregroundStyle(warn ? Farbe.bernstein : Farbe.ink2)
            Text("\(zahl)").font(Schrift.mono(12)).foregroundStyle(Farbe.ink3)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

struct SnAufgabenZeile: View {
    let aufgabe: Aufgabe
    var jetzt = Date()
    var oeffne: (String) -> Void = { _ in }
    @State private var teileOffen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { oeffne(aufgabe.id) } label: {
                Group { if aufgabe.zustand.erledigt { erledigt } else { offen } }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .buttonStyle(SnZeilenStil())
            .padding(.horizontal, -10)
            .help(aufgabe.titel)
            if !aufgabe.zustand.erledigt, !aufgabe.teile.isEmpty { teile }
        }
        .accessibilityIdentifier("aufgabe-zeile")
    }

    private var offen: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(aufgabe.titel).font(Schrift.grotesk(15)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.tail)
            let was = aufgabe.wasUndSeit(jetzt: jetzt)
            if !was.isEmpty { Text(was).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(1).truncationMode(.tail) }
            if let z = aufgabe.zusatz(jetzt: jetzt) {
                Text(z.text).font(Schrift.grotesk(12.5)).foregroundStyle(z.haengt ? Farbe.warnText : (aufgabe.zustand == .brauchtDich ? Farbe.bernstein : Farbe.ink2))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }
        }
    }

    private var erledigt: some View {
        let ab = aufgabe.zustand == .abgebrochen
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: ab ? "xmark" : "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(ab ? Farbe.koralle : Farbe.ink3).frame(width: 12)
                    .accessibilityHidden(true)
                Text(aufgabe.titel).font(Schrift.grotesk(14.5)).foregroundStyle(ab ? Farbe.ink2 : Color.white).lineLimit(1).truncationMode(.tail)
                if ab { Text("abgebrochen").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(1).fixedSize() }
                Spacer(minLength: 8)
                Text(aufgabe.abschlussUhr(jetzt: jetzt)).font(Schrift.mono(12)).foregroundStyle(Farbe.ink3).lineLimit(1).fixedSize()
            }
            if let h = aufgabe.fertigHinweis {
                Text(h).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(1).truncationMode(.tail).padding(.leading, 20)
            }
            if ab, let g = aufgabe.grund {
                Text(g).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20).multilineTextAlignment(.leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var teile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Kurve.sn(0.3)) { teileOffen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(teileOffen ? 90 : 0)).frame(width: 10)
                    Text(aufgabe.teileZaehlzeile).font(Schrift.grotesk(12.5)).lineLimit(1)
                }
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .foregroundStyle(Farbe.ink3)
            .accessibilityIdentifier("aufgabe-teile")
            if teileOffen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(aufgabe.teile) { t in
                        HStack(spacing: 8) {
                            Text(t.titel).font(Schrift.grotesk(13)).foregroundStyle(t.zustand.erledigt ? Farbe.ink3 : Farbe.ink1).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(t.zustand.wort).font(Schrift.grotesk(12)).foregroundStyle(t.zustand == .haengt ? Farbe.warnText : Farbe.ink3).lineLimit(1).fixedSize()
                        }
                        .padding(.vertical, 4)
                        .help(t.titel)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Farbe.linie).frame(width: 1) }
                .padding(.leading, 4).padding(.bottom, 4)
            }
        }
    }
}

struct SnAufgabenAbschnitt: View {
    let titel: String
    let aufgaben: [Aufgabe]
    var hoechstens: Int? = nil
    var warn = false
    var jetzt = Date()
    var oeffne: (String) -> Void = { _ in }
    var zeigeVoll: () -> Void = {}

    var body: some View {
        let sichtbar = hoechstens.map { Array(aufgaben.prefix($0)) } ?? aufgaben
        VStack(alignment: .leading, spacing: 4) {
            SnAbschnittKopf(titel: titel, zahl: aufgaben.count, warn: warn).padding(.bottom, 4)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sichtbar) { SnAufgabenZeile(aufgabe: $0, jetzt: jetzt, oeffne: oeffne) }
            }
            if let h = hoechstens, aufgaben.count > h {
                Button(action: zeigeVoll) {
                    HStack(spacing: 6) {
                        Text("und \(aufgaben.count - h) weitere").font(Schrift.grotesk(13))
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .accessibilityIdentifier("aufgaben-weitere")
            }
        }
    }
}

struct SnAufgabenHinweis: View {
    let text: String
    var body: some View { Text(text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3).padding(.vertical, 6) }
}

struct SnAufgabenHeute: View {
    let liste: AufgabenListe?
    var lesbar = true
    var wirdGelesen = false
    var jetzt = Date()
    var oeffne: (String) -> Void = { _ in }
    var zeigeVoll: () -> Void = {}
    private let hoechstens = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            if let liste {
                let a = liste.antonio
                if !lesbar { SnAufgabenHinweis(text: "Aufgaben sind gerade nicht lesbar. Du siehst den letzten Stand.") }
                offeneAbschnitte(liste)
                if !a.neu.isEmpty { abschnitt("Neu seit deinem letzten Blick", a.neu).snNeuSichtbar("heute", ids: Set(a.neu.map(\.id))) }
                if !a.istLeer || !liste.agenten.istLeer {
                    Button(action: zeigeVoll) {
                        HStack(spacing: 6) {
                            Text("Alle Aufgaben").font(Schrift.grotesk(13.5))
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(SnLeiserStil())
                    .accessibilityIdentifier("aufgaben-alle")
                }
            } else {
                SnAufgabenHinweis(text: wirdGelesen ? "Die Aufgaben werden gelesen." : "Aufgaben sind gerade nicht lesbar.")
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aufgaben-heute")
    }

    @ViewBuilder private func offeneAbschnitte(_ liste: AufgabenListe) -> some View {
        SnOffeneArbeit(aufgaben: liste.offeneArbeit(), hoechstens: hoechstens, jetzt: jetzt, oeffne: oeffne, zeigeVoll: zeigeVoll)
    }

    private func abschnitt(_ titel: String, _ z: [Aufgabe], warn: Bool = false) -> some View {
        SnAufgabenAbschnitt(titel: titel, aufgaben: z, hoechstens: hoechstens, warn: warn, jetzt: jetzt, oeffne: oeffne, zeigeVoll: zeigeVoll)
    }
}

struct SnOffeneArbeit: View {
    let aufgaben: [Aufgabe]
    var hoechstens: Int? = nil
    var jetzt: Date
    var oeffne: (String) -> Void
    var zeigeVoll: () -> Void = {}

    var body: some View {
        gruppe("Läuft", .laeuft)
        gruppe("Braucht dich", .brauchtDich)
        gruppe("Blockiert", .haengt)
        gruppe("Wartet", .wartet)
    }

    @ViewBuilder private func gruppe(_ titel: String, _ zustand: AufgabenZustand) -> some View {
        let zeilen = aufgaben.filter { $0.zustand == zustand }
        if !zeilen.isEmpty {
            SnAufgabenAbschnitt(titel: titel, aufgaben: zeilen, hoechstens: hoechstens, warn: zustand == .brauchtDich,
                                jetzt: jetzt, oeffne: oeffne, zeigeVoll: zeigeVoll)
        }
    }
}

struct SnAufgabenVoll: View {
    let liste: AufgabenListe?
    var lesbar = true
    var wirdGelesen = false
    var jetzt = Date()
    var oeffne: (String) -> Void = { _ in }
    var agentenOffenZuBeginn = false
    var zuletztOffenZuBeginn = false
    @State private var agentenOffen = false
    @State private var zuletztOffen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            if let liste {
                if !lesbar { SnAufgabenHinweis(text: "Aufgaben sind gerade nicht lesbar. Du siehst den letzten Stand.") }
                let a = liste.antonio
                SnOffeneArbeit(aufgaben: liste.offeneArbeit(), jetzt: jetzt, oeffne: oeffne)
                if !a.neu.isEmpty { SnAufgabenAbschnitt(titel: "Neu seit deinem letzten Blick", aufgaben: a.neu, jetzt: jetzt, oeffne: oeffne).snNeuSichtbar("voll", ids: Set(a.neu.map(\.id))) }
                if !liste.agenten.neu.isEmpty || !liste.agenten.zuletzt.isEmpty { agenten(liste.agenten) }
                if !a.zuletzt.isEmpty { zuletzt(a.zuletzt) }
            } else {
                SnAufgabenHinweis(text: wirdGelesen ? "Die Aufgaben werden gelesen." : "Aufgaben sind gerade nicht lesbar.")
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .onAppear { if agentenOffenZuBeginn { agentenOffen = true }; if zuletztOffenZuBeginn { zuletztOffen = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aufgaben-voll")
    }

    private func agenten(_ a: AufgabenAbschnitte) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Kurve.sn(0.3)) { agentenOffen.toggle() } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(agentenOffen ? 90 : 0)).frame(width: 12)
                        Text("Abgeschlossene Arbeit der Agenten").font(Schrift.grotesk(14, .medium))
                        Spacer(minLength: 0)
                    }
                    Text("\(a.neu.count) neu fertig").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).padding(.leading, 20)
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .accessibilityIdentifier("aufgaben-agenten")
            if agentenOffen {
                VStack(alignment: .leading, spacing: 30) {
                    if !a.neu.isEmpty { SnAufgabenAbschnitt(titel: "Neu", aufgaben: a.neu, jetzt: jetzt, oeffne: oeffne).snNeuSichtbar("voll-agenten", ids: Set(a.neu.map(\.id))) }
                    if !a.zuletzt.isEmpty { SnAufgabenAbschnitt(titel: "Zuletzt fertig", aufgaben: a.zuletzt, jetzt: jetzt, oeffne: oeffne) }
                }
                    .padding(.top, 18)
            }
        }
    }

    private func zuletzt(_ z: [Aufgabe]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Kurve.sn(0.3)) { zuletztOffen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(zuletztOffen ? 90 : 0)).frame(width: 12)
                    Text("Zuletzt fertig (\(AufgabenAbschnitte.zuletztStunden) Std.)").font(Schrift.grotesk(14, .medium))
                    Text("\(z.count)").font(Schrift.mono(12)).foregroundStyle(Farbe.ink3)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .accessibilityIdentifier("aufgaben-zuletzt")
            if zuletztOffen {
                LazyVStack(alignment: .leading, spacing: 0) { ForEach(z) { SnAufgabenZeile(aufgabe: $0, jetzt: jetzt, oeffne: oeffne) } }.padding(.top, 8)
            }
        }
    }
}
