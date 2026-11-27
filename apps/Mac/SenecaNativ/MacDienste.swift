import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import UserNotifications
import WidgetKit

@MainActor
final class GlobalesKuerzel {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var aktion: (() -> Void)?
    private(set) var aktuell: Kuerzel?
    private(set) var status: OSStatus = noErr
    private(set) var ausgeloest = 0
    private static let kennung = EventHotKeyID(signature: 0x534E4B41, id: 1)

    func setze(_ k: Kuerzel?) {
        if k == aktuell, k == nil || ref != nil { return }
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        aktuell = k
        status = noErr
        guard let k else { return }
        installiereHandler()
        status = RegisterEventHotKey(k.taste, k.modifier, Self.kennung, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil }
    }

    private func installiereHandler() {
        guard handler == nil else { return }
        var typ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, daten in
            guard let daten else { return OSStatus(eventNotHandledErr) }
            let selbst = Unmanaged<GlobalesKuerzel>.fromOpaque(daten).takeUnretainedValue()
            let druck = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async { MainActor.assumeIsolated { selbst.ausloesen(seit: druck) } }
            return noErr
        }, 1, &typ, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private(set) var gedrueckt: CFAbsoluteTime = 0
    func ausloesen(seit: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) { gedrueckt = seit; ausgeloest += 1; aktion?() }

    #if DEBUG
    func sendeInProzess() -> OSStatus {
        var e: EventRef?
        var id = Self.kennung
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &e) == noErr, let e else { return -1 }
        SetEventParameter(e, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
        let r = SendEventToEventTarget(e, GetApplicationEventTarget())
        ReleaseEvent(e)
        return r
    }
    #endif
}

@MainActor
final class SystemMitteilungen: NSObject, Mitteilungszentrale, UNUserNotificationCenterDelegate {
    var oeffne: ((String) -> Void)?
    private var zentrale: UNUserNotificationCenter { .current() }

    func melde() { zentrale.delegate = self }

    func status() async -> UNAuthorizationStatus { await zentrale.notificationSettings().authorizationStatus }

    func frageErlaubnis() async -> Bool {
        (try? await zentrale.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func zeige(_ m: Mitteilung) {
        let c = UNMutableNotificationContent()
        c.title = m.titel
        c.body = m.text
        c.userInfo = ["pfad": m.pfad]
        c.threadIdentifier = m.art.rawValue
        c.sound = nil
        zentrale.add(UNNotificationRequest(identifier: m.id, content: c, trigger: nil))
    }

    nonisolated static func oeffnet(_ knopf: String) -> Bool {
        let k = knopf.lowercased()
        return ["lesen", "öffnen", "ansehen", "zeigen"].contains { k.contains($0) }
    }

    var oeffneAufgabe: ((String) -> Void)?

    func zeigeAufgabe(_ m: AufgabenMeldung) async -> Bool {
        var stand = await status()
        if stand == .notDetermined { _ = await frageErlaubnis(); stand = await status() }
        guard stand == .authorized || stand == .provisional else { return false }
        let c = UNMutableNotificationContent()
        c.title = m.titel
        c.body = m.text
        c.userInfo = ["pfad": "#/heute", "aufgabe": m.aufgabe]
        c.threadIdentifier = "seneca.aufgaben"
        c.sound = nil
        do { try await zentrale.add(UNNotificationRequest(identifier: "aufgabe." + m.id, content: c, trigger: nil)); return true } catch { return false }
    }

    var wahl: ((String, String) -> Void)?

    func zeigeMeldung(_ m: TageslaufMeldung) async -> Bool {
        var stand = await status()
        if stand == .notDetermined { _ = await frageErlaubnis(); stand = await status() }
        guard stand == .authorized || stand == .provisional else { return false }
        if let g = m.gruppe {
            var alle = await zentrale.notificationCategories()
            if !alle.contains(where: { $0.identifier == g }) {
                let aktionen = m.knoepfe.enumerated().map { UNNotificationAction(identifier: TageslaufMeldung.knopfKennung($0.offset), title: $0.element, options: Self.oeffnet($0.element) ? [.foreground] : []) }
                alle.insert(UNNotificationCategory(identifier: g, actions: aktionen, intentIdentifiers: [], options: []))
                zentrale.setNotificationCategories(alle)
            }
        }
        let c = UNMutableNotificationContent()
        c.title = m.titel
        c.body = m.text
        c.userInfo = ["pfad": "#/heute", "meldung": m.id, "knoepfe": m.knoepfe]
        c.threadIdentifier = "seneca.meldung"
        if let g = m.gruppe { c.categoryIdentifier = g }
        c.sound = m.dringend ? .default : nil
        do { try await zentrale.add(UNNotificationRequest(identifier: "meldung." + m.id, content: c, trigger: nil)); return true } catch { return false }
    }

    func zeigeMeetingNotiz(titel: String, text: String, datei: URL) async -> Bool {
        var stand = await status()
        if stand == .notDetermined { _ = await frageErlaubnis(); stand = await status() }
        guard stand == .authorized || stand == .provisional else { return false }
        let c = UNMutableNotificationContent()
        c.title = titel
        c.body = text
        c.userInfo = ["datei": datei.path]
        c.threadIdentifier = "seneca.meeting"
        c.sound = nil
        do { try await zentrale.add(UNNotificationRequest(identifier: "meeting." + datei.lastPathComponent, content: c, trigger: nil)); return true } catch { return false }
    }

    func zugestellt() async -> [String] { await zentrale.deliveredNotifications().map(\.request.identifier) }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let id = info["meldung"] as? String, let knoepfe = info["knoepfe"] as? [String],
           let w = TageslaufMeldung.wahl(aktion: response.actionIdentifier, knoepfe: knoepfe) {
            await MainActor.run { self.wahl?(id, w) }
            return
        }
        if let a = info["aufgabe"] as? String, !a.isEmpty {
            await MainActor.run { self.oeffneAufgabe?(a) }
            return
        }
        if let datei = info["datei"] as? String, !datei.isEmpty {
            _ = await MainActor.run { NSWorkspace.shared.open(URL(fileURLWithPath: datei)) }
            return
        }
        guard let pfad = info["pfad"] as? String else { return }
        await MainActor.run { self.oeffne?(pfad) }
    }
}

struct PanelGroesse: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { let n = nextValue(); if n.height > value.height { value = n } }
}

final class SchnellfrageFenster: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var beiEsc: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { beiEsc?() }
}

@MainActor
final class SchnellfragePanel {
    private var fenster: SchnellfrageFenster?
    private let modell: SchnellfrageModell
    private let oeffneFenster: () -> Void
    private var beobachter: NSObjectProtocol?
    private(set) var zeigtSich = false
    private(set) var aufgegangen = 0
    private var zeigeZeit: CFAbsoluteTime = 0
    private var nochmal = 0

    init(modell: SchnellfrageModell, oeffneFenster: @escaping () -> Void) {
        self.modell = modell
        self.oeffneFenster = oeffneFenster
    }

    var hoechsteDeckkraft: CGFloat = 1
    var ohneLesen = false
    private var freigabe: HierFreigabe?
    private var lauf = 0

    func schalte(seit: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) { zeigtSich ? schliesse() : zeige(seit: seit) }

    func bereite() {
        guard fenster == nil else { return }
        baue()
        guard let f = fenster, !zeigtSich else { return }
        f.alphaValue = 0
        f.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        f.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak f] in if self?.zeigtSich == false { f?.orderOut(nil) } }
    }

    private func lies() {
        lauf += 1
        if ohneLesen { return }
        guard let v = HierLeser.vorne() else { return }
        modell.liest = true
        let meiner = lauf
        Task.detached(priority: .userInitiated) { [weak self] in
            if HierLeser.fragtErst(v.bundle) {
                await MainActor.run {
                    guard let self, self.lauf == meiner, self.zeigtSich else { return }
                    self.modell.liest = false
                    self.modell.freigabeSatz = "macOS fragt gerade, ob Seneca \(v.name) lesen darf. Mit „Erlauben“ kennt Seneca künftig, was du dort vor dir hast."
                    self.freigabe = .automation
                }
            }
            let e = await HierLeser.lies(v)
            await MainActor.run {
                guard let self, self.lauf == meiner else { return }
                self.modell.liest = false
                guard self.zeigtSich else { return }
                self.modell.zusammenhang = e.z
                self.modell.freigabeSatz = e.satz
                self.freigabe = e.freigabe
                HierMessung.schreibe(["ereignis": "gelesen", "ms": Int(e.ms), "art": e.z.art.rawValue, "zeichen": e.z.zeichen, "anhaenge": e.z.dateien.count])
            }
        }
    }

    private func passeAn(_ g: CGSize) {
        guard let f = fenster, g.height > 10, abs(f.frame.height - g.height) > 0.5 || abs(f.frame.width - g.width) > 0.5 else { return }
        f.setFrame(NSRect(x: f.frame.minX, y: f.frame.maxY - g.height, width: g.width, height: g.height), display: true)
    }

    func zeige(bild: URL, vorn: String) {
        zeige(fuelle: { m in
            var z = HierZusammenhang(art: .fenster, programm: vorn)
            z.dateien = [bild]
            z.hatBildschirmfoto = true
            m.zusammenhang = z
            m.leerFrage = "Schau dir meinen Bildschirm an und sag mir kurz, was du siehst und was ich als Nächstes tun sollte."
        })
    }

    func zeige(hinweis: String, freigabe: HierFreigabe?) {
        zeige(fuelle: { [weak self] m in
            m.freigabeSatz = hinweis
            self?.freigabe = freigabe
        })
    }

    func zeige(seit: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(), fuelle: ((SchnellfrageModell) -> Void)? = nil) {
        if !modell.beschaeftigt {
            modell.zuruecksetzen(); freigabe = nil
            if let fuelle { lauf += 1; modell.liest = false; fuelle(modell) } else { lies() }
        }
        if fenster == nil { baue() }
        guard let f = fenster else { return }
        let schirm = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let s = schirm?.visibleFrame {
            f.setFrameTopLeftPoint(NSPoint(x: s.midX - f.frame.width / 2, y: s.maxY - s.height * 0.2))
        }
        f.alphaValue = 0
        Hintergrund.zeige(f)
        DispatchQueue.main.async { HierMessung.schreibe(["ereignis": "feld", "ms": Int((CFAbsoluteTimeGetCurrent() - seit) * 1000)]) }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.1
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.24, 1)
            f.animator().alphaValue = hoechsteDeckkraft
        }
        zeigtSich = true
        zeigeZeit = CFAbsoluteTimeGetCurrent()
        nochmal = 0
        aufgegangen += 1
    }

    func schliesse() {
        guard let f = fenster, zeigtSich else { return }
        zeigtSich = false
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.14
            f.animator().alphaValue = 0
        }, completionHandler: { [weak f] in MainActor.assumeIsolated { if f?.alphaValue == 0 { f?.orderOut(nil) } } })
    }

    func sichtbar() -> Bool { fenster?.isVisible == true && zeigtSich }
    var fensterNummer: Int? { fenster?.windowNumber }

    private func baue() {
        let f = SchnellfrageFenster(contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                                    styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        f.isFloatingPanel = true
        f.beiEsc = { [weak self] in self?.schliesse() }
        f.level = .floating
        f.hidesOnDeactivate = false
        f.isOpaque = false
        f.backgroundColor = .clear
        f.hasShadow = false
        f.isMovableByWindowBackground = true
        f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: HierKarte(modell: modell, schliesse: { [weak self] in self?.schliesse() }, imChat: { [weak self] in
            self?.schliesse(); self?.oeffneFenster()
        }, freigabe: { [weak self] in self?.freigabe?.oeffne() })
            .background(GeometryReader { g in Color.clear.preference(key: PanelGroesse.self, value: g.size) })
            .onPreferenceChange(PanelGroesse.self) { [weak self] g in Task { @MainActor in self?.passeAn(g) } }
            .frame(maxHeight: .infinity, alignment: .top)
            .preferredColorScheme(.dark))
        host.sizingOptions = [.intrinsicContentSize]
        f.contentView = host
        f.setContentSize(host.fittingSize)
        fenster = f
        beobachter = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: f, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, let f = self.fenster, self.zeigtSich, CFAbsoluteTimeGetCurrent() - self.zeigeZeit < 0.8, self.nochmal < 5 {
                    self.nochmal += 1
                    DispatchQueue.main.async { f.makeKey() }
                    return
                }
                self?.schliesse()
            }
        }
    }
}

@MainActor
final class MacDienste: ObservableObject {
    let einstellungen = MacEinstellungen()
    let waechter = MitteilungsWaechter()
    let mitteilungen = SystemMitteilungen()
    let schnellfrage = SchnellfrageModell()
    let kuerzel = GlobalesKuerzel()
    let zeichen = MenueZeichenModell()
    var meetingWertetAus = false
    var meetingGemeldet: Set<String> = []
    private(set) var panel: SchnellfragePanel!
    @Published private(set) var stand = MenueStand(braucht: 0, laeuft: 0, ungelesen: 0, termin: nil)
    @Published var mitteilungsHinweis: String?
    private weak var modell: AppModell?
    private var abos: Set<AnyCancellable> = []
    private var letzteZahl: String?
    var protokoll: ((Mitteilung) -> Void)?

    func starte(modell: AppModell) {
        self.modell = modell
        schnellfrage.sende = { [weak modell] text in
            guard let modell else { throw SenecaError.offline }
            return try await modell.chat.send(text, an: .seneca)
        }
        panel = SchnellfragePanel(modell: schnellfrage, oeffneFenster: { [weak modell] in modell?.zeigeFenster(Route(.heute), gespraech: true) })
        kuerzel.aktion = { [weak self] in if let self { self.panel.schalte(seit: self.kuerzel.gedrueckt) } }
        schnellfrage.sendeHier = { [weak modell] text, dateien in
            guard let modell else { throw SenecaError.offline }
            return try await modell.chat.send(text, an: .seneca, anhaenge: dateien.compactMap { ChatAnhang.von($0) })
        }
        schnellfrage.erstesZeichen = { ms in HierMessung.schreibe(["ereignis": "erstesZeichen", "ms": Int(ms)]) }
        modell.chat.$lives.receive(on: DispatchQueue.main).sink { [weak self, weak modell] lives in
            MainActor.assumeIsolated {
                let live = lives[ChatPartner.seneca.sessionKey(main: modell?.chat.mainKey ?? "")]
                self?.schnellfrage.setzeStrom(live?.text ?? "")
                if let live {
                    self?.schnellfrage.laufZeile = Laufzeile.kurz(name: "Seneca", phase: live.phase, taetigkeit: live.activity, verbunden: modell?.store.isConnected ?? true)
                }
            }
        }.store(in: &abos)
        if !MacPfade.nebenher { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.panel.bereite() } }
        mitteilungen.oeffne = { [weak modell] pfad in modell?.zeigeFenster(Route.lies(pfad)) }
        mitteilungen.oeffneAufgabe = { [weak modell] id in
            guard let modell else { return }
            modell.zeigeFenster(nil)
            modell.oeffneAufgabe(id, anker: nil)
        }
        AufgabenMelder.gemeinsam.einstellungen = einstellungen
        AufgabenMelder.gemeinsam.zustellen = { [weak self] m in await self?.mitteilungen.zeigeAufgabe(m) ?? false }
        waechter.zentrale = self
        TagesBegleiter.gemeinsam.starte(mitteilungen: mitteilungen, oeffneHeute: { [weak modell] in modell?.zeigeFenster(Route(.heute)) },
                                        oeffneBerichte: { [weak modell] in
                                            guard let modell else { return }
                                            modell.zeigeFenster(Route(.berichte))
                                            Task {
                                                await modell.uebersicht.ladeBerichte(erzwingen: true)
                                                let heute = Menschlich.tagStart(Date().timeIntervalSince1970 * 1000)
                                                if let b = modell.uebersicht.berichte.liste.filter({ $0.zeit >= heute }).max(by: { $0.zeit < $1.zeit }) {
                                                    modell.zeigeFenster(Route(.berichte, id: b.id))
                                                }
                                            }
                                        })
        waechter.aktiv = { [einstellungen] in einstellungen.meldet($0) }
        if !(MacPfade.profil == .demo || MacPfade.nebenher) { mitteilungen.melde() }
        modell.uebersicht.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.aktualisiere() } }.store(in: &abos)
        einstellungen.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.aktualisiere() } }.store(in: &abos)
        ListenModell.gemeinsam.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.aktualisiere() } }.store(in: &abos)
        AufgabenModell.gemeinsam.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.aktualisiere() } }.store(in: &abos)
        TageslaufModell.gemeinsam.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.aktualisiere() } }.store(in: &abos)
        aktualisiere()
        zeichen.starte(dienste: self, store: modell.store)
        VorneMerker.gemeinsam.starte()
        MeetingDienst.gemeinsam.$zustand.receive(on: DispatchQueue.main)
            .sink { [weak self] z in MainActor.assumeIsolated { self?.meetingStand(z) } }.store(in: &abos)
    }

    func aktualisiere() {
        guard let modell else { return }
        let u = modell.uebersicht
        let neu = MacPfade.profil.echteDaten
            ? MenueStand.aus(u, fragen: ListenModell.gemeinsam.liste.map { $0.fragen.count }, laeuft: AufgabenModell.gemeinsam.liste?.laeuftInsgesamt)
            : MenueStand.aus(u)
        if neu != stand { stand = neu }
        let zahl = einstellungen.dockZahl ? DockZahl.text(neu.braucht) : nil
        if zahl != letzteZahl || NSApp.dockTile.badgeLabel != zahl { letzteZahl = zahl; NSApp.dockTile.badgeLabel = zahl }
        guard !MacPfade.nebenher else { return }
        kuerzel.setze(einstellungen.kuerzel)
        if modell.zustand == .bereit { waechter.pruefe(u); schreibeWidgetStand(u) }
    }

    private func schreibeWidgetStand(_ u: OverviewStore) {
        switch MacPfade.profil {
        case .test, .probe: return
        case .demo: guard ProcessInfo.processInfo.environment["SENECA_WIDGET"] == "1" else { return }
        case .echt: break
        }
        let tag = TageslaufModell.gemeinsam.tag
        guard let neu = MacPfade.profil.echteDaten ? WidgetStand.aus(u, fuerDich: tag?.fuerDich, laeuft: tag?.laeuft) : WidgetStand.aus(u) else { return }
        let jetzt = Date()
        let veraltet = letzterWidgetSchreibzeitpunkt.map { jetzt.timeIntervalSince($0) > 600 } ?? true
        guard veraltet || (letzterWidgetStand.map { Self.sichtbarGleich($0, neu) } != true) else { return }
        letzterWidgetSchreibzeitpunkt = jetzt
        letzterWidgetStand = neu
        if WidgetSpeicher.schreibe(neu) { WidgetCenter.shared.reloadAllTimelines() }
    }
    private var letzterWidgetStand: WidgetStand?
    private var letzterWidgetSchreibzeitpunkt: Date?
    private static func sichtbarGleich(_ a: WidgetStand, _ b: WidgetStand) -> Bool { var x = a; x.geschrieben = b.geschrieben; return x == b }

    func setzeAufgabenMelden(_ an: Bool) {
        einstellungen.aufgabenMelden = an
        guard an else { return }
        Task {
            if await mitteilungen.status() == .notDetermined { _ = await mitteilungen.frageErlaubnis() }
            let s = await mitteilungen.status()
            if s != .authorized && s != .provisional { mitteilungsHinweis = "Das System erlaubt Seneca keine Mitteilungen. Du kannst das in den Systemeinstellungen unter „Mitteilungen“ ändern." }
        }
    }

    func setzeMitteilungen(_ an: Bool) {
        mitteilungsHinweis = nil
        guard an else { einstellungen.mitteilungenAn = false; return }
        Task {
            let ok = await mitteilungen.frageErlaubnis()
            einstellungen.mitteilungenAn = ok
            if !ok { mitteilungsHinweis = "Das System erlaubt Seneca keine Mitteilungen. Du kannst das in den Systemeinstellungen unter „Mitteilungen“ ändern." }
        }
    }
}

extension MacDienste: Mitteilungszentrale {
    func zeige(_ m: Mitteilung) {
        if let protokoll { protokoll(m) } else { mitteilungen.zeige(m) }
    }
}
