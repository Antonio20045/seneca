import SwiftUI

struct AbschnittKopf: View {
    var titel: String
    var zahl: Int?
    var aktion: (titel: String, ausfuehren: () -> Void)?
    var oben = true

    init(_ titel: String, zahl: Int? = nil, aktion: (titel: String, ausfuehren: () -> Void)? = nil, oben: Bool = true) {
        self.titel = titel; self.zahl = zahl; self.aktion = aktion; self.oben = oben
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
            Text(titel)
                .schrift(.etikett)
                .foregroundStyle(Stil.tinte.leise)
            if let zahl {
                Text("\(zahl)")
                    .schrift(.etikett)
                    .monospacedDigit()
                    .foregroundStyle(Stil.tinte.leise)
            }
            Spacer(minLength: Stil.abstand.l)
            if let aktion {
                Button(aktion.titel + " ›", action: aktion.ausfuehren)
                    .buttonStyle(TextKnopfStil(stufe: .klein))
                    .padding(.vertical, -Stil.abstand.m)
            }
        }
        .padding(.top, oben ? Stil.abstand.xl : 0)
        .padding(.bottom, Stil.abstand.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
