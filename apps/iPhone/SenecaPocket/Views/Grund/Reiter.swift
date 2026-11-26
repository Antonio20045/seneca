import SwiftUI

struct ReiterOption<Wert: Hashable>: Identifiable {
    var wert: Wert
    var titel: String
    var zahl: Int?
    var id: Wert { wert }
    init(_ wert: Wert, _ titel: String, zahl: Int? = nil) {
        self.wert = wert; self.titel = titel; self.zahl = zahl
    }
}

struct ReiterLeiste<Wert: Hashable>: View {
    @Binding var auswahl: Wert
    var optionen: [ReiterOption<Wert>]
    @Namespace private var linie

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.xl) {
            ForEach(optionen) { o in
                let gewaehlt = o.wert == auswahl
                Button {
                    guard !gewaehlt else { return }
                    Haptik.auswahl()
                    Bewegung.mit(.wechsel) { auswahl = o.wert }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.xs) {
                        Text(o.titel).schrift(gewaehlt ? .zeileWichtig : .zeile)
                        if let zahl = o.zahl, zahl > 0 {
                            Text("\(zahl)").schrift(.klein).monospacedDigit()
                        }
                    }
                    .foregroundStyle(gewaehlt ? Stil.tinte.voll : Stil.tinte.leise)
                    .padding(.vertical, Stil.abstand.m)
                    .overlay(alignment: .bottom) {
                        if gewaehlt {
                            Capsule()
                                .fill(Stil.tinte.voll)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "linie", in: linie)
                        }
                    }
                    .frame(minHeight: Stil.tippFlaeche)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
