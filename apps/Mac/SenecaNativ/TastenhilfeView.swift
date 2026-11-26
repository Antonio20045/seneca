import SwiftUI

struct TastenhilfeDialog: View {
    @ObservedObject var modell: AppModell

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if modell.hilfeOffen {
                    Farbe.schleier.ignoresSafeArea()
                        .onTapGesture { modell.hilfeOffen = false }
                        .transition(.opacity.animation(Kurve.ease(0.2)))
                        .accessibilityHidden(true)
                    dialog(maxHoehe: geo.size.height - 48)
                        .transition(.offset(y: 14).combined(with: .scale(scale: 0.97)).combined(with: .opacity).animation(Kurve.feder(0.28)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(Kurve.ease(0.2), value: modell.hilfeOffen)
        }
    }

    private func dialog(maxHoehe: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView { VStack(alignment: .leading, spacing: 14) {
                Text("Tastenkürzel").font(Schrift.serif(28)).foregroundStyle(Farbe.ink1)
                    .accessibilityAddTraits(.isHeader)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 22, verticalSpacing: 6) {
                    ForEach(Array(Tastenhilfe.zeilen.enumerated()), id: \.offset) { _, z in
                        GridRow {
                            HStack(spacing: 4) { ForEach(Array(z.tasten.enumerated()), id: \.offset) { _, t in Tastenkappe(t) } }
                                .gridColumnAlignment(.leading)
                            Text(z.text).font(Schrift.grotesk(14.5)).foregroundStyle(Farbe.ink2)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(z.tasten.joined(separator: " dann ")): \(z.text)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36).padding(.top, 28).padding(.bottom, 24) }
            Button { modell.hilfeOffen = false } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Farbe.ink2)
                    .frame(width: 30, height: 30).background(Farbe.flaeche, in: Circle())
            }
            .buttonStyle(.plain).padding(16)
            .accessibilityLabel("Schließen").accessibilityIdentifier("hilfe-zu")
        }
        .frame(width: 560, height: min(maxHoehe, 710))
        .background(Farbe.papier, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .shadow(color: Farbe.kastenSchatten, radius: 40, y: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tastenkürzel")
        .accessibilityIdentifier("tastenhilfe")
        .onExitCommand { modell.hilfeOffen = false }
    }
}

struct Tastenkappe: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink2)
            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
