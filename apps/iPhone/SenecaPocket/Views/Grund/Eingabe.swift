import SwiftUI

struct SchreibFeld: View {
    var platzhalter: String
    @Binding var text: String
    var zeilen: ClosedRange<Int> = 1...5
    var eingabeSendet = false
    var geheim = false
    var senden: (() -> Void)?
    private var linksInhalt: AnyView?

    init(_ platzhalter: String, text: Binding<String>, zeilen: ClosedRange<Int> = 1...5, eingabeSendet: Bool = false,
         geheim: Bool = false, senden: (() -> Void)? = nil) {
        self.platzhalter = platzhalter
        self._text = text
        self.zeilen = zeilen
        self.eingabeSendet = eingabeSendet
        self.geheim = geheim
        self.senden = senden
    }

    func links<V: View>(@ViewBuilder _ inhalt: () -> V) -> SchreibFeld {
        var s = self
        s.linksInhalt = AnyView(inhalt())
        return s
    }

    private var bereit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if let linksInhalt {
                linksInhalt.padding(.leading, Stil.abstand.xs).padding(.bottom, Stil.abstand.xs)
            }
            feld
                .padding(.leading, linksInhalt == nil ? Stil.abstand.l : Stil.abstand.xs)
                .padding(.trailing, senden == nil ? Stil.abstand.l : Stil.abstand.xs)
                .padding(.vertical, Stil.abstand.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let senden {
                RundKnopf("arrow.up", beschriftung: "Senden", voll: bereit) {
                    if bereit { senden() }
                }
                .disabled(!bereit)
                .padding(.trailing, Stil.abstand.xs)
                .padding(.bottom, Stil.abstand.xs)
            }
        }
        .frame(minHeight: Stil.tippFlaeche + Stil.abstand.s)
        .background(RoundedRectangle(cornerRadius: Stil.radius.mittel, style: .continuous).fill(Stil.tinte.flaeche))
        .bewegt(.klein, wert: bereit)
    }

    @ViewBuilder private var feld: some View {
        let bild = Text(platzhalter).foregroundStyle(Stil.tinte.leise)
        Group {
            if geheim {
                SecureField(text: $text, prompt: bild) { Text(platzhalter) }
            } else if zeilen.upperBound <= 1 {
                TextField(text: $text, prompt: bild) { Text(platzhalter) }
            } else {
                TextField(text: $text, prompt: bild, axis: .vertical) { Text(platzhalter) }
                    .lineLimit(zeilen)
            }
        }
        .schrift(.text)
        .foregroundStyle(Stil.tinte.voll)
        .tint(Stil.farbe.himmel)
        .padding(.vertical, Stil.abstand.xs)
        .submitLabel(eingabeSendet ? .send : .return)
        .onSubmit { if eingabeSendet, bereit { senden?() } }
        .onChange(of: text) { _, neu in
            guard eingabeSendet, zeilen.upperBound > 1, neu.hasSuffix("\n") else { return }
            text = String(neu.dropLast())
            if bereit { senden?() }
        }
    }
}
