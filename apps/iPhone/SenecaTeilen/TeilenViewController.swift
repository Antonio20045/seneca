import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class TeilenViewController: UIViewController {
    private let modell = TeilenModell()

    override func viewDidLoad() {
        super.viewDidLoad()
        let blatt = TeilenBlatt(modell: modell, senden: { [weak self] in self?.senden() }, abbrechen: { [weak self] in
            self?.aufraeumen()
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        let host = UIHostingController(rootView: blatt)
        host.overrideUserInterfaceStyle = .dark
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await laden() }
    }

    private func laden() async {
        var e = TeilenEintrag(id: UUID().uuidString, zeit: Date())
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            if e.titel.isEmpty, let t = item.attributedTitle?.string ?? item.attributedContentText?.string { e.titel = String(t.prefix(200)) }
            for anhang in item.attachments ?? [] {
                if anhang.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let name = await kopiere(anhang, UTType.image, endung: "jpg") { e.dateien.append(name); e.bilder += 1 }
                } else if anhang.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let name = await kopiere(anhang, UTType.item, endung: "dat") { e.dateien.append(name) }
                } else if anhang.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await anhang.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { e.adresse = url.absoluteString }
                } else if anhang.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await anhang.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { e.text = [e.text, text].compactMap { $0 }.joined(separator: "\n") }
                } else if anhang.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    if let name = await kopiere(anhang, UTType.data, endung: "dat") { e.dateien.append(name) }
                }
            }
        }
        if let t = e.text, t == e.titel { e.titel = "" }
        modell.eintrag = e
        modell.geladen = true
    }

    private func kopiere(_ anhang: NSItemProvider, _ typ: UTType, endung: String) async -> String? {
        guard let ordner = TeilenEingang.ordner else { return nil }
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return await withCheckedContinuation { weiter in
            anhang.loadFileRepresentation(forTypeIdentifier: typ.identifier) { url, _ in
                guard let url else {
                    anhang.loadObject(ofClass: UIImage.self) { bild, _ in
                        let name = "datei-\(UUID().uuidString).jpg"
                        guard let daten = (bild as? UIImage)?.jpegData(compressionQuality: 0.85), (try? daten.write(to: ordner.appendingPathComponent(name))) != nil else { weiter.resume(returning: nil); return }
                        weiter.resume(returning: name)
                    }
                    return
                }
                let name = "datei-\(UUID().uuidString)." + (url.pathExtension.isEmpty ? endung : url.pathExtension)
                let ok = (try? FileManager.default.copyItem(at: url, to: ordner.appendingPathComponent(name))) != nil
                weiter.resume(returning: ok ? name : nil)
            }
        }
    }

    private func senden() {
        guard var e = modell.eintrag else { return }
        e.frage = modell.frage.trimmingCharacters(in: .whitespacesAndNewlines)
        e.an = modell.an
        e.ablegen = modell.ablegen
        e.zeit = Date()
        do { try TeilenEingang.ablegen(e) } catch {
            modell.hinweis = "Das ließ sich nicht ablegen. Öffne Seneca einmal und versuche es noch einmal."
            return
        }
        if !e.nurMerken { oeffneSeneca() }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func aufraeumen() {
        if let e = modell.eintrag { TeilenEingang.entfernen(e) }
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
