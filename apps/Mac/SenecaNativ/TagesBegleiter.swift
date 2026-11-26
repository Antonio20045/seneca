import AppKit
import UserNotifications

@MainActor
final class TagesBegleiter: NSObject {
    static let gemeinsam = TagesBegleiter()
    private static let merker = "seneca.meldungen.gezeigt"

    private var takt: Takt?
    private var laeuft = false
    private var zeichen: NSStatusItem?
    private var oeffneHeute: (() -> Void)?
    private var oeffneBerichte: (() -> Void)?
    private weak var mitteilungen: SystemMitteilungen?
    private var gezeigt: [String] = UserDefaults.standard.stringArray(forKey: TagesBegleiter.merker) ?? []

    func starte(mitteilungen: SystemMitteilungen, oeffneHeute: @escaping () -> Void, oeffneBerichte: @escaping () -> Void) {
        guard TageslaufHaken.erlaubt, takt == nil else { return }
        self.mitteilungen = mitteilungen
        self.oeffneHeute = oeffneHeute
        self.oeffneBerichte = oeffneBerichte
        mitteilungen.wahl = { [weak self] id, knopf in
            Task { _ = await Kindprozess.laufe(TageslaufModell.befehl, ["meldung-antwort", "--id", id, "--wahl", knopf], limit: 20, ausgabe: false) }
            if SystemMitteilungen.oeffnet(knopf) { self?.oeffneBerichte?() }
        }
        takt = Takt(sekunden: 60, verzoegerung: 3) { [weak self] in await self?.runde() }
    }

    private func runde() async {
        guard !laeuft else { return }
        laeuft = true
        defer { laeuft = false }
        let tag = await TageslaufModell.gemeinsam.lade()
        zeige(MenueTag.zeile(tag, jetzt: Date()))
        guard let daten = await Kindprozess.laufe(TageslaufModell.befehl, ["meldungen", "--neu", "--json"], limit: 20), let mitteilungen else { return }
        for m in TageslaufMeldung.lies(daten) where !gezeigt.contains(m.id) {
            guard await mitteilungen.zeigeMeldung(m) else { return }
            gezeigt = Array((gezeigt + [m.id]).suffix(200))
            UserDefaults.standard.set(gezeigt, forKey: Self.merker)
            _ = await Kindprozess.laufe(TageslaufModell.befehl, ["meldungen", "--gezeigt", m.id], limit: 20, ausgabe: false)
        }
    }

    private func zeige(_ zeile: String) {
        if zeile.isEmpty { zeichen?.isVisible = false; return }
        if zeichen == nil {
            let z = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            z.button?.target = self
            z.button?.action = #selector(klick)
            z.button?.font = NSFont.menuBarFont(ofSize: 0)
            z.button?.setAccessibilityLabel("Seneca, dein Tag")
            zeichen = z
        }
        zeichen?.isVisible = true
        if zeichen?.button?.title != zeile { zeichen?.button?.title = zeile }
    }

    @objc private func klick() { oeffneHeute?() }
}
