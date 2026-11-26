import SwiftUI

struct FadenFrage: View {
    var text: String
    var breite: CGFloat

    var body: some View {
        Text(text)
            .schrift(.text)
            .foregroundStyle(Stil.tinte.voll)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, Stil.abstand.m)
            .padding(.vertical, Stil.abstand.s)
            .background(RoundedRectangle(cornerRadius: Stil.radius.mittel, style: .continuous).fill(Stil.tinte.flaecheStark))
            .frame(maxWidth: breite * 0.8, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Du: \(text)")
    }
}

struct FadenAntwort: View {
    var text: String
    var sprecher: String

    var body: some View {
        FadenMarkdown(text: text, live: false, sprecher: sprecher)
    }
}

struct FadenDatum: View {
    var text: String

    var body: some View {
        Text(text)
            .schrift(.klein)
            .foregroundStyle(Stil.tinte.leise)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
final class WortTakt: ObservableObject {
    @Published private(set) var sichtbar = ""
    @Published private(set) var frisch = FrischSpanne.keine
    @Published private(set) var beendet = false

    private var text = ""
    private var final = false
    private var schnitte: [String.Index] = []
    private var plan = WortTaktPlan()
    private var gezeigteBytes = 0
    private var lauf: Task<Void, Never>?

    var anzahl: Int { plan.angezeigt }

    func setzeText(_ neu: String, final: Bool = false) {
        if neu != text || final != self.final {
            text = neu
            self.final = final
            schnitte = WortSchnitte.schnitte(neu, final: final)
        }
        plan.setzeZiel(schnitte.count)
        if final { plan.schliesseAb(jetzt: Self.jetzt()) }
        starte()
    }

    private static func jetzt() -> Double { ProcessInfo.processInfo.systemUptime }

    private func starte() {
        guard lauf == nil else { return }
        guard takt(schleife: false) else { return }
        lauf = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(WortTaktPlan.intervall * 1000)))
                guard let weiter = self?.takt(schleife: true), weiter else { break }
            }
            self?.lauf = nil
        }
    }

    private func takt(schleife: Bool) -> Bool {
        let dazu = plan.schritt(jetzt: Self.jetzt())
        let n = min(plan.angezeigt, schnitte.count)
        let ende = n == 0 ? text.startIndex : schnitte[n - 1]
        let teil = String(text[..<ende])
        if teil != sichtbar { sichtbar = teil }
        let bytes = teil.utf8.count
        let zeichen = max(0, bytes - gezeigteBytes)
        gezeigteBytes = bytes
        if dazu > 0 || schleife {
            let neu = frisch.weiter(dazu: dazu > 0 ? zeichen : 0)
            if neu != frisch { frisch = neu }
        }
        let aus = plan.beendet
        if aus != beendet { beendet = aus }
        return !plan.fertig || !frisch.istKeine
    }

    deinit { lauf?.cancel() }
}

struct FadenWachsend: View {
    var text: String
    var sprecher: String
    var final = false
    @StateObject private var takt = WortTakt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FadenMarkdown(text: takt.sichtbar, live: !takt.beendet, frisch: reduceMotion ? .keine : takt.frisch,
                      sprecher: sprecher, ansage: "\(sprecher) schreibt gerade")
            .onAppear { takt.setzeText(text, final: final) }
            .onChange(of: text) { _, neu in takt.setzeText(neu, final: final) }
            .onChange(of: final) { _, ende in takt.setzeText(text, final: ende) }
    }
}
