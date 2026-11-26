import WidgetKit
import SwiftUI

struct StandProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandEintrag { StandEintrag(date: Date(), stand: .beispiel(), beispiel: true) }

    func getSnapshot(in context: Context, completion: @escaping (StandEintrag) -> Void) {
        let jetzt = Date()
        let gelesen = WidgetSpeicher.lies()
        if context.isPreview, gelesen == nil { completion(placeholder(in: context)) }
        else { completion(StandEintrag(date: jetzt, stand: gelesen, beispiel: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandEintrag>) -> Void) {
        let jetzt = Date()
        let stand = WidgetSpeicher.lies()
        let eintraege = WidgetSpeicher.zeitpunkte(stand, ab: jetzt).map { StandEintrag(date: $0, stand: stand, beispiel: false) }
        completion(Timeline(entries: eintraege, policy: .after(jetzt.addingTimeInterval(1800))))
    }
}

struct HeuteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SenecaNativHeute", provider: StandProvider()) { HeuteWidgetView(eintrag: $0) }
            .configurationDisplayName("Heute")
            .description("Der Satz zur Lage, was läuft und was ungelesen ist.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BrauchtWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SenecaNativBraucht", provider: StandProvider()) { BrauchtWidgetView(eintrag: $0) }
            .configurationDisplayName("Braucht dich")
            .description("Wie viele Entscheidungen warten, und die ersten Fragen.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TerminWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SenecaNativTermin", provider: StandProvider()) { TerminWidgetView(eintrag: $0) }
            .configurationDisplayName("Nächster Termin")
            .description("Der nächste Termin mit Uhrzeit und Ort.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SenecaNativWidgets: WidgetBundle {
    var body: some Widget {
        HeuteWidget()
        BrauchtWidget()
        TerminWidget()
    }
}
