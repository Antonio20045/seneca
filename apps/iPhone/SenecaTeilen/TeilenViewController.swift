import UIKit
import SwiftUI

final class TeilenViewController: UIViewController {
    private let modell = TeilenModell()

    override func viewDidLoad() {
        super.viewDidLoad()
        let blatt = TeilenBlatt(modell: modell, senden: { [weak self] in self?.senden() }, abbrechen: { [weak self] in
            self?.modell.verwerfen()
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        let host = UIHostingController(rootView: blatt)
        host.overrideUserInterfaceStyle = .dark
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task {
            modell.eintrag = await TeilenEingang.laden(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            modell.geladen = true
        }
    }

    private func senden() {
        guard let e = modell.fertig() else { return }
        if !e.nurMerken { oeffneSeneca() }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func oeffneSeneca() {
        guard let url = URL(string: "seneca://eingang") else { return }
        var naechster: UIResponder? = self
        while let r = naechster {
            if let app = r as? UIApplication { app.open(url, options: [:], completionHandler: nil); return }
            naechster = r.next
        }
    }
}
