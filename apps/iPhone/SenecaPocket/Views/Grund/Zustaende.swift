import SwiftUI

struct LeerSatz: View {
    var text: String
    var aktion: (titel: String, ausfuehren: () -> Void)?
    init(_ text: String, aktion: (titel: String, ausfuehren: () -> Void)? = nil) {
        self.text = text; self.aktion = aktion
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.xs) {
            Text(text)
                .schrift(.sache)
                .foregroundStyle(Stil.tinte.zweit)
                .fixedSize(horizontal: false, vertical: true)
            if let aktion {
                TextKnopf(aktion.titel, aktion: aktion.ausfuehren)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Stil.abstand.l)
    }
}

struct LadeZeile: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: Stil.abstand.s) {
            LaeuftPunkte(farbe: Stil.tinte.zweit)
            Text(text)
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.zweit)
        }
        .frame(minHeight: Stil.tippFlaeche, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HinweisZeile: View {
    enum Art { case offline, fehler, info }
    var text: String
    var art: Art = .info
    var aktion: (titel: String, ausfuehren: () -> Void)?

    init(_ text: String, art: Art = .info, aktion: (titel: String, ausfuehren: () -> Void)? = nil) {
        self.text = text; self.art = art; self.aktion = aktion
    }

    private var farbe: Color {
        switch art {
        case .offline: Stil.farbe.bernstein
        case .fehler: Stil.farbe.koralle
        case .info: Stil.farbe.himmel
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
            Circle().fill(farbe).frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.zweit)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Stil.abstand.s)
            if let aktion {
                TextKnopf(aktion.titel, stufe: .klein, aktion: aktion.ausfuehren)
            }
        }
        .frame(minHeight: Stil.tippFlaeche)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
