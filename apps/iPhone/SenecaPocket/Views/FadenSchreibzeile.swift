import SwiftUI

extension FadenLayer {
    var schreibzeile: some View {
        SchreibFeld(partner.platzhalter, text: $feld, zeilen: 1...5, senden: { senden() })
            .links { mikrofon }
            .focused($fokus)
            .accessibilityIdentifier("faden.feld")
            .background {
                Button("Senden") { senden() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder private var mikrofon: some View {
        if model.gespraech.aktiv || model.sprechenErlaubt {
            let imGespraech = model.gespraech.aktiv
            let frei = imGespraech || feldLeer
            RundKnopf(imGespraech ? "mic.fill" : "mic", beschriftung: imGespraech ? "Gespräch beenden" : "Sprechen", voll: imGespraech) {
                guard allowTap() else { return }
                if imGespraech { model.zuhoerEnde(.beendet) } else {
                    fokus = false
                    model.gespraechStarten(feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
                }
            }
            .disabled(!frei)
            .opacity(frei ? 1 : 0.35)
            .accessibilityHint(imGespraech ? "Beendet das Gespräch" : "Sagen, was du willst; \(partner.satzName) antwortet")
            .accessibilityIdentifier("faden.sprechen")
        }
    }

    func sprechWunschErfuellen() {
        guard model.sprechWunschOffen else { return }
        model.sprechWunschOffen = false
        guard !model.gespraech.aktiv else { return }
        if model.sprechenErlaubt, feldLeer {
            fokus = false
            model.gespraechStarten(feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
        } else {
            fokus = true
        }
    }

    @discardableResult
    func senden(_ gesagt: String? = nil) -> Bool {
        let text = gesagt ?? feld
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let vorher = ankerPartner
        ankerPartner = partner.id
        if model.senden(text, an: partner) {
            feld = ""
            return true
        }
        ankerPartner = vorher
        if model.macUnreachable { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        return false
    }
}
