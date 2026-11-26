import Foundation

public enum SenecaBuildSchluessel {
    public static let commit = "SenecaBuildCommit"
    public static let nummer = "SenecaBuildNummer"
}

public struct VersionsStand: Equatable, Sendable {
    public var commit: String
    public var nummer: Int
    public init(commit: String, nummer: Int) {
        self.commit = commit
        self.nummer = nummer
    }
}

public struct VersionsHinweisInfo: Equatable, Sendable {
    public var stand: VersionsStand
    public var neuigkeiten: String
    public init(stand: VersionsStand, neuigkeiten: String) {
        self.stand = stand
        self.neuigkeiten = neuigkeiten
    }
}

public enum VersionsUpdateErgebnis: Equatable, Sendable {
    case erfolg
    case fehler(String)
}

public protocol VersionsDateisystem {
    func liesPlistWert(_ infoPlistPfad: String, schluessel: String) -> String?
    func existiert(_ pfad: String) -> Bool
    func liesTextdatei(_ pfad: String) -> String?
    func ditto(von: String, nach: String) throws
    func entferne(_ pfad: String) throws
    func erzeugeOrdner(_ pfad: String) throws
    func codesignVerifiziere(_ pfad: String) -> Bool
    func teamKennung(_ pfad: String) -> String?
}

public enum VersionsHinweis {
    public static func alsText(_ wert: Any?) -> String? {
        if let text = wert as? String { return text }
        if let zahl = wert as? NSNumber { return zahl.stringValue }
        return nil
    }

    public static func liesStand(infoPlistPfad: String, fs: VersionsDateisystem) -> VersionsStand? {
        guard let commit = fs.liesPlistWert(infoPlistPfad, schluessel: SenecaBuildSchluessel.commit), !commit.isEmpty else { return nil }
        let nummer = fs.liesPlistWert(infoPlistPfad, schluessel: SenecaBuildSchluessel.nummer).flatMap(Int.init) ?? 0
        return VersionsStand(commit: commit, nummer: nummer)
    }

    public static func pruefeAufNeueVersion(
        eigenerStand: VersionsStand,
        bereitAppPfad: String,
        neuigkeitenPfad: String,
        fs: VersionsDateisystem
    ) -> VersionsHinweisInfo? {
        guard fs.existiert(bereitAppPfad) else { return nil }
        let infoPlist = bereitAppPfad + "/Contents/Info.plist"
        guard let bereitStand = liesStand(infoPlistPfad: infoPlist, fs: fs) else { return nil }
        guard bereitStand.nummer > eigenerStand.nummer, bereitStand.commit != eigenerStand.commit else { return nil }
        let neuigkeiten = fs.liesTextdatei(neuigkeitenPfad) ?? ""
        return VersionsHinweisInfo(stand: bereitStand, neuigkeiten: neuigkeiten)
    }

    public static func fuehreUpdateAus(
        bereitAppPfad: String,
        zielPfad: String,
        sicherungsZiel: String,
        fs: VersionsDateisystem
    ) -> VersionsUpdateErgebnis {
        guard fs.existiert(bereitAppPfad) else {
            return .fehler("Die bereitgelegte Version wurde nicht gefunden (\(bereitAppPfad)).")
        }
        let gabAlteVersion = fs.existiert(zielPfad)
        let altesTeam = gabAlteVersion ? fs.teamKennung(zielPfad) : nil
        if gabAlteVersion {
            do {
                try fs.erzeugeOrdner((sicherungsZiel as NSString).deletingLastPathComponent)
                try fs.ditto(von: zielPfad, nach: sicherungsZiel)
            } catch {
                return .fehler("Sicherung der bisherigen Version ist fehlgeschlagen: \(error.localizedDescription)")
            }
        }
        do {
            if gabAlteVersion { try fs.entferne(zielPfad) }
            try fs.ditto(von: bereitAppPfad, nach: zielPfad)
        } catch {
            return .fehler("Kopieren der neuen Version ist fehlgeschlagen: \(error.localizedDescription)")
        }
        func spieleZurueck(_ meldung: String) -> VersionsUpdateErgebnis {
            if gabAlteVersion {
                try? fs.entferne(zielPfad)
                try? fs.ditto(von: sicherungsZiel, nach: zielPfad)
            } else {
                try? fs.entferne(zielPfad)
            }
            return .fehler(meldung)
        }
        guard fs.codesignVerifiziere(zielPfad) else {
            return spieleZurueck("Die Signaturprüfung der neuen Version ist fehlgeschlagen – die bisherige Version bleibt installiert.")
        }
        if let altesTeam, !altesTeam.isEmpty {
            let neuesTeam = fs.teamKennung(zielPfad)
            guard let neuesTeam, neuesTeam == altesTeam else {
                let gefunden = (neuesTeam?.isEmpty == false) ? "Team \(neuesTeam!)" : "keine Team-Kennung (ad-hoc signiert)"
                return spieleZurueck("""
                    Die neue Version ist mit einer anderen Identität signiert als die bisherige \
                    (bisher Team \(altesTeam), neu \(gefunden)). Sie bleibt draußen, denn sonst fragt macOS \
                    bei jedem Zugriff auf den Schlüsselbund nach. Die bisherige Version bleibt installiert.
                    """)
            }
        }
        return .erfolg
    }
}
