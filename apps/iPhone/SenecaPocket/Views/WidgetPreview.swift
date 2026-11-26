#if DEBUG
import SwiftUI

struct WidgetPreviewScreen: View {
    @EnvironmentObject private var store: SenecaStore
    private let scale: CGFloat = 1.5
    private let rect = CGSize(width: 160, height: 72)

    private struct Variant: Identifiable {
        let id: String
        let caption: String
        let lines: WidgetLines
    }

    private var variants: [Variant] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date())! }
        guard let today = store.today else { return [] }
        let base = WidgetBridge.snapshot(today, now: at(13, 51))
        return [
            Variant(id: "a", caption: "13:51, der nächste Termin", lines: WidgetLogic.lines(base, at: at(13, 51))),
            Variant(id: "b", caption: "17:05, der darauf folgende", lines: WidgetLogic.lines(base, at: at(17, 5))),
            Variant(id: "c", caption: "23:00, heute steht nichts mehr an", lines: WidgetLogic.lines(base, at: at(23, 0))),
            Variant(id: "d", caption: "Stand älter als zwölf Stunden", lines: WidgetLogic.lines(base, at: at(13, 51).addingTimeInterval(13 * 3600))),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Sundartha.ink, Color(red: 0.18, green: 0.26, blue: 0.40)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Sperrbildschirm").font(Sundartha.grotesk(13)).foregroundStyle(.white.opacity(0.6))
                ForEach(variants) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.caption).font(Sundartha.grotesk(11)).foregroundStyle(.white.opacity(0.45))
                        WidgetFace(lines: v.lines)
                            .frame(width: rect.width, height: rect.height, alignment: .leading)
                            .overlay(Rectangle().stroke(.white.opacity(0.12), lineWidth: 0.5))
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: rect.width * scale, height: rect.height * scale, alignment: .topLeading)
                    }
                }
                Text("Eine Zeile über der Uhr").font(Sundartha.grotesk(11)).foregroundStyle(.white.opacity(0.45)).padding(.top, 6)
                ForEach(variants.prefix(3)) { v in
                    WidgetFace(lines: v.lines, inline: true)
                        .font(.system(size: 15 * scale, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 28)
            .padding(.top, 20)
        }
        .task {
            store.loadDemo(now: Calendar.current.date(bySettingHour: 13, minute: 51, second: 0, of: Date())!, streak: 11, record: 3, todos: true, routineDone: true)
        }
    }
}
#endif
