import WidgetKit
import SwiftUI
import AppIntents

@main
struct SenecaWidgets: WidgetBundle {
    var body: some Widget {
        SenecaDayWidget()
        SenecaSagenControl()
        SenecaLiveWidget()
    }
}

struct SenecaSagenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "de.antonio.senecapocket.sagen") {
            ControlWidgetButton(action: SenecaSagenIntent()) {
                Label("Seneca etwas sagen", systemImage: "mic.fill")
            }
        }
        .displayName("Seneca etwas sagen")
        .description("Öffnet Seneca und hört dir sofort zu.")
    }
}
