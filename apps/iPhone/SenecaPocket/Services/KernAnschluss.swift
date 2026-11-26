import Foundation

enum MacPfade {
    static let demo: Bool = {
        let d = ProcessInfo.processInfo.environment["SENECA_DEMO"] ?? ""
        return !d.isEmpty && d != "0"
    }()

    enum Profil {
        case echt, demo
        var echteDaten: Bool { self == .echt }
    }
    static var profil: Profil { demo ? .demo : .echt }

    static let dienst = "de.seneca.pocket.gateway"
    static let pruefinstanz = false
    static let ersatzSchluesselbundDatei: URL? = nil

    static var datenOrdner: URL? {
        guard let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(demo ? "Chat Demo" : "Chat", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: basis, withIntermediateDirectories: true)
        return basis
    }
}

extension SenecaStore {
    static weak var aktuell: SenecaStore?
}
