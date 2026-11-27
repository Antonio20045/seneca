import Foundation

@MainActor
final class MacEinstellungen: ObservableObject {
    private let d: UserDefaults
    private nonisolated static func sch(_ n: String) -> String { "seneca-nativ.\(n)" + MacPfade.profil.endung }

    @Published var mitteilungenAn: Bool { didSet { d.set(mitteilungenAn, forKey: Self.sch("mitteilungen")) } }
    @Published var artEntscheidung: Bool { didSet { d.set(artEntscheidung, forKey: Self.sch("mitteilung-entscheidung")) } }
    @Published var artStoerung: Bool { didSet { d.set(artStoerung, forKey: Self.sch("mitteilung-stoerung")) } }
    @Published var aufgabenMelden: Bool { didSet { d.set(aufgabenMelden, forKey: Self.sch("mitteilung-aufgaben")) } }
    @Published var dockZahl: Bool { didSet { d.set(dockZahl, forKey: Self.sch("dock-zahl")) } }
    @Published var kuerzel: Kuerzel? { didSet { d.set(kuerzel?.data() ?? Data(), forKey: Self.sch("kuerzel")) } }
    @Published var mikrofonQuelle: MikrofonQuelle { didSet { d.set(mikrofonQuelle.gespeichertesWort, forKey: Self.sch("mikrofon-quelle")) } }

    init(_ d: UserDefaults = .standard) {
        self.d = d
        func b(_ n: String, _ v: Bool) -> Bool { d.object(forKey: Self.sch(n)) as? Bool ?? v }
        mitteilungenAn = b("mitteilungen", false)
        artEntscheidung = b("mitteilung-entscheidung", true)
        artStoerung = b("mitteilung-stoerung", true)
        aufgabenMelden = b("mitteilung-aufgaben", true)
        dockZahl = b("dock-zahl", true)
        if let roh = d.object(forKey: Self.sch("kuerzel")) as? Data { kuerzel = roh.isEmpty ? nil : Kuerzel.aus(data: roh) ?? .standard } else { kuerzel = .standard }
        mikrofonQuelle = MikrofonQuelle.ausGespeichertemWort(d.string(forKey: Self.sch("mikrofon-quelle")))
    }

    nonisolated static var mikrofonQuelleGespeichert: MikrofonQuelle {
        MikrofonQuelle.ausGespeichertemWort(UserDefaults.standard.string(forKey: sch("mikrofon-quelle")))
    }

    func meldet(_ art: Mitteilung.Art) -> Bool {
        guard mitteilungenAn else { return false }
        switch art {
        case .entscheidung: return artEntscheidung
        case .stoerung: return artStoerung
        }
    }
}
