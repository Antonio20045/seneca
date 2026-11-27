import SwiftUI
import QuickLook

@MainActor
enum DateiOeffner {
    static func oeffnen(pfad roh: String, partner: ChatPartner, store: SenecaStore, lesen: (ReadingDocument) -> Void) async -> String? {
        Haptik.tipp()
        let pfad = DateiLogik.bereinige(roh)
        guard !pfad.isEmpty else { return fehler("Ungültiger Pfad.") }

        let json: [String: Any]
        if store.demo {
            guard let demo = DateiLogik.demoAntwort(pfad: pfad) else { return fehler("Die Datei gibt es nicht (mehr).") }
            json = demo
        } else {
            do {
                json = try await store.rufe("seneca.stand", params: ["geraet": "iphone", "sicht": "datei", "pfad": pfad], timeout: 45)
            } catch {
                return fehler(error.localizedDescription)
            }
        }
        guard let antwort = DateiLogik.antwort(aus: json) else { return fehler("Die Datei ist nicht lesbar.") }

        switch DateiLogik.ziel(fuer: antwort) {
        case .lesen(let titel, let text, let format):
            lesen(ReadingDocument(id: "datei-\(antwort.pfad)", kicker: "Datei · \(partner.kopfName)", title: titel, body: text,
                                  format: format == .markdown ? .markdown : .text))
            return nil
        case .quickLook(let name, let daten):
            guard let url = QuickLookZeiger.gemeinsam.schreibe(daten, name: name), QuickLookZeiger.gemeinsam.zeige(url) else {
                return fehler("Datei nicht lesbar", schonKurz: true)
            }
            return nil
        case .hinweis(let satz):
            return fehler(satz, schonKurz: true)
        }
    }

    private static func fehler(_ meldung: String, schonKurz: Bool = false) -> String {
        let satz = schonKurz ? meldung : DateiLogik.fehlertext(meldung)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: satz)
        return satz
    }
}

@MainActor
final class QuickLookZeiger: NSObject, QLPreviewControllerDataSource, @preconcurrency QLPreviewControllerDelegate {
    static let gemeinsam = QuickLookZeiger()

    private var datei: URL?
    private let wurzel = FileManager.default.temporaryDirectory.appendingPathComponent("seneca-dateien", isDirectory: true)

    func schreibe(_ daten: Data, name: String) -> URL? {
        let fm = FileManager.default
        try? fm.removeItem(at: wurzel)
        let ordner = wurzel.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: ordner, withIntermediateDirectories: true)
            let url = ordner.appendingPathComponent(name)
            try daten.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func zeige(_ url: URL) -> Bool {
        guard let oben = Self.obersterController() else { return false }
        datei = url
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        oben.present(ql, animated: true)
        return true
    }

    private static func obersterController() -> UIViewController? {
        let fenster = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        var vc = fenster?.rootViewController
        while let naechster = vc?.presentedViewController { vc = naechster }
        return vc
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { datei == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (datei ?? wurzel) as NSURL
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        datei = nil
        try? FileManager.default.removeItem(at: wurzel)
    }
}
