import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

enum HierFreigabe: String, Sendable {
    case automation = "Privacy_Automation", bildschirm = "Privacy_ScreenCapture", bedienungshilfen = "Privacy_Accessibility"

    @MainActor func oeffne() {
        if self == .bildschirm, !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") { NSWorkspace.shared.open(u) }
    }
}

enum HierLeser {
    struct Vorne: Sendable { let pid: pid_t; let name: String; let bundle: String }
    struct Ergebnis: Sendable {
        var z: HierZusammenhang
        var satz: String?
        var freigabe: HierFreigabe?
        var ms: Double
    }

    static let browser: [String: Bool] = [
        "com.apple.Safari": false, "com.apple.SafariTechnologyPreview": false,
        "com.google.Chrome": true, "company.thebrowser.Browser": true, "com.brave.Browser": true, "com.microsoft.edgemac": true,
    ]

    @MainActor static func vorne() -> Vorne? {
        guard let a = NSWorkspace.shared.frontmostApplication, a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return Vorne(pid: a.processIdentifier, name: a.localizedName ?? "", bundle: a.bundleIdentifier ?? "")
    }

    static func ax(_ pid: pid_t) -> (markiert: String, titel: String) {
        guard AXIsProcessTrusted() else { return ("", "") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        func wert(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var w: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, name as CFString, &w) == .success ? w : nil
        }
        var markiert = "", titel = ""
        if let f = wert(app, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() {
            markiert = wert(f as! AXUIElement, kAXSelectedTextAttribute) as? String ?? ""
        }
        if let w = wert(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() {
            titel = wert(w as! AXUIElement, kAXTitleAttribute) as? String ?? ""
        }
        return (markiert.trimmingCharacters(in: .whitespacesAndNewlines), titel)
    }

    static func automationStand(_ bundle: String) -> Int { Int(automation(bundle)) }

    static func fragtErst(_ bundle: String) -> Bool {
        guard browser[bundle] != nil || bundle == "com.apple.mail" || bundle == "com.apple.finder" else { return false }
        return automation(bundle) == OSStatus(errAEEventWouldRequireUserConsent)
    }

    private static func automation(_ bundle: String) -> OSStatus {
        let ziel = NSAppleEventDescriptor(bundleIdentifier: bundle)
        guard let d = ziel.aeDesc else { return 0 }
        return AEDeterminePermissionToAutomateTarget(d, typeWildCard, typeWildCard, false)
    }

    private static func skript(_ zeilen: String, limit: TimeInterval) async -> String? {
        guard let d = await Kindprozess.laufe(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", zeilen], limit: limit) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func skriptFuer(_ v: Vorne, art: HierZusammenhang.Art) -> String {
        let app = "application id \"\(v.bundle)\""
        switch art {
        case .browser where browser[v.bundle] == true:
            return """
            tell \(app)
              if (count of windows) is 0 then return ""
              set t to active tab of front window
              set s to ""
              try
                tell t to set s to (execute javascript "document.body.innerText")
              end try
              if s is missing value then set s to ""
              return (URL of t) & linefeed & (title of t) & linefeed & s
            end tell
            """
        case .browser:
            return """
            tell \(app)
              if (count of documents) is 0 then return ""
              set d to front document
              set s to ""
              try
                set s to text of d
              end try
              return (URL of d) & linefeed & (name of d) & linefeed & s
            end tell
            """
        case .mail:
            return """
            tell \(app)
              set sel to selection
              if (count of sel) is 0 then return ""
              set m to item 1 of sel
              return (subject of m) & linefeed & (sender of m) & linefeed & (content of m)
            end tell
            """
        default:
            return """
            tell \(app)
              set out to ""
              repeat with f in (get selection)
                set out to out & POSIX path of (f as alias) & linefeed
              end repeat
              return out
            end tell
            """
        }
    }

    static func fensterfoto(_ pid: pid_t) async -> URL? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let liste = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let nummer = liste.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] as? CGWindowID
        guard let inhalt = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let eigene = inhalt.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 120 }
        guard let w = eigene.first(where: { $0.windowID == nummer }) ?? eigene.first else { return nil }
        let cfg = SCStreamConfiguration()
        let skala = min(2, Double(ChatAnhang.maxBildKante) / Double(max(w.frame.width, w.frame.height)))
        cfg.width = Int(w.frame.width * skala); cfg.height = Int(w.frame.height * skala)
        cfg.showsCursor = false
        guard let bild = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg),
              let jpg = NSBitmapImageRep(cgImage: bild).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return ChatAnhang.ausDaten(jpg, name: "Fenster-\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")?.url
    }

    static func lies(_ v: Vorne) async -> Ergebnis {
        let start = CFAbsoluteTimeGetCurrent()
        let a = ax(v.pid)
        var z = HierZusammenhang(art: .fenster, programm: v.name, titel: a.titel, markiert: a.markiert)
        var satz: String?, freigabe: HierFreigabe?
        let art: HierZusammenhang.Art? = browser[v.bundle] != nil ? .browser : v.bundle == "com.apple.mail" ? .mail : v.bundle == "com.apple.finder" ? .finder : nil
        if let art {
            z.art = art
            let erlaubt = automation(v.bundle)
            if erlaubt == OSStatus(errAEEventNotPermitted) {
                satz = "Seneca darf \(v.name) nicht lesen und sieht deshalb nur den Fenstertitel. Einschalten lässt sich das in den Systemeinstellungen unter Datenschutz, Automation."
                freigabe = .automation
                z.art = .fenster
            } else {
                let ersteFrage = erlaubt == OSStatus(errAEEventWouldRequireUserConsent)
                let aus = await skript(skriptFuer(v, art: art), limit: ersteFrage ? 90 : 6)
                if aus == nil, ersteFrage {
                    satz = "macOS fragt einmal, ob Seneca \(v.name) lesen darf. Mit „Erlauben“ kennt Seneca künftig, was du dort vor dir hast."
                    freigabe = .automation
                    z.art = .fenster
                } else if let aus {
                    let teile = aus.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                    switch art {
                    case .browser:
                        z.adresse = teile.first?.trimmingCharacters(in: .whitespaces) ?? ""
                        if teile.count > 1, !teile[1].isEmpty { z.titel = teile[1] }
                        z.text = teile.count > 2 ? teile[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        if z.text.isEmpty, browser[v.bundle] == true, !z.adresse.isEmpty {
                            satz = "\(v.name) gibt den Text der Seite erst frei, wenn dort im Menü Darstellung, Entwickler „JavaScript von Apple Events erlauben“ eingeschaltet ist. Bis dahin kennt Seneca Adresse und Titel."
                        }
                    case .mail:
                        if teile.count > 2 { z.titel = teile[0]; z.absender = teile[1]; z.text = teile[2].trimmingCharacters(in: .whitespacesAndNewlines) } else { z.art = .fenster }
                    default:
                        let urls = aus.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
                        z.dateien = Array(urls.filter { ChatAnhang.von($0)?.problem == nil && ChatAnhang.von($0) != nil }.prefix(5))
                        if z.dateien.isEmpty { z.art = .fenster }
                    }
                } else { z.art = .fenster }
            }
        }
        if z.dateien.isEmpty {
            if let foto = await fensterfoto(v.pid) { z.dateien = [foto]; z.hatFensterfoto = true }
            else if satz == nil, !CGPreflightScreenCaptureAccess() {
                satz = "Mit der Freigabe „Bildschirmaufnahme“ bekäme Seneca zusätzlich ein Foto dieses Fensters."
                freigabe = .bildschirm
            }
        }
        if satz == nil, !AXIsProcessTrusted() {
            satz = "Mit der Freigabe „Bedienungshilfen“ sähe Seneca auch, was du markiert hast."
            freigabe = .bedienungshilfen
        }
        return Ergebnis(z: z, satz: satz, freigabe: freigabe, ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

enum BildschirmFoto {
    enum Ergebnis: Sendable { case foto(URL), keineFreigabe, fehler }

    @MainActor static func unterMaus() -> CGDirectDisplayID? {
        let maus = NSEvent.mouseLocation
        let schirm = NSScreen.screens.first { NSMouseInRect(maus, $0.frame, false) } ?? NSScreen.main
        return (schirm?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func nimm(display: CGDirectDisplayID?) async -> Ergebnis {
        guard CGPreflightScreenCaptureAccess() else { return .keineFreigabe }
        guard let inhalt = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let d = inhalt.displays.first(where: { $0.displayID == display }) ?? inhalt.displays.first else { return .fehler }
        let ich = ProcessInfo.processInfo.processIdentifier
        let schwebend = inhalt.windows.filter { $0.owningApplication?.processID == ich && $0.windowLayer != 0 }
        let cfg = SCStreamConfiguration()
        let skala = min(2, Double(ChatAnhang.maxBildKante) / Double(max(d.width, d.height, 1)))
        cfg.width = max(1, Int(Double(d.width) * skala)); cfg.height = max(1, Int(Double(d.height) * skala))
        cfg.showsCursor = false
        guard let bild = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, excludingWindows: schwebend), configuration: cfg),
              let jpg = NSBitmapImageRep(cgImage: bild).representation(using: .jpeg, properties: [.compressionFactor: 0.8]),
              let a = ChatAnhang.ausDaten(jpg, name: "Bildschirm-\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg") else { return .fehler }
        return .foto(a.url)
    }
}

struct HierVorschau: View {
    let datei: URL
    var breite: CGFloat = 176
    var stelle: CGRect?
    @State private var bild: NSImage?

    var body: some View {
        ZStack { if let bild { Image(nsImage: bild).resizable().aspectRatio(contentMode: .fill) } }
            .frame(width: breite, height: breite * 0.58)
            .overlay { if let stelle, let bild { marke(stelle, bild.size) } }.background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .task(id: datei) { bild = NSImage(contentsOf: datei) }
            .accessibilityLabel("Foto deines Bildschirms")
            .accessibilityIdentifier("hier-vorschau")
    }

    private func marke(_ r: CGRect, _ g: CGSize) -> some View {
        let h = breite * 0.58, s = max(breite / max(g.width, 1), h / max(g.height, 1))
        let w = g.width * s, hh = g.height * s
        return RoundedRectangle(cornerRadius: 4, style: .continuous).fill(TafelFarbe.himmel.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(TafelFarbe.himmel, lineWidth: 1.5))
            .frame(width: r.width * w, height: r.height * hh)
            .position(x: (breite - w) / 2 + r.midX * w, y: (h - hh) / 2 + r.midY * hh)
            .transition(.opacity)
    }
}

enum HierMessung {
    static func schreibe(_ werte: [String: Any]) {
        guard let ordner = MacPfade.datenOrdner else { return }
        var w = werte
        w["zeit"] = ISO8601DateFormatter().string(from: Date())
        guard var d = try? JSONSerialization.data(withJSONObject: w, options: [.sortedKeys]) else { return }
        d.append(0x0A)
        let url = ordner.appendingPathComponent("seneca-hier.log")
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: d) } else { try? d.write(to: url) }
    }
}

struct HierKarte: View {
    @ObservedObject var modell: SchnellfrageModell
    var schliesse: () -> Void = {}
    var imChat: () -> Void = {}
    var freigabe: (() -> Void)?
    var ausschnitt: (String) -> Void = { _ in }
    @FocusState private var fokus: Bool

    private var foto: URL? { modell.zusammenhang.flatMap { $0.hatBildschirmfoto || $0.hatFensterfoto ? $0.dateien.first : nil } }
    private var art: String { !modell.ausschnitt.isEmpty ? modell.ausschnitt : modell.zusammenhang?.hatBildschirmfoto == true ? "bildschirm" : "fenster" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch modell.phase {
            case .antwort(let frage, let text): antwort(frage, text)
            case .wartet(let frage): antwort(frage, modell.strom.isEmpty ? (modell.laufZeile.isEmpty ? "Deine Frage geht an Seneca." : modell.laufZeile) : modell.strom, fertig: false)
            default: eingabe
            }
        }
        .padding(.horizontal, modell.phase == .eingabe ? 18 : 22).padding(.vertical, modell.phase == .eingabe ? 18 : 20)
        .frame(width: modell.phase == .eingabe ? 700 : 760, alignment: .leading)
        .background(ZStack {
            LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [TafelFarbe.himmel.opacity(0.26), TafelFarbe.himmel.opacity(0.11), .clear], center: UnitPoint(x: 0.76, y: 0.1), startRadius: 0, endRadius: 300)
        }.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 35, y: 30)
        .padding(.horizontal, 40).padding(.top, 14).padding(.bottom, 60)
        .animation(Kurve.ease(0.22), value: modell.phase)
        .onAppear { fokus = true }
        .onChange(of: modell.phase) { _, _ in if !modell.beschaeftigt { fokus = true } }
    }

    @ViewBuilder private var eingabe: some View {
        if let z = modell.zusammenhang, !z.istLeer {
            HStack(alignment: .center, spacing: 16) {
                if let foto { HierVorschau(datei: foto) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("SENECA SIEHT").font(Schrift.mono(11)).kerning(1.2).foregroundStyle(TafelFarbe.leise)
                    Text(art == "bildschirm" ? "Ganzer Bildschirm" + (z.programm.isEmpty ? "" : " · vorn \(z.programm)") : z.sichtKurz).font(Schrift.grotesk(15)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 2) {
                        ForEach([("fenster", "macwindow", "Fenster"), ("bildschirm", "display", "Ganzer Bildschirm"), ("bereich", "viewfinder", "Bereich ziehen")], id: \.0) { k, bild, titel in
                            Button { ausschnitt(k) } label: {
                                Label(titel, systemImage: bild).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(art == k ? .white : TafelFarbe.leise)
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(art == k ? 0.14 : 0)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                }
            }
        }
        HStack(spacing: 12) {
            TextField("", text: $modell.text, prompt: Text(foto != nil ? "Was siehst du?" : "Frag Seneca etwas").foregroundColor(TafelFarbe.leise))
                .textFieldStyle(.plain).font(Schrift.grotesk(16)).foregroundStyle(.white).focused($fokus)
                .onSubmit { Task { await modell.abschicken() } }.onExitCommand { schliesse() }.accessibilityIdentifier("schnellfrage-feld")
            Label("rechte ⌘", systemImage: "mic").font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise).fixedSize()
            Button { Task { await modell.abschicken() } } label: {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel).frame(width: 34, height: 34).background(Circle().fill(TafelFarbe.himmel))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
        if let s = modell.freigabeSatz {
            HStack {
                Text(s).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                if let freigabe { Button("Einstellung öffnen") { freigabe() }.buttonStyle(SnLeiserStil()).font(Schrift.grotesk(13, .medium)) }
            }
        }
        HStack {
            Text("Nichts geht raus, bevor du fragst.")
            Spacer()
            HStack(spacing: 4) { Text("schließen"); taste("esc") }
        }
        .font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise)
    }

    private func taste(_ t: String, _ farbe: Color = TafelFarbe.zweit) -> some View {
        Text(t).font(Schrift.mono(11)).foregroundStyle(farbe).padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
    }

    private func antwort(_ frage: String, _ roh: String, fertig: Bool = true) -> some View {
        let (text, stelle) = HierStelle.teile(roh)
        let (kopf, rest) = Self.teile(text)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                if let foto { HierVorschau(datei: foto, breite: 200, stelle: stelle).animation(Kurve.ease(0.3), value: stelle) }
                VStack(alignment: .leading, spacing: 8) {
                    Text((["SENECA", HeuteTafelLogik.uhr(Date().timeIntervalSince1970 * 1000)] + (foto == nil ? [] : ["\(["bereich": "Bereich", "bildschirm": "Bildschirm"][art] ?? "Fenster") aus \(modell.zusammenhang?.programm ?? "")"])).joined(separator: " · ").uppercased())
                        .font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.leise)
                    Text(frage).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.akzent).lineLimit(2)
                    if !kopf.isEmpty { Text(kopf).font(Schrift.serif(26)).lineHeight(.exact(points: 29)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true) }
                    if !rest.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(SchnellfrageFeld.markdown(rest)).font(Schrift.grotesk(14)).lineSpacing(5).foregroundStyle(TafelFarbe.zweit)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("schnellfrage-antwort")
                        }
                        .frame(maxHeight: 320).defaultScrollAnchor(fertig ? .top : .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if fertig {
                HStack(spacing: 10) {
                    Button(action: imChat) { HStack(spacing: 6) { Text("Im Gespräch weiter"); taste("⌘↩", TafelFarbe.aufHimmel) } }
                        .buttonStyle(SnTafelKnopf(groesse: 13)).keyboardShortcut(.return, modifiers: .command)
                    Button("Neue Frage") { modell.neueFrage() }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                    Button("Kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                    Spacer()
                    if let d = modell.dauer { Text((modell.schritte > 0 ? "▸ \(modell.schritte) \(modell.schritte == 1 ? "Schritt" : "Schritte") · " : "") + String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise) }
                }
            }
        }
        .transition(.opacity)
    }

    static func teile(_ t: String) -> (String, String) {
        let absaetze = t.components(separatedBy: "\n\n")
        if absaetze.count > 1, absaetze[0].count <= 160, !absaetze[0].hasPrefix("#"), !absaetze[0].hasPrefix("-") { return (absaetze[0], absaetze.dropFirst().joined(separator: "\n\n")) }
        return ("", t)
    }
}

struct SnBildschirmBild: View {
    var antwort: Bool
    @StateObject private var modell = SchnellfrageModell(sende: { _ in "Die Lücke ist kein Einbruch. Vier Tage lang kamen keine Daten an.\n\nVom 9. bis 12. Oktober lief der Webhook nicht. Die Webhook-Kette von heute früh kann die vier Tage nachholen, sobald du sie um 16 Uhr abnimmst." })

    var body: some View {
        let foto = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SENECA_G_PROBE"] ?? "") + "/powerbi.png")
        ZStack(alignment: .top) {
            LinearGradient(colors: [TafelFarbe.hex(0x48618A), TafelFarbe.hex(0x1D2A44)], startPoint: .top, endPoint: .bottom)
            Image(nsImage: NSImage(contentsOf: foto) ?? NSImage()).resizable().frame(width: 1240, height: 480).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.top, 56)
            HierKarte(modell: modell).padding(.top, antwort ? 546 : 560)
        }
        .task {
            modell.zusammenhang = HierZusammenhang(art: .browser, programm: "Safari", titel: "Power BI · Anrufe pro Tag · Oktober", dateien: [foto], hatFensterfoto: true)
            modell.text = "Warum ist der Oktober so niedrig?"
            if antwort { modell.ausschnitt = "bereich"; modell.sendeHier = { _, _ in try? await Task.sleep(for: .milliseconds(400)); return "Die Lücke ist kein Einbruch. Vier Tage lang kamen keine Daten an.\n\nVom 9. bis 12. Oktober lief der Webhook nicht. Die Webhook-Kette von heute früh kann die vier Tage nachholen, sobald du sie um 16 Uhr abnimmst.\nStelle: 33 25 10 62" }; Task { try? await Task.sleep(for: .milliseconds(100)); modell.zaehle("liest das Bild"); modell.zaehle("prüft den Webhook") }; await modell.abschicken() }
        }
    }
}
