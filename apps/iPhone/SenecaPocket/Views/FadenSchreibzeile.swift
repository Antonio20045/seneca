import SwiftUI

extension FadenLayer {
    var schreibzeile: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if feldLeer, !fokus, model.sprechenErlaubt { sprechen }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $feld, prompt: Text(partner.platzhalter).foregroundColor(TafelFarbe.leise), axis: .vertical)
                    .font(Sundartha.grotesk(16)).foregroundStyle(.white).lineLimit(1...5).focused($fokus)
                    .padding(.vertical, 13)
                    .accessibilityIdentifier("faden.feld")
                if !feldLeer {
                    Button { senden() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel)
                            .frame(width: 36, height: 36).background(Circle().fill(TafelFarbe.akzent))
                    }
                    .buttonStyle(.plain).padding(.bottom, 6)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Senden")
                }
            }
            .padding(.leading, 18).padding(.trailing, feldLeer ? 18 : 6)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        }
        .padding(.horizontal, -8)
        .bewegt(.wechsel, wert: feldLeer && !fokus)
    }

    private var sprechen: some View {
        Button {
            guard allowTap() else { return }
            fokus = false
            model.gespraechStarten(feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic").font(.system(size: 15, weight: .medium))
                Text("Sprechen").font(Sundartha.grotesk(15, .medium))
            }
            .foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 16).frame(height: 48)
            .background(Capsule().fill(TafelFarbe.akzent))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sagen, was du willst; \(partner.satzName) antwortet")
        .accessibilityIdentifier("faden.sprechen")
    }

    func sprechWunschErfuellen() {
        guard model.sprechWunschOffen else { return }
        model.sprechWunschOffen = false
        guard !model.gespraech.aktiv else { return }
        if model.sprechenErlaubt, feldLeer {
            fokus = false
            model.gespraechStarten(taste: model.sprechWunschTaste, feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
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
