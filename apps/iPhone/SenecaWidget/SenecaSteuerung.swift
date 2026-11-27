import WidgetKit
import SwiftUI
import AppIntents

@main
struct SenecaWidgets: WidgetBundle {
    var body: some Widget {
        SenecaDayWidget()
        SenecaLiveWidget()
    }
}
