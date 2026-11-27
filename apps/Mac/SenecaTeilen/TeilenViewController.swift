import AppKit
import SwiftUI

final class TeilenViewController: NSViewController {
    private let modell = TeilenModell()

    override func loadView() {
        let blatt = TeilenBlatt(modell: modell, senden: { [weak self] in self?.senden() }, abbrechen: { [weak self] in
            self?.modell.verwerfen()
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        let host = NSHostingView(rootView: blatt.environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 390, height: 540)
        view = host
        preferredContentSize = host.frame.size
        Task {
            modell.eintrag = await TeilenEingang.laden(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            modell.geladen = true
        }
    }

    private func senden() {
        guard modell.fertig() != nil else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "de.antonio.seneca.nativ").isEmpty,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "de.antonio.seneca.nativ") {
            let wie = NSWorkspace.OpenConfiguration()
            wie.activates = false
            NSWorkspace.shared.openApplication(at: app, configuration: wie)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
