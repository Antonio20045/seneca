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

final class TeilenModell: ObservableObject {
    @Published var eintrag: TeilenEintrag?
    @Published var geladen = false
    @Published var frage = ""
    @Published var hinweis: String?
}

struct TeilenBlatt: View {
    @ObservedObject var modell: TeilenModell
    var senden: () -> Void
    var abbrechen: () -> Void
    @FocusState private var schreibt: Bool

    private static func serif(_ g: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: g) }
    private static func grotesk(_ g: CGFloat) -> Font { .custom("SpaceGrotesk-Regular", size: g) }
    private static let grund = Color(red: 0x0A / 255, green: 0x22 / 255, blue: 0x45 / 255)
    private static let grundUnten = Color(red: 0x06 / 255, green: 0x16 / 255, blue: 0x32 / 255)

    private var ohneFrage: Bool { modell.frage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("An Seneca").font(Self.grotesk(13)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button("Abbrechen", action: abbrechen)
                    .font(Self.grotesk(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 44)
            }
            if let e = modell.eintrag {
                Text(TeilenEingang.kurz(e))
                    .font(Self.serif(28))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .padding(.top, 10)
                if let a = e.adresse, let ort = TeilenEingang.ort(a), !e.titel.isEmpty {
                    Text(ort).font(Self.grotesk(15)).foregroundStyle(.white.opacity(0.65)).padding(.top, 8)
                }
            } else if modell.geladen {
                Text("Hier ist nichts, das ich lesen kann.").font(Self.serif(28)).foregroundStyle(.white).padding(.top, 10)
            }
            TextField("", text: $modell.frage, prompt: Text("Was möchtest du dazu wissen?").foregroundColor(.white.opacity(0.45)))
                .font(Self.grotesk(19))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($schreibt)
                .submitLabel(.send)
                .onSubmit(senden)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.3)).frame(height: 1) }
                .padding(.top, 26)
                .accessibilityLabel("Deine Frage dazu")
            if let h = modell.hinweis {
                Text(h).font(Self.grotesk(15)).foregroundStyle(.white.opacity(0.85)).padding(.top, 12)
            }
            Button(action: senden) {
                Text(ohneFrage ? "Merk dir das" : "Seneca fragen")
                    .font(Self.grotesk(17))
                    .foregroundStyle(Self.grund)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 46)
                    .background(Capsule().fill(.white.opacity(0.94)))
            }
            .buttonStyle(.plain)
            .disabled(modell.eintrag == nil)
            .opacity(modell.eintrag == nil ? 0.4 : 1)
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Self.grund, Self.grundUnten], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear { schreibt = true }
    }
}
