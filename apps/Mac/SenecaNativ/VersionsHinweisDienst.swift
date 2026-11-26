import AppKit
import Foundation
import SwiftUI

struct MacVersionsDateisystem: VersionsDateisystem {
    func liesPlistWert(_ infoPlistPfad: String, schluessel: String) -> String? {
        guard let dict = NSDictionary(contentsOfFile: infoPlistPfad) else { return nil }
        return VersionsHinweis.alsText(dict[schluessel])
    }

    func existiert(_ pfad: String) -> Bool { FileManager.default.fileExists(atPath: pfad) }

    func liesTextdatei(_ pfad: String) -> String? { try? String(contentsOfFile: pfad, encoding: .utf8) }

    func ditto(von: String, nach: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [von, nach]
        let fehler = Pipe()
        p.standardError = fehler
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let text = String(data: fehler.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ditto", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "ditto fehlgeschlagen" : text])
        }
    }

    func entferne(_ pfad: String) throws {
        guard FileManager.default.fileExists(atPath: pfad) else { return }
        try FileManager.default.removeItem(atPath: pfad)
    }

    func erzeugeOrdner(_ pfad: String) throws {
        try FileManager.default.createDirectory(atPath: pfad, withIntermediateDirectories: true)
    }

    func codesignVerifiziere(_ pfad: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", "--deep", "--strict", pfad]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func teamKennung(_ pfad: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", pfad]
        let aus = Pipe(), fehler = Pipe()
        p.standardOutput = aus
        p.standardError = fehler
        do { try p.run() } catch { return nil }
        let text = (String(data: fehler.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            + (String(data: aus.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        for zeile in text.split(separator: "\n") where zeile.hasPrefix("TeamIdentifier=") {
            let wert = zeile.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return (wert.isEmpty || wert == "not set") ? nil : wert
        }
        return nil
    }
}

func starteLosgeloestenNeustartHelfer(eigenePid: Int32, zielPfad: String) {
    let skript = "while kill -0 \(eigenePid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(zielPfad)\""
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", skript]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
}

@MainActor
final class VersionsHinweisModell: ObservableObject {
    @Published var info: VersionsHinweisInfo?
    @Published var fehler: String?
    @Published private(set) var laeuftUpdate = false

    private let fs: VersionsDateisystem = MacVersionsDateisystem()
    private let bereitOrdner: String
    private let bereitApp: String
    private let neuigkeitenPfad: String
    private let zielPfad: String
    private var timer: Timer?

    init(bereitOrdner: String? = nil, zielPfad: String? = nil) {
        let env = ProcessInfo.processInfo.environment
        let vorgabeBereit = ("~/Developer/SenecaMac/Nativ/bereit" as NSString).expandingTildeInPath
        #if DEBUG
        let testBereit = Hintergrund.aktiv ? env["SENECA_TEST_BEREIT_ORDNER"] : nil
        let testZiel = Hintergrund.aktiv ? env["SENECA_TEST_ZIEL_APP"] : nil
        #else
        let testBereit: String? = nil
        let testZiel: String? = nil
        #endif
        let ordner = bereitOrdner ?? testBereit ?? vorgabeBereit
        self.bereitOrdner = ordner
        self.bereitApp = ordner + "/Seneca Nativ.app"
        self.neuigkeitenPfad = ordner + "/NEU.txt"
        self.zielPfad = zielPfad ?? testZiel ?? "/Applications/Seneca Nativ.app"
    }

    private var eigenerStand: VersionsStand {
        let dict = Bundle.main.infoDictionary ?? [:]
        let commit = dict[SenecaBuildSchluessel.commit] as? String ?? ""
        let nummer = VersionsHinweis.alsText(dict[SenecaBuildSchluessel.nummer]).flatMap(Int.init) ?? 0
        return VersionsStand(commit: commit, nummer: nummer)
    }

    func starte() {
        guard MacPfade.profil != .test, !MacPfade.nebenher else { return }
        pruefe()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruefe() }
        }
    }

    func pruefe() {
        let eigener = eigenerStand
        let bereitApp = bereitApp, neuigkeitenPfad = neuigkeitenPfad, fs = fs
        Task.detached { [weak self] in
            let info = VersionsHinweis.pruefeAufNeueVersion(eigenerStand: eigener, bereitAppPfad: bereitApp, neuigkeitenPfad: neuigkeitenPfad, fs: fs)
            if ProcessInfo.processInfo.environment["SENECA_TEST_HINWEIS_LOG"] == "1" {
                let msg = "SENECA_TEST_HINWEIS: eigener=\(eigener) bereitApp=\(bereitApp) info=\(String(describing: info))\n"
                FileHandle.standardError.write(msg.data(using: .utf8)!)
            }
            await MainActor.run { self?.info = info }
        }
    }

    func neuStarten(vorherSpeichern: () -> Void) {
        vorherSpeichern()
        laeuftUpdate = true
        fehler = nil
        let zeitstempel = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sicherungsZiel = ("~/Developer/SenecaMac/Nativ/sicherung/\(zeitstempel)/Seneca Nativ.app" as NSString).expandingTildeInPath
        let bereitApp = bereitApp, zielPfad = zielPfad, fs = fs
        Task.detached { [weak self] in
            let ergebnis = VersionsHinweis.fuehreUpdateAus(bereitAppPfad: bereitApp, zielPfad: zielPfad, sicherungsZiel: sicherungsZiel, fs: fs)
            await MainActor.run {
                guard let self else { return }
                self.laeuftUpdate = false
                switch ergebnis {
                case .erfolg:
                    starteLosgeloestenNeustartHelfer(eigenePid: ProcessInfo.processInfo.processIdentifier, zielPfad: zielPfad)
                    NSApp.terminate(nil)
                case .fehler(let text):
                    self.fehler = text
                }
            }
        }
    }
}

struct VersionsHinweisBand: View {
    @ObservedObject var hinweis: VersionsHinweisModell
    var neuStarten: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let fehler = hinweis.fehler {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Farbe.koralle)
                    Text(fehler).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink1)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Farbe.papier2, in: Capsule())
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .shadow(color: Farbe.hinweisSchatten, radius: 16, y: 6)
                .accessibilityIdentifier("versions-hinweis-fehler")
            } else if let info = hinweis.info {
                VStack(spacing: 2) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Farbe.himmel)
                        Text("Neue Version bereit").font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink1)
                        Button {
                            neuStarten()
                        } label: {
                            Text(hinweis.laeuftUpdate ? "Startet neu …" : "Neu starten")
                                .font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.himmel)
                        }
                        .buttonStyle(.plain)
                        .disabled(hinweis.laeuftUpdate)
                        .accessibilityIdentifier("versions-hinweis-neustart")
                    }
                    if !info.neuigkeiten.isEmpty {
                        Text(info.neuigkeiten.split(separator: "\n").first.map(String.init) ?? info.neuigkeiten)
                            .font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Farbe.papier2, in: Capsule())
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .shadow(color: Farbe.hinweisSchatten, radius: 16, y: 6)
                .accessibilityIdentifier("versions-hinweis-band")
            }
        }
        .animation(Kurve.feder(0.35), value: hinweis.info)
        .animation(Kurve.feder(0.35), value: hinweis.fehler)
    }
}
