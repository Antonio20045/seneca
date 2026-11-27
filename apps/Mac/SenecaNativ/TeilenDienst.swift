import Foundation
import Combine

@MainActor
final class TeilenDienst {
    private weak var modell: AppModell?
    private var quelle: DispatchSourceFileSystemObject?
    private var abo: AnyCancellable?
    private var laeuft = false
    private var nochmal = false

    func starte(modell: AppModell) {
        guard MacPfade.profil == .echt, !MacPfade.nebenher, let ordner = TeilenEingang.ordner,
              (try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)) != nil else { return }
        self.modell = modell
        let fd = open(ordner.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let q = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        q.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.verarbeite() } }
        q.setCancelHandler { close(fd) }
        q.resume()
        quelle = q
        abo = modell.$zustand.filter { $0 == .bereit }.sink { [weak self] _ in self?.verarbeite() }
    }

    func verarbeite() {
        guard !laeuft else { nochmal = true; return }
        laeuft = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await abarbeiten()
            laeuft = false
            if nochmal { nochmal = false; verarbeite() }
        }
    }

    private func abarbeiten() async {
        guard let modell, modell.zustand == .bereit else { return }
        for e in TeilenEingang.alle() {
            let gelesen = await TeilenEingang.lesen(e)
            if e.nurMerken { merken(e, gelesen, modell) } else if modell.store.isConnected { fragen(e, gelesen, modell) }
        }
    }

    private func merken(_ e: TeilenEintrag, _ gelesen: String?, _ modell: AppModell) {
        let z = TeilenEingang.merkzettel(e, gelesen: gelesen)
        let wert: [String: Any] = ["zeit": ISO8601DateFormatter().string(from: e.zeit), "quelle": "mac-teilen", "art": z.art, "titel": z.titel,
                                   "detail": z.detail, "schluessel": "teilen:\(e.id)"]
        guard let json = (try? JSONSerialization.data(withJSONObject: wert)).flatMap({ try? JSONDecoder().decode([String: JSONWert].self, from: $0) }) else { return }
        modell.store.handle("eingang.datei", ziel: "teilen:\(e.id)", wert: json)
        TeilenEingang.entfernen(e)
    }

    private func fragen(_ e: TeilenEintrag, _ gelesen: String?, _ modell: AppModell) {
        let anhaenge = TeilenEingang.bilder(e).compactMap { u in
            (try? Data(contentsOf: u)).flatMap { ChatAnhang.ausDaten($0, name: u.lastPathComponent, mime: ChatAnhang.mimeTyp(u.pathExtension)) }
        }
        let id = e.an.flatMap { an in modell.store.stand?.team?.first { $0.name == an }?.id } ?? Hauptagent.id
        modell.oeffneChat(key: "agent:\(id):main", agentId: id)
        modell.zeigeFenster(nil, gespraech: true)
        let text = TeilenEingang.nachricht(e, gelesen: gelesen), partner = modell.gegenueber.partner
        TeilenEingang.entfernen(e)
        Task { _ = try? await modell.chat.send(text, an: partner, anhaenge: anhaenge) }
    }
}
