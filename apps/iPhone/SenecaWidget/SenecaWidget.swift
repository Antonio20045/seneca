import WidgetKit
import SwiftUI

struct DayEntry: TimelineEntry {
    let date: Date
    let lines: WidgetLines
}

struct DayProvider: TimelineProvider {
    private func sample(_ now: Date) -> WidgetSnapshot {
        let start = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        return WidgetSnapshot(items: [.init(title: "Kaffee mit Lena", start: start, end: start.addingTimeInterval(3600), place: "Café Lorenz")],
                              writtenAt: now, coversUntil: now.addingTimeInterval(86_400))
    }

    func placeholder(in context: Context) -> DayEntry {
        let now = Date()
        return DayEntry(date: now, lines: WidgetLogic.lines(sample(now), at: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let now = Date()
        if context.isPreview, WidgetStore.read() == nil {
            completion(placeholder(in: context))
        } else {
            completion(DayEntry(date: now, lines: WidgetLogic.lines(WidgetStore.read(), at: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetStore.read()
        let entries = WidgetLogic.timelineDates(snapshot, from: now).map { DayEntry(date: $0, lines: WidgetLogic.lines(snapshot, at: $0)) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private static let oben = Color(red: 0x0A / 255, green: 0x22 / 255, blue: 0x45 / 255)
    private static let unten = Color(red: 0x06 / 255, green: 0x16 / 255, blue: 0x32 / 255)

    private var art: WidgetFace.Art {
        switch family {
        case .accessoryInline: return .zeile
        case .accessoryCircular: return .kreis
        case .accessoryRectangular: return .rechteck
        default: return .home
        }
    }

    var body: some View {
        WidgetFace(lines: entry.lines, art: art)
            .containerBackground(for: .widget) {
                if art == .home { LinearGradient(colors: [Self.oben, Self.unten], startPoint: .top, endPoint: .bottom) } else { Color.clear }
            }
    }
}

struct SenecaDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SenecaDay", provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName("Dein Tag")
        .description("Was jetzt ist und was als Nächstes kommt.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}
