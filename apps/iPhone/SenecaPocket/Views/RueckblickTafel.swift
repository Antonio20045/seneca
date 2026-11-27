import SwiftUI

struct RueckblickTafel: View {
    var r: SenecaStand.Rueckblick
    var antworte: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(HeuteTafelLogik.datumZeile(r.um)) · \(HeuteTafelLogik.uhr(r.um))").mono(12).foregroundStyle(TafelFarbe.leise)
            Text("RÜCKBLICK").mono(11, abstand: 1.2).foregroundStyle(TafelFarbe.himmel).padding(.top, 6).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(r.saetze.enumerated()), id: \.offset) { i, s in
                    Text(s).font(Sundartha.serif(30, italic: i == 1)).foregroundStyle(i == 1 ? TafelFarbe.akzent : .white)
                        .zeilenHoehe(30 * 1.14, schrift: 30).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 26)
            if let f = r.frage {
                HStack(spacing: 6) {
                    ForEach(Array(f.optionen.enumerated()), id: \.offset) { i, o in
                        Button { antworte(f.id, o.wert ?? "") } label: {
                            Text(o.text ?? "").font(Sundartha.grotesk(15, .medium)).foregroundStyle(i == 0 ? TafelFarbe.aufHimmel : TafelFarbe.zweit)
                                .padding(.horizontal, i == 0 ? 20 : 10).frame(height: 44)
                                .background(Capsule().fill(i == 0 ? TafelFarbe.himmel : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                Text("HEUTE").mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(r.zahlen, id: \.name) { z in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(z.wert).font(Sundartha.grotesk(24, .medium)).monospacedDigit().foregroundStyle(.white)
                            Text(z.name).mono(11).foregroundStyle(TafelFarbe.leise).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 16).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 28).padding(.top, 62)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { g in
                ZStack {
                    LinearGradient(colors: [TafelFarbe.hex(0x0D2550), TafelFarbe.hex(0x030B1A)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(stops: [.init(color: TafelFarbe.himmel.opacity(0.16), location: 0), .init(color: TafelFarbe.himmel.opacity(0), location: 0.4)],
                                   center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: hypot(g.size.width / 2, g.size.height))
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityIdentifier("rueckblick")
    }
}
