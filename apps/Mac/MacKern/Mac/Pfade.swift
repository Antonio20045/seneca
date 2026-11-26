import Foundation

enum MacPfade {
    enum Profil: String {
        case echt, demo, test, probe
        var endung: String { self == .echt ? "" : "." + rawValue }
        var ordnerEndung: String { self == .echt ? "" : " " + rawValue.capitalized }
        var echteDaten: Bool { self == .echt || self == .probe }
    }

    static var nebenher: Bool { profil == .probe }

    static let profil: Profil = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil { return .test }
        if let d = env["SENECA_DEMO"], !d.isEmpty, d != "0" { return .demo }
        if Bundle.main.bundleIdentifier?.hasSuffix(".probe") == true { return .probe }
        return .echt
    }()

    static var dienst: String { "de.antonio.seneca.nativ.gateway" + profil.endung }

    static let pruefinstanz: Bool = {
        let env = ProcessInfo.processInfo.environment
        return SchluesselbundSchutz.gesperrt(hintergrund: env["SENECA_HINTERGRUND"], daten: env["SENECA_DATEN"],
                                             profilTest: profil == .test)
    }()

    static var ersatzSchluesselbundDatei: URL? {
        guard let t = ProcessInfo.processInfo.environment["SENECA_DATEN"], !t.isEmpty else { return nil }
        let basis = URL(fileURLWithPath: t, isDirectory: true)
        try? FileManager.default.createDirectory(at: basis, withIntermediateDirectories: true)
        return basis.appendingPathComponent("schluesselbund-ersatz.json")
    }

    static var adresseSchluessel: String { "seneca-nativ.adresse" + profil.endung }

    static var datenOrdner: URL? {
        let basis: URL?
        if let t = ProcessInfo.processInfo.environment["SENECA_DATEN"], !t.isEmpty {
            basis = URL(fileURLWithPath: t, isDirectory: true)
        } else {
            basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Seneca Nativ" + profil.ordnerEndung, isDirectory: true)
        }
        guard let basis else { return nil }
        try? FileManager.default.createDirectory(at: basis, withIntermediateDirectories: true)
        return basis
    }

    static var echterBasisOrdner: URL? {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Seneca Nativ", isDirectory: true)
        guard let basis else { return nil }
        try? FileManager.default.createDirectory(at: basis, withIntermediateDirectories: true)
        return basis
    }

    static var instanzSperrdatei: URL? { echterBasisOrdner?.appendingPathComponent("app.lock") }
}
