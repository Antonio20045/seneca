import SwiftUI

struct SnReiter<W: Hashable>: View {
    let eintraege: [(W, String)]
    @Binding var gewaehlt: W
    var abstand: CGFloat = 28
    var linie = true

    var body: some View {
        HStack(spacing: abstand) {
            ForEach(Array(eintraege.enumerated()), id: \.offset) { _, e in SnReiterKnopf(titel: e.1, an: gewaehlt == e.0) { gewaehlt = e.0 } }
            if linie { Spacer(minLength: 0) }
        }
        .background(alignment: .bottom) { if linie { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) } }
        .accessibilityElement(children: .contain)
    }
}

private struct SnReiterKnopf: View {
    let titel: String
    let an: Bool
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Text(titel).font(Schrift.grotesk(15, .medium)).lineHeight(.exact(points: 22))
                .foregroundStyle(an || hover ? Color.white : Farbe.ink3)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { if an { Rectangle().fill(Farbe.himmel).frame(height: 1.5) } }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.25), value: hover)
        .accessibilityAddTraits(an ? [.isSelected] : [])
    }
}

struct SnRundKnopf: View {
    let symbol: String
    let beschriftung: String
    var aktion: () -> Void = {}
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hover ? Color.white : Farbe.ink2)
                .frame(width: 40, height: 40)
                .background(Circle().fill(hover ? Color.white.opacity(0.06) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.2), value: hover)
        .accessibilityLabel(beschriftung)
    }
}
