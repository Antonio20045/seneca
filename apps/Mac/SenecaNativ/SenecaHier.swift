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

    private static func ax(_ pid: pid_t) -> (markiert: String, titel: String) {
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

    private static func fensterfoto(_ pid: pid_t) async -> URL? {
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
        if z.text.isEmpty, z.dateien.isEmpty, z.markiert.isEmpty {
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
    @State private var bild: NSImage?

    var body: some View {
        ZStack {
            if let bild {
                Image(nsImage: bild).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Farbe.linie, lineWidth: 1))
            }
        }
        .frame(height: 96, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: datei) { bild = NSImage(contentsOf: datei) }
        .accessibilityLabel("Foto deines Bildschirms")
        .accessibilityIdentifier("hier-vorschau")
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

private struct HierHoehe: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct HierKarte: View {
    @ObservedObject var modell: SchnellfrageModell
    var schliesse: () -> Void = {}
    var imChat: () -> Void = {}
    var freigabe: (() -> Void)?
    @FocusState private var fokus: Bool
    @State private var textHoehe: CGFloat = 0

    private static let einzug: CGFloat = 36
    private static let hoechstens: CGFloat = 380

    private var sicht: String {
        if let z = modell.zusammenhang { return z.sichtSatz }
        return modell.liest ? "Seneca schaut, was du vor dir hast." : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                SnKugel(groesse: 22, atmet: modell.beschaeftigt)
                TextField("", text: $modell.text, prompt: Text(modell.zusammenhang?.hatBildschirmfoto == true ? "Was soll ich damit tun?" : modell.zusammenhang?.istLeer == false ? "Frag Seneca dazu" : "Frag Seneca etwas").foregroundColor(Farbe.ink4))
                    .textFieldStyle(.plain).font(Schrift.serif(25)).foregroundStyle(Color.white)
                    .focused($fokus)
                    .disabled(modell.beschaeftigt)
                    .onSubmit { Task { await modell.abschicken() } }
                    .onExitCommand { schliesse() }
                    .accessibilityIdentifier("schnellfrage-feld")
            }
            if let z = modell.zusammenhang, z.hatBildschirmfoto, let foto = z.dateien.first {
                HierVorschau(datei: foto)
                    .padding(.leading, Self.einzug).padding(.top, 12)
            }
            if !sicht.isEmpty {
                Text(sicht).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(Farbe.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.einzug).padding(.top, 7)
                    .transition(.opacity)
            }
            if let s = modell.freigabeSatz, modell.phase == .eingabe {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
                    if let freigabe {
                        Button("Einstellung öffnen") { freigabe() }.buttonStyle(SnLeiserStil()).font(Schrift.grotesk(13, .medium)).padding(.vertical, 3)
                    }
                }
                .padding(.leading, Self.einzug).padding(.top, 8)
                .transition(.opacity)
            }
            antwort
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 18)
        .frame(width: 660, alignment: .leading)
        .background(Farbe.kasten, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Farbe.linie, lineWidth: 1))
        .shadow(color: Farbe.kastenSchatten, radius: 24, y: 14)
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        .animation(Kurve.ease(0.22), value: modell.phase)
        .animation(Kurve.ease(0.22), value: sicht)
        .onAppear { fokus = true }
        .onChange(of: modell.phase) { _, _ in if !modell.beschaeftigt { fokus = true } }
    }

    @ViewBuilder private var antwort: some View {
        switch modell.phase {
        case .eingabe: EmptyView()
        case .wartet(let frage): teil(frage: frage, text: modell.strom, fertig: false, lauf: modell.laufZeile)
        case .antwort(let frage, let text): teil(frage: frage, text: text.isEmpty ? "Seneca hat nichts zurückgegeben." : text, fertig: true)
        case .fehler(let t):
            Text(t).font(Schrift.grotesk(14)).foregroundStyle(Farbe.koralle).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.einzug).padding(.top, 14)
        }
    }

    private func teil(frage: String, text: String, fertig: Bool, lauf: String = "") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Farbe.linie2).frame(height: 1).padding(.top, 16)
            Text(frage).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(Farbe.ink3).lineLimit(2)
                .padding(.top, 14)
            if text.isEmpty {
                Text(lauf.isEmpty ? "Deine Frage geht an Seneca." : lauf).font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink2).padding(.top, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(SchnellfrageFeld.markdown(text))
                        .font(Schrift.grotesk(15)).lineSpacing(5).foregroundStyle(Farbe.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        .background(GeometryReader { g in Color.clear.preference(key: HierHoehe.self, value: g.size.height) })
                        .accessibilityIdentifier("schnellfrage-antwort")
                }
                .defaultScrollAnchor(fertig ? .top : .bottom)
                .frame(height: min(max(textHoehe, 22), Self.hoechstens))
                .onPreferenceChange(HierHoehe.self) { textHoehe = $0 }
                .padding(.top, 8)
            }
            if fertig {
                Button("Im Chat weiterführen") { imChat() }.buttonStyle(SnLeiserStil()).font(Schrift.grotesk(14, .medium))
                    .padding(.top, 12)
            }
        }
        .padding(.leading, Self.einzug)
        .transition(.opacity)
    }
}
