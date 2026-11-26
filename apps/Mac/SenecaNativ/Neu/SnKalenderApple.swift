import Foundation
import EventKit
import CoreGraphics

@MainActor
protocol SnKalWeg: AnyObject {
    var kalender: [KalKalender] { get }
    var vorgabeKalender: String? { get }
    var kannAendern: Bool { get }
    func lies(_ z: DateInterval) async -> [KalEreignis]?
    func sichere(_ q: KalEntwurf, alt: KalEreignis?) async throws
    func loesche(_ e: KalEreignis) async throws
}

struct SnKalFehler: LocalizedError {
    let satz: String
    var errorDescription: String? { satz }
}

@MainActor
final class SnAppleKalender: SnKalWeg {
    private struct Kiste: @unchecked Sendable { let store: EKEventStore }
    private let store = EKEventStore()

    static var erlaubt: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var gefragt: Bool { EKEventStore.authorizationStatus(for: .event) != .notDetermined }

    func frage() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }

    var kannAendern: Bool { true }

    var kalender: [KalKalender] {
        store.calendars(for: .event)
            .map { KalKalender(id: $0.calendarIdentifier, name: $0.title, farbe: Self.hex($0.cgColor), schreibbar: $0.allowsContentModifications) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var vorgabeKalender: String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    func lies(_ z: DateInterval) async -> [KalEreignis]? {
        let k = Kiste(store: store)
        return await Task.detached(priority: .userInitiated) {
            k.store.events(matching: k.store.predicateForEvents(withStart: z.start, end: z.end, calendars: nil)).map(Self.ereignis)
        }.value
    }

    func sichere(_ q: KalEntwurf, alt: KalEreignis?) async throws {
        let ev: EKEvent
        if let alt {
            guard let f = finde(alt) else { throw SnKalFehler(satz: "Der Termin steht nicht mehr in Apple Kalender.") }
            ev = f
        } else {
            ev = EKEvent(eventStore: store)
        }
        ev.title = q.titelSauber
        ev.isAllDay = q.ganztags
        ev.startDate = q.start
        ev.endDate = q.ende
        let ort = q.ort.trimmingCharacters(in: .whitespacesAndNewlines)
        ev.location = ort.isEmpty ? nil : ort
        ev.notes = q.notiz.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : q.notiz
        if let id = q.kalenderId, let c = store.calendar(withIdentifier: id), c.allowsContentModifications, ev.calendar?.calendarIdentifier != id {
            ev.calendar = c
        }
        if ev.calendar == nil { ev.calendar = store.defaultCalendarForNewEvents }
        guard ev.calendar != nil else { throw SnKalFehler(satz: "Es gibt keinen Kalender, in den Seneca schreiben darf.") }
        try store.save(ev, span: .thisEvent, commit: true)
    }

    func loesche(_ e: KalEreignis) async throws {
        guard let ev = finde(e) else { return }
        try store.remove(ev, span: .thisEvent, commit: true)
    }

    private func finde(_ e: KalEreignis) -> EKEvent? {
        let teile = e.id.components(separatedBy: "|")
        guard teile.count == 2, let t = Double(teile[1]) else { return store.event(withIdentifier: e.id) }
        let p = store.predicateForEvents(withStart: e.start.addingTimeInterval(-86_400), end: e.ende.addingTimeInterval(86_400), calendars: nil)
        return store.events(matching: p).first { $0.eventIdentifier == teile[0] && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince1970 - t) < 1 }
    }

    nonisolated private static func ereignis(_ ev: EKEvent) -> KalEreignis {
        let serie = ev.hasRecurrenceRules || ev.isDetached
        let kennung = ev.eventIdentifier ?? UUID().uuidString
        let ort = ev.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return KalEreignis(
            id: serie ? "\(kennung)|\((ev.occurrenceDate ?? ev.startDate).timeIntervalSince1970)" : kennung,
            titel: (ev.title ?? "").isEmpty ? "Ohne Titel" : ev.title,
            start: ev.startDate, ende: max(ev.endDate, ev.startDate), ganztags: ev.isAllDay,
            kalender: ev.calendar?.title, kalenderId: ev.calendar?.calendarIdentifier, farbe: ev.calendar.flatMap { hex($0.cgColor) },
            ort: (ort ?? "").isEmpty ? nil : ort, notiz: (ev.notes ?? "").isEmpty ? nil : ev.notes,
            aenderbar: (ev.calendar?.allowsContentModifications ?? false) && !ev.hasAttendees,
            serie: serie)
    }

    nonisolated private static func hex(_ c: CGColor?) -> UInt32? {
        guard let c, let s = CGColorSpace(name: CGColorSpace.sRGB), let k = c.converted(to: s, intent: .defaultIntent, options: nil)?.components, k.count >= 3 else { return nil }
        func b(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return b(k[0]) << 16 | b(k[1]) << 8 | b(k[2])
    }
}
