import WidgetKit
import SwiftUI

struct DayEntry: TimelineEntry {
    let date: Date
    let lage: WidgetLage?
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date(), lage: WidgetStore.read()) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) { completion(placeholder(in: context)) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let lage = WidgetStore.read()
        completion(Timeline(entries: WidgetLogik.zeiten(lage, ab: Date()).map { DayEntry(date: $0, lage: lage) }, policy: .never))
    }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private var art: WidgetFace.Art {
        switch family {
        case .accessoryInline: return .zeile
        case .accessoryCircular: return .kreis
        case .accessoryRectangular: return .rechteck
        case .systemMedium: return .mittel
        default: return .klein
        }
    }

    var body: some View {
        WidgetFace(lage: entry.lage, jetzt: entry.date, art: art)
            .containerBackground(for: .widget) {
                if art == .klein || art == .mittel { WidgetFarbe.grund } else { Color.clear }
            }
    }
}

struct SenecaDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SenecaDay", provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName("Seneca")
        .description("Die nächste Sache, dazu, was wartet.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}
