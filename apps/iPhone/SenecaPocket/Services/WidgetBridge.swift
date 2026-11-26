import Foundation
import Combine
import WidgetKit

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var sink: AnyCancellable?
    private var lastWritten: WidgetSnapshot?
    private var lastReload = Date.distantPast

    func attach(_ store: SenecaStore) {
        guard sink == nil else { return }
        sink = store.$today.combineLatest(store.$kalenderLang)
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self, weak store] _ in
                guard let self, !self.vomAblauf, let store, let today = store.today else { return }
                self.write(Self.snapshot(today, termine: store.kalenderTermine, stand: store.kalenderStand, now: store.clock()))
            }
    }

    static func snapshot(_ today: TodaySnapshot, termine: [KalenderTermin]? = nil, stand: Date? = nil, now: Date,
                         _ cal: Calendar = .current) -> WidgetSnapshot {
        let entries = termine.map(KalenderParser.eintraege) ?? today.calendar
        let input = DayInput(now: now, calendar: cal, entries: entries, jobs: today.jobs ?? [], leaders: today.leaders ?? [:],
                             tasks: today.tasks, days: [:], routineDoneToday: false)
        let dayStart = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let horizon = cal.date(byAdding: .day, value: 2, to: dayStart)!
        let orte = Dictionary((termine ?? []).compactMap { t in t.place.map { ("\(t.title)|\(t.start.timeIntervalSince1970)", $0) } },
                              uniquingKeysWith: { a, _ in a })
        let items = (DayLogic.items(on: now, input) + DayLogic.items(on: tomorrow, input))
            .map { WidgetSnapshot.Item(title: $0.title, start: $0.start, end: $0.end, place: orte["\($0.title)|\($0.start.timeIntervalSince1970)"]) }
        return WidgetLogic.snapshot(items: items, now: now, horizon: horizon, stand: stand)
    }

    func ablauf(_ punkte: [AblaufPunkt], stand: Date?, now: Date) {
        vomAblauf = true
        write(Tagesablauf.widget(punkte, jetzt: now, stand: stand))
    }
    private var vomAblauf = false

    private func write(_ snapshot: WidgetSnapshot) {
        WidgetStore.write(snapshot)
        let standSprung = abs((lastWritten?.stand ?? .distantPast).timeIntervalSince(snapshot.stand ?? .distantPast)) > 3600
        let changed = lastWritten.map { $0.items != snapshot.items || $0.laufend != snapshot.laufend || standSprung } ?? true
        lastWritten = snapshot
        guard changed || Date().timeIntervalSince(lastReload) > 30 * 60 else { return }
        lastReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
