import SwiftUI

struct FadenFrage: View {
    var text: String
    var breite: CGFloat
    var zeit: Date?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(Sundartha.grotesk(15)).zeilenHoehe(21, schrift: 15)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                    .fill(TafelFarbe.hex(0x142B4C)))
                .frame(maxWidth: 308, alignment: .trailing)
            if let zeit { Text(HeuteTafelLogik.uhr(zeit.timeIntervalSince1970 * 1000)).mono(11).foregroundStyle(TafelFarbe.aus) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Du: \(text)")
    }
}

struct FadenAntwort: View {
    var text: String
    var sprecher: String

    var body: some View {
        FadenMarkdown(text: text, live: false, sprecher: sprecher)
    }
}

struct FadenDatum: View {
    var text: String

    var body: some View {
        Text(text)
            .schrift(.klein)
            .foregroundStyle(Stil.tinte.leise)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)
    }
}

struct FadenWachsend: View {
    var text: String
    var sprecher: String
    var final = false
    @StateObject private var takt = WortTakt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FadenMarkdown(text: takt.sichtbar, live: !takt.beendet, frisch: reduceMotion ? .keine : takt.frisch,
                      sprecher: sprecher, ansage: "\(sprecher) schreibt gerade")
            .onAppear { takt.setzeText(text, final: final) }
            .onChange(of: text) { _, neu in takt.setzeText(neu, final: final) }
            .onChange(of: final) { _, ende in takt.setzeText(text, final: ende) }
    }
}
