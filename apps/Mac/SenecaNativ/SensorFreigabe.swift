import SwiftUI

struct SensorFreigabeKarte: View {
    let satz: String
    let oeffnen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(satz).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: oeffnen) {
                Text("Freigabe öffnen").font(Schrift.grotesk(12, .medium)).foregroundStyle(Farbe.nacht)
                    .padding(.horizontal, 13).padding(.vertical, 5)
                    .background(Farbe.himmel, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sensor-freigabe-oeffnen")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { SensorKartenGrund() }
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SensorKartenGrund: View {
    var body: some View {
        GeometryReader { g in
            let mitte = CGPoint(x: g.size.width * 0.76, y: g.size.height * 0.1)
            let weit = [CGPoint.zero, CGPoint(x: g.size.width, y: 0), CGPoint(x: 0, y: g.size.height), CGPoint(x: g.size.width, y: g.size.height)]
                .map { hypot($0.x - mitte.x, $0.y - mitte.y) }.max() ?? 1
            ZStack {
                LinearGradient(colors: [Color(hex: 0x123264), Farbe.nachtUnten], startPoint: .top, endPoint: .bottom)
                RadialGradient(stops: [.init(color: Farbe.himmel.opacity(0.26), location: 0), .init(color: Farbe.himmel.opacity(0.11), location: 0.14),
                                       .init(color: Farbe.himmel.opacity(0), location: 0.30)],
                               center: UnitPoint(x: 0.76, y: 0.1), startRadius: 0, endRadius: weit)
            }
        }
    }
}

struct SensorEinstellung: View {
    @ObservedObject var sensor = Sensor.gemeinsam

    var body: some View {
        Text("Seneca sieht, welche App und welches Fenster vorn ist. Ein Modell auf diesem Mac fragt sich: Kann ich hier helfen? Nur wenn es sicher ist, kommt ein Vorschlag. Fotos und markierter Text verlassen den Mac nie.")
            .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
        HStack { Text("Sensor"); Spacer(); Toggle("Sensor", isOn: $sensor.an).labelsHidden() }
            .accessibilityIdentifier("einst-sensor")
        if sensor.an, let s = sensor.satz { SensorFreigabeKarte(satz: s) { sensor.freigeben() } }
    }
}
