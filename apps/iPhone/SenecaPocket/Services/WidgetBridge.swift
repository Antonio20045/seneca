import Foundation
import Combine
import WidgetKit

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var sink: AnyCancellable?
    private var letzte: WidgetLage?

    func attach(_ store: SenecaStore) {
        guard sink == nil else { return }
        sink = store.$stand.compactMap { $0 }
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] s in
                self?.schreiben(WidgetLogik.lage(s))
                TeilenEingang.teamMerken((s.team ?? []).map { [$0.name, "\(ChatTafelLogik.punkt($0, s))"] })
            }
    }

    private func schreiben(_ l: WidgetLage) {
        WidgetStore.write(l)
        let anders = letzte.map { var a = $0; a.stand = l.stand; return a != l } ?? true
        letzte = l
        if anders { WidgetCenter.shared.reloadAllTimelines() }
    }
}
