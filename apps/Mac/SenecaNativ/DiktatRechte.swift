import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

@MainActor
final class DiktatRechte: ObservableObject {
    static let gemeinsam = DiktatRechte()

    enum Art { case bedienung, eingabe, mikrofon }

    @Published private(set) var bedienung = false
    @Published private(set) var eingabe = false
    @Published private(set) var mikrofon: AVAuthorizationStatus = .notDetermined

    var tasteErkennbar: Bool { eingabe || bedienung }
    var mikrofonErteilt: Bool { mikrofon == .authorized }
    var vollstaendig: Bool { tasteErkennbar && bedienung && mikrofonErteilt }

    private static var gefragtSchluessel: String { "seneca-nativ.diktat-rechte-gefragt" + MacPfade.profil.endung }

    private init() { aktualisiere() }

    func aktualisiere() {
        let b = AXIsProcessTrusted()
        let e = CGPreflightListenEventAccess()
        let m = AVCaptureDevice.authorizationStatus(for: .audio)
        if b != bedienung { bedienung = b }
        if e != eingabe { eingabe = e }
        if m != mikrofon { mikrofon = m }
    }

    func frageErstmals() async {
        aktualisiere()
        guard MacPfade.profil == .echt, !Hintergrund.an, !vollstaendig else { return }
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.gefragtSchluessel) else { return }
        d.set(true, forKey: Self.gefragtSchluessel)

        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Spracheingabe freigeben"
        a.informativeText = """
        Mit einem Tippen auf die rechte ⌘-Taste startet und beendet Seneca eine Aufnahme – auch in anderen Apps. Dafür braucht der Mac drei Freigaben:

        • Mikrofon: zum Aufnehmen.
        • Eingabeüberwachung: damit Seneca das Tippen der rechten ⌘ bemerkt. Gelesen wird nur das; nichts wird gespeichert.
        • Bedienungshilfen: um den erkannten Text an die Cursorstelle der anderen App zu setzen.

        Erkannt wird auf diesem Mac, nichts geht ins Netz.
        """
        a.addButton(withTitle: "Freigaben anfragen")
        a.addButton(withTitle: "Später")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        await frageAlle()
    }

    func frageAlle() async {
        if mikrofon == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        aktualisiere()
    }

    func frage(_ art: Art) async {
        switch art {
        case .mikrofon:
            if mikrofon == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) } else { oeffne(art) }
        case .eingabe:
            if !CGRequestListenEventAccess() { oeffne(art) }
        case .bedienung:
            if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) { oeffne(art) }
        }
        aktualisiere()
    }

    func oeffne(_ art: Art) {
        let bereich: String
        switch art {
        case .bedienung: bereich = "Privacy_Accessibility"
        case .eingabe: bereich = "Privacy_ListenEvent"
        case .mikrofon: bereich = "Privacy_Microphone"
        }
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(bereich)") { NSWorkspace.shared.open(u) }
    }
}
