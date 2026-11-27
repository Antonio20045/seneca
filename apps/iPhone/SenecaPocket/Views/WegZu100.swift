import SwiftUI

struct WegZu100: View {
    var k: LaufDaten.Lauf?

    var body: some View {
        let vorher = Array((k?.lang ?? []).suffix(12)), plan = (k?.aufbau ?? []).dropFirst().compactMap { $0.count > 1 ? $0[1].d : nil }
        let n = max(1, vorher.count + plan.count + 2)
        let bester = k?.laengster?.first?.d, wann = k?.laengster?.last?.s.flatMap { ISO8601DateFormatter.tag.date(from: $0) }
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let x = { (i: Int) in g.size.width * CGFloat(i) / CGFloat(n - 1) }, y = { (v: Double) in g.size.height * (1 - min(1, v / 100)) }
                ZStack(alignment: .topLeading) {
                    Path { p in p.move(to: CGPoint(x: 0, y: y(100))); p.addLine(to: CGPoint(x: g.size.width, y: y(100))) }
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    Path { p in p.addLines(vorher.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) }) }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    Path { p in p.addLines(([vorher.last ?? 0] + plan).enumerated().map { CGPoint(x: x(vorher.count - 1 + $0.offset), y: y($0.element)) }) }
                        .stroke(TafelFarbe.himmel.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [3, 3]))
                    Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7).position(x: x(n - 1), y: y(100))
                    Text("100 KM").mono(10).foregroundStyle(TafelFarbe.gruen).position(x: x(n - 1) - 26, y: y(100) + 12)
                    if let i = vorher.lastIndex(of: vorher.max() ?? 0), (vorher.max() ?? 0) > 0 {
                        Circle().fill(Color.white).frame(width: 6, height: 6).position(x: x(i), y: y(vorher[i]))
                    }
                }
            }
            .frame(height: 64)
            HStack {
                Text(bester.map { "Längster Lauf \(LaufRechnen.zahl($0)) km" + (wann.map { " · " + LaufRechnen.datum($0, "d. MMMM") } ?? "") } ?? "Noch kein langer Lauf")
                Spacer()
                Text("Plan bis \(LaufRechnen.zahl(plan.max() ?? 0, 0)) km").foregroundStyle(TafelFarbe.himmel)
            }
            .font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
        }
    }
}
