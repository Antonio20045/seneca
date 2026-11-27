import SwiftUI

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
