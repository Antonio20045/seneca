import SwiftUI

struct HeuteJetzt: View {
    var m: Metrics
    var day: DayState
    var jetzt: Date
    var punkte: [AblaufPunkt]
    var bereit: Bool
    var reduceMotion: Bool
    var allowTap: () -> Bool
    var toggleRoutine: () -> Void

    @Environment(\.wege) private var wege
    @State private var routineHalten = false
    @State private var routineTask: Task<Void, Never>?

    private var routineOffen: Bool { !day.routineDone && !day.routineDetail.isEmpty }
    private var routineSichtbar: Bool { routineOffen || routineHalten }

    var body: some View {
        let satz = Tagesablauf.jetztSatz(punkte, routineOffen: routineOffen, jetzt: jetzt)
        let strecke = Tagesablauf.strecke(punkte, jetzt: jetzt, breite: HeuteBild.breite(m), schilder: HeuteBild.schilder, messen: HeuteBild.messen)
        VStack(alignment: .leading, spacing: 0) {
            Button { zumKalender() } label: {
                HeuteSatzText(satz: satz)
                    .id(satz.text + "|" + satz.leise)
                    .transition(.wechsel)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(bereit ? Bewegung.wechsel.kurve : nil, value: satz.text + "|" + satz.leise)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(satz.leise.isEmpty ? satz.text : satz.text + " " + satz.leise)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Zeigt den Kalender")
            .accessibilityIdentifier("heute.satz")

            if !strecke.leer {
                Button { zumKalender() } label: {
                    HeuteBild(strecke: strecke, reduceMotion: reduceMotion).equatable()
                }
                .buttonStyle(.plain)
                .padding(.top, Stil.abstand.l)
            }

            if routineSichtbar {
                Zeile(vorn: .haken(an: day.routineDone) { routineTippen() },
                      titel: "Morgenroutine",
                      unter: day.routineDetail.isEmpty ? nil : day.routineDetail,
                      linie: false) { routineTippen() }
                    .padding(.top, Stil.abstand.s)
                    .transition(.wechsel)
                    .accessibilityIdentifier("heute.routine")
            }
        }
        .bewegt(.blatt, wert: routineSichtbar)
    }

    private func zumKalender() {
        guard allowTap() else { return }
        wege.oeffne(.kalender())
    }

    private func routineTippen() {
        guard allowTap() else { return }
        routineTask?.cancel()
        if day.routineDone {
            routineHalten = false
            toggleRoutine()
            return
        }
        routineHalten = true
        toggleRoutine()
        routineTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 4 : 1.6))
            guard !Task.isCancelled else { return }
            Bewegung.mit(.blatt) { routineHalten = false }
        }
    }
}
