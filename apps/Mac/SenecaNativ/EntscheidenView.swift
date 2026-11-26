import SwiftUI

@MainActor
final class EntscheidenModell: ObservableObject {
    let store: OverviewStore
    var rueckfrage: (OvEntscheidung) -> Void = { _ in }

    @Published var index = 0
    @Published var gewaehlt: [String: String] = [:]
    @Published var detailsOffen = false
    @Published var andersOffen = false
    @Published var andersText = ""

    init(store: OverviewStore) { self.store = store }

    var gruppen: [Entscheiden.Gruppe] { Entscheiden.gruppiere(store.entscheidungenSicht, jetzt: store.jetzt) }
    var schlange: [OvEntscheidung] { gruppen.filter { $0.art != .spaeter }.flatMap(\.liste) }
    var spaeter: [OvEntscheidung] { gruppen.first { $0.art == .spaeter }?.liste ?? [] }
    var aktuell: OvEntscheidung? { let s = schlange; return s.isEmpty ? nil : s[min(max(index, 0), s.count - 1)] }
    var position: Int { min(max(index, 0), max(schlange.count - 1, 0)) }

    func wahl(_ e: OvEntscheidung) -> String? { gewaehlt[e.id] ?? Entscheiden.vorwahl(e) }

    private func neuesBlatt() { detailsOffen = false; andersOffen = false; andersText = "" }

    func weiter() { if position < schlange.count - 1 { index = position + 1; neuesBlatt() } }
    func zurueck() { if position > 0 { index = position - 1; neuesBlatt() } }
    func geheZu(_ id: String) { if let i = schlange.firstIndex(where: { $0.id == id }) { index = i; neuesBlatt() } }

    func waehle(nummer n: Int) {
        guard let e = aktuell, n >= 1, n <= e.optionen.count else { return }
        gewaehlt[e.id] = e.optionen[n - 1].key
        andersOffen = false
    }

    func schalteDetails() { detailsOffen.toggle() }

    func schalteAnders() { andersOffen.toggle() }

    func entscheide() {
        guard let e = aktuell else { return }
        let text = andersText.trimmingCharacters(in: .whitespacesAndNewlines)
        if andersOffen {
            guard !text.isEmpty else { return }
            store.entscheide(e, .init(wahl: nil, text: text))
        } else {
            guard let w = wahl(e) else { return }
            store.entscheide(e, .init(wahl: w))
        }
        neuesBlatt()
    }

    func vertage(_ t: Entscheiden.Tag? = nil) {
        guard let e = aktuell else { return }
        let tag = t ?? Entscheiden.naechsteTage(jetzt: store.jetzt)[0]
        neuesBlatt()
        Task { await store.vertage(e, bis: tag.bis, label: tag.label) }
    }

    func fragZurueck() { if let e = aktuell { rueckfrage(e) } }
}
