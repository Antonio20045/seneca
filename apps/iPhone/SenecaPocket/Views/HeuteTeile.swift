import SwiftUI

struct Knopf: ButtonStyle {
    var groesse: CGFloat = 0
    var stark = false
    func makeBody(configuration: Configuration) -> some View {
        KapselStil(art: stark ? .haupt : .zweit).makeBody(configuration: configuration)
    }
}

struct LeiserKnopf: ButtonStyle {
    var groesse: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View {
        TextKnopfStil().makeBody(configuration: configuration)
    }
}

struct LebendePunkte: View {
    var reduceMotion = false
    var body: some View { LaeuftPunkte() }
}

struct LaeuftInhalt: View {
    var zeilen: [LaeuftZeile]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if zeilen.isEmpty {
                LeerSatz("Gerade läuft nichts mehr für dich.")
            }
            ForEach(Array(zeilen.enumerated()), id: \.element.id) { i, z in
                Zeile(vorn: .punkt(z.art == .pruefung ? Stil.farbe.himmel : Stil.farbe.gruen),
                      titel: z.satz,
                      unter: unter(z),
                      linie: i < zeilen.count - 1)
                    .accessibilityIdentifier("heute.laeuft.arbeit")
            }
        }
        .accessibilityIdentifier("heute.laeuft.blatt")
    }

    private func unter(_ z: LaeuftZeile) -> String? {
        let wer = z.von.isEmpty ? "" : Namen.mitarbeiter(z.von)
        let teile = [wer, z.art == .auftrag ? z.stand : ""].filter { !$0.isEmpty }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }
}

struct HeuteTodos: View {
    var jetzt: Date
    var allowTap: () -> Bool
    var toggleTodo: (String) -> Void

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.wege) private var wege
    @State private var gehalten: Set<String> = []

    private static let hoechstens = 8

    var body: some View {
        let zeilen = store.topDreiMitGehaltenen(gehalten, anzahl: 100, jetzt: jetzt)
        let offen = zeilen.filter { !$0.isDone }.count
        VStack(alignment: .leading, spacing: 0) {
            AbschnittKopf("To-dos heute", zahl: offen > 0 ? offen : nil, aktion: ("Alle", {
                guard allowTap() else { return }
                wege.oeffne(.aufgaben)
            }), oben: false)
            if zeilen.isEmpty {
                LeerSatz(store.today == nil ? "Deine To-dos stehen hier, sobald dein Mac antwortet." : "Für heute ist nichts offen.")
                    .accessibilityIdentifier("heute.todos.leer")
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach(Array(stride(from: min(zeilen.count, Self.hoechstens), through: 1, by: -1)), id: \.self) { n in
                        liste(zeilen, n)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bewegt(.blatt, wert: zeilen.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("heute.todos")
    }

    private func liste(_ zeilen: [SenecaTask], _ n: Int) -> some View {
        let rest = zeilen.count - n
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(zeilen.prefix(n).enumerated()), id: \.element.id) { i, t in
                Zeile(vorn: .haken(an: t.isDone) { abhaken(t) },
                      titel: HeuteLogik.anzeigeTitel(t.title),
                      linie: i < n - 1 || rest > 0)
                    .transition(.wechsel)
                    .accessibilityAction(named: t.isDone ? "Zurückholen" : "Erledigen") { abhaken(t) }
                    .accessibilityIdentifier("heute.todo")
            }
            if rest > 0 {
                TextKnopf(rest == 1 ? "Noch eins ›" : "Noch \(rest) ›", stufe: .klein) {
                    guard allowTap() else { return }
                    wege.oeffne(.aufgaben)
                }
                .accessibilityLabel(rest == 1 ? "Noch ein To-do" : "Noch \(rest) To-dos")
                .accessibilityHint("Öffnet die Aufgaben")
                .accessibilityIdentifier("heute.aufgaben")
            }
        }
    }

    private func abhaken(_ t: SenecaTask) {
        guard allowTap() else { return }
        if t.isDone {
            gehalten.remove(t.id)
            toggleTodo(t.id)
            return
        }
        gehalten.insert(t.id)
        toggleTodo(t.id)
        let id = t.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 4 : 1.6))
            Bewegung.mit(.blatt) { _ = gehalten.remove(id) }
        }
    }
}
