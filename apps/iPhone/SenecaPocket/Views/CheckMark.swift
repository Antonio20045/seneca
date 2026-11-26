import SwiftUI

struct CheckMark: View {
    var on: Bool
    var size: CGFloat = 20
    var reduceMotion = false
    @Environment(\.checkPressed) private var pressed

    var body: some View {
        let k = size / 20
        ZStack {
            Circle()
                .fill(on ? Stil.tinte.voll : .clear)
                .animation(reduceMotion ? nil : Bewegung.wechsel.kurve, value: on)
            Circle()
                .inset(by: 0.8 * k)
                .stroke(Stil.tinte.voll, lineWidth: 1.2 * k)
            TickShape()
                .trim(from: 0, to: on ? 1 : 0)
                .stroke(Sundartha.checkInk, style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round))
                .animation(reduceMotion ? nil : on ? Bewegung.wechsel.kurve.delay(0.1) : Bewegung.klein.kurve, value: on)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed && !reduceMotion ? 0.88 : 1)
        .animation(Bewegung.klein.kurve, value: pressed)
        .accessibilityHidden(true)
    }
}

struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 20
        var p = Path()
        p.move(to: CGPoint(x: 6.2 * k, y: 10.3 * k))
        p.addLine(to: CGPoint(x: 8.8 * k, y: 12.9 * k))
        p.addLine(to: CGPoint(x: 13.8 * k, y: 7.5 * k))
        return p
    }
}

struct StrikeText: View {
    var text: String
    var on: Bool
    var font: Font
    var reduceMotion = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Stil.tinte.voll)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(on ? 0.55 : 1)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Stil.tinte.voll)
                        .frame(width: geo.size.width, height: 1)
                        .scaleEffect(x: on ? 1 : 0, anchor: .leading)
                        .offset(y: geo.size.height * 0.58)
                        .opacity(on ? 0.55 : 1)
                }
            }
            .animation(reduceMotion ? Bewegung.klein.kurve : on ? Bewegung.wechsel.kurve.delay(0.2) : Bewegung.wechsel.kurve, value: on)
    }
}
