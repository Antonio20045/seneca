import SwiftUI

struct SnFluss: Layout {
    var abstand: CGFloat = 6
    var zeilenAbstand: CGFloat = 0

    private func rahmen(_ subviews: Subviews, breite: CGFloat) -> (frames: [CGRect], groesse: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHoehe: CGFloat = 0, maxX: CGFloat = 0
        var frames: [CGRect] = []
        for v in subviews {
            let s = v.sizeThatFits(.init(width: nil, height: nil))
            let w = min(s.width, breite)
            let h = v.sizeThatFits(.init(width: w, height: nil)).height
            if x > 0, x + w > breite { x = 0; y += zeilenHoehe + zeilenAbstand; zeilenHoehe = 0 }
            frames.append(CGRect(x: x, y: y, width: w, height: h))
            x += w + abstand; zeilenHoehe = max(zeilenHoehe, h); maxX = max(maxX, x - abstand)
        }
        var ergebnis = frames
        var i = 0
        while i < frames.count {
            var j = i
            while j < frames.count, frames[j].minY == frames[i].minY { j += 1 }
            let h = frames[i..<j].map(\.height).max() ?? 0
            for k in i..<j { ergebnis[k].origin.y += (h - frames[k].height) / 2 }
            i = j
        }
        return (ergebnis, CGSize(width: maxX, height: y + zeilenHoehe))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rahmen(subviews, breite: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? r.groesse.width, height: r.groesse.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rahmen(subviews, breite: bounds.width)
        for (v, f) in zip(subviews, r.frames) {
            v.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .init(width: f.width, height: f.height))
        }
    }
}

struct SnZeilenStil: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Farbe.zeileHover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(configuration.isPressed ? Kurve.snFeder : Kurve.sn(0.25), value: configuration.isPressed)
            .animation(Kurve.sn(0.25), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnLeiserStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? Color.white : Farbe.ink2)
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

