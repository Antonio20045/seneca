import ActivityKit
import SwiftUI
import WidgetKit

struct SenecaLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SenecaLive.self) { ctx in
            LiveKarte(s: ctx.state)
                .activityBackgroundTint(LiveFarbe.grund)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "seneca://team"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { LiveKarte(s: ctx.state) }
            } compactLeading: {
                LiveZeichen(art: ctx.state.art, groesse: 18)
            } compactTrailing: {
                Text(ctx.state.insel).font(LiveFarbe.grotesk(14, true)).monospacedDigit()
                    .foregroundStyle(["arbeitet", "fertig", "unterwegs"].contains(ctx.state.art) ? LiveFarbe.gruen : ctx.state.art == "frage" ? LiveFarbe.bernstein : .white)
            } minimal: {
                LiveZeichen(art: ctx.state.art, groesse: 18)
            }
            .widgetURL(URL(string: "seneca://team"))
        }
    }
}
