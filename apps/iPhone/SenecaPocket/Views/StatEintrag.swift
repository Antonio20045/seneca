import SwiftUI

struct StatChip: View {
    var titel: String
    var gewaehlt = false
    var breit = false
    var aktion: () -> Void
    init(_ titel: String, gewaehlt: Bool = false, breit: Bool = false, aktion: @escaping () -> Void) {
        self.titel = titel; self.gewaehlt = gewaehlt; self.breit = breit; self.aktion = aktion
    }
    var body: some View {
        Button { Haptik.auswahl(); aktion() } label: {
            Text(titel)
                .schrift(gewaehlt ? .zeileWichtig : .zeile)
                .foregroundStyle(gewaehlt ? Stil.tinte.voll : Stil.tinte.zweit)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Stil.abstand.l)
                .frame(maxWidth: breit ? .infinity : nil, minHeight: Stil.knopfHoehe)
                .background(RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous)
                    .fill(gewaehlt ? Stil.tinte.flaecheStark : Stil.tinte.flaeche))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bewegt(.klein, wert: gewaehlt)
        .accessibilityAddTraits(gewaehlt ? .isSelected : [])
    }
}

struct StatSchnellLesen: View {
    @ObservedObject var model: StatistikModel
    var mehr: () -> Void
    @EnvironmentObject private var store: SenecaStore
    @State private var letzter: (id: String, text: String)?

    var body: some View {
        let daten = model.daten(jetzt: store.clock())
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            if let buch = daten.aktuellesBuch {
                HStack(spacing: Stil.abstand.s) {
                    ZweitKnopf("+15 Min") { eintragen(15, buch) }.accessibilityIdentifier("statistik.lesen.15")
                    ZweitKnopf("+30 Min") { eintragen(30, buch) }.accessibilityIdentifier("statistik.lesen.30")
                    TextKnopf("Andere …", aktion: mehr).accessibilityIdentifier("statistik.plus.lesen")
                    Spacer(minLength: 0)
                }
            } else {
                HauptKnopf("Lesen eintragen", aktion: mehr).accessibilityIdentifier("statistik.plus.lesen")
            }
            if let letzter {
                HinweisZeile(letzter.text, art: .info, aktion: (titel: "Rückgängig", ausfuehren: { zuruecknehmen() }))
                    .transition(.wechsel)
                    .task(id: letzter.id) {
                        try? await Task.sleep(for: .seconds(8))
                        if !Task.isCancelled { Bewegung.mit(.wechsel) { self.letzter = nil } }
                    }
            }
        }
        .bewegt(.wechsel, wert: letzter?.id)
    }

    private func eintragen(_ minuten: Int, _ buch: StatBuch) {
        let jetzt = store.clock()
        let id = model.lesenEintragen(minuten: minuten, tag: StatKalender.schluessel(jetzt), notiz: "", buch: nil, neuesBuch: nil, store: store)
        letzter = (id, "\(StatFormat.lesezeit(minuten)) in „\(buch.titel)“ eingetragen.")
    }

    private func zuruecknehmen() {
        guard let l = letzter else { return }
        model.lesenZuruecknehmen(l.id, store: store)
        Haptik.auswahl()
        letzter = nil
    }
}

struct StatEintragBlatt: View {
    @ObservedObject var model: StatistikModel

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss
    @State private var zahl = ""
    @State private var notiz = ""
    @State private var tagWahl = 0
    @State private var datum = Date()
    @State private var gewaehlt: StatBuch?
    @State private var neuesBuch = false
    @State private var titel = ""
    @FocusState private var fokus: Bool
    @FocusState private var titelFokus: Bool

    private var daten: StatDaten { model.daten(jetzt: store.clock()) }
    private var buch: StatBuch? { neuesBuch ? nil : (gewaehlt ?? daten.aktuellesBuch) }
    private var braucheTitel: Bool { neuesBuch || daten.buecher.isEmpty }
    private var wert: Int? { Int(zahl.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 && $0 <= 1440 ? $0 : nil } }
    private var tagKey: String {
        let jetzt = store.clock()
        switch tagWahl {
        case 0: return StatKalender.schluessel(jetzt)
        case 1: return StatKalender.plus(StatKalender.schluessel(jetzt), tage: -1)
        default: return StatKalender.schluessel(datum)
        }
    }
    private var kannEintragen: Bool { wert != nil && (!braucheTitel || !titel.trimmingCharacters(in: .whitespaces).isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            if braucheTitel {
                SchreibFeld("Wie heißt das Buch?", text: $titel, zeilen: 1...1)
                    .focused($titelFokus)
                    .modifier(FocusOnAppear(focus: $titelFokus))
                    .accessibilityIdentifier("statEintrag.titel")
            }

            HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                TextField("0", text: $zahl)
                    .keyboardType(.numberPad)
                    .schrift(.zahl)
                    .foregroundStyle(Stil.tinte.voll)
                    .tint(Stil.farbe.himmel)
                    .fixedSize()
                    .focused($fokus)
                    .accessibilityLabel("Minuten")
                    .accessibilityIdentifier("statEintrag.wert")
                    .modifier(FocusOnAppearWenn(aktiv: !braucheTitel, focus: $fokus))
                Text("Min").schrift(.titel).foregroundStyle(Stil.tinte.zweit)
                Spacer(minLength: 0)
            }

            HStack(spacing: Stil.abstand.s) {
                ForEach([15, 30, 45, 60], id: \.self) { minuten in
                    StatChip(StatFormat.lesezeit(minuten), gewaehlt: wert == minuten, breit: true) { zahl = String(minuten) }
                        .accessibilityIdentifier("statEintrag.min\(minuten)")
                }
            }

            if !braucheTitel, let b = buch {
                HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.m) {
                    (Text("in ").font(Stil.Schrift.text.font) + Text(b.titel).font(Stil.Schrift.sache.kursiv))
                        .foregroundStyle(Stil.tinte.zweit).lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(daten.buecher.sorted { $0.begonnen > $1.begonnen }) { x in
                            Button(x.titel) { gewaehlt = x }
                        }
                        Button("Neues Buch …") { neuesBuch = true; gewaehlt = nil }
                    } label: {
                        Text("Anderes Buch").schrift(.zeile).foregroundStyle(Stil.tinte.zweit).frame(minHeight: Stil.tippFlaeche)
                    }
                    .accessibilityIdentifier("statEintrag.anderesBuch")
                }
            }

            HStack(spacing: Stil.abstand.s) {
                StatChip("Heute", gewaehlt: tagWahl == 0) { tagWahl = 0 }
                StatChip("Gestern", gewaehlt: tagWahl == 1) { tagWahl = 1 }
                StatChip("Anderer Tag", gewaehlt: tagWahl == 2) { tagWahl = 2 }
                Spacer(minLength: 0)
            }
            if tagWahl == 2 {
                DatePicker("Tag", selection: $datum, in: ...store.clock(), displayedComponents: .date)
                    .labelsHidden().tint(Stil.farbe.himmel).frame(maxWidth: .infinity, alignment: .leading)
            }

            SchreibFeld("Notiz", text: $notiz, zeilen: 1...3)
                .accessibilityIdentifier("statEintrag.notiz")

            HauptKnopf("Eintragen", breit: true, aktion: eintragen)
                .disabled(!kannEintragen)
                .accessibilityIdentifier("statEintrag.eintragen")
        }
        .bewegt(.klein, wert: tagWahl)
    }

    private func eintragen() {
        guard let n = wert else { return }
        let neu: String? = braucheTitel ? titel.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        model.lesenEintragen(minuten: n, tag: tagKey, notiz: notiz, buch: gewaehlt, neuesBuch: neu, store: store)
        Haptik.erledigt()
        dismiss()
    }
}

struct FocusOnAppearWenn: ViewModifier {
    var aktiv: Bool
    var focus: FocusState<Bool>.Binding
    func body(content: Content) -> some View {
        if aktiv { content.modifier(FocusOnAppear(focus: focus)) } else { content }
    }
}
