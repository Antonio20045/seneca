import Foundation

enum Kindprozess {
    private static var umgebung: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return env
    }

    static func laufe(_ datei: URL, _ argumente: [String] = [], limit: TimeInterval, ausgabe: Bool = true) async -> Data? {
        guard FileManager.default.fileExists(atPath: datei.path) else { return nil }
        return await withCheckedContinuation { (weiter: CheckedContinuation<Data?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                if datei.pathExtension == "py" {
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    p.arguments = ["python3", datei.path] + argumente
                } else if FileManager.default.isExecutableFile(atPath: datei.path) {
                    p.executableURL = datei
                    p.arguments = argumente
                } else {
                    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    p.arguments = [datei.path] + argumente
                }
                p.currentDirectoryURL = datei.deletingLastPathComponent()
                p.environment = umgebung
                p.standardInput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                let rohr = ausgabe ? Pipe() : nil
                p.standardOutput = rohr ?? FileHandle.nullDevice
                do { try p.run() } catch { weiter.resume(returning: nil); return }
                let abgelaufen = DispatchWorkItem {
                    guard p.isRunning else { return }
                    p.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: abgelaufen)
                let daten = rohr?.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let rechtzeitig = p.terminationReason == .exit && p.terminationStatus == 0
                abgelaufen.cancel()
                weiter.resume(returning: rechtzeitig ? (daten ?? Data()) : nil)
            }
        }
    }
}

@MainActor
final class TageslaufHaken {
    static let gemeinsam = TageslaufHaken()
    static let ordner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Bereiche/openclaw/tageslauf", isDirectory: true)
    static var skript: URL { ordner.appendingPathComponent("sammeln.sh") }

    private var laeuft = false
    private var takt: Takt?

    static var erlaubt: Bool { MacPfade.profil == .echt && !Hintergrund.aktiv && !MacPfade.pruefinstanz }

    func starte() {
        guard Self.erlaubt, takt == nil else { return }
        takt = Takt(sekunden: 300) { [weak self] in await self?.sammle() }
    }

    private static func vermerke(start: Date, gelungen: Bool) {
        guard let ordner = MacPfade.datenOrdner else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let zeile = "\(f.string(from: start)) dauer=\(String(format: "%.1f", Date().timeIntervalSince(start)))s \(gelungen ? "ok" : "fehler-oder-zeitlimit")\n"
        let url = ordner.appendingPathComponent("takt.log")
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(zeile.utf8)) } else { try? Data(zeile.utf8).write(to: url) }
    }

    private func sammle() async {
        guard !laeuft else { return }
        laeuft = true
        defer { laeuft = false }
        let start = Date()
        let ergebnis = await Kindprozess.laufe(Self.skript, limit: 210, ausgabe: false)
        Self.vermerke(start: start, gelungen: ergebnis != nil)
    }
}

@MainActor
final class Takt {
    private let quelle: DispatchSourceTimer
    private let aktivitaet: NSObjectProtocol

    init(sekunden: Int, sofort: Bool = true, verzoegerung: Double = 0, tu: @escaping @MainActor () async -> Void) {
        aktivitaet = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Seneca sammelt den Tag im festen Takt")
        quelle = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.global(qos: .utility))
        quelle.schedule(wallDeadline: .now() + (sofort ? verzoegerung : Double(sekunden)), repeating: .seconds(sekunden), leeway: .seconds(1))
        quelle.setEventHandler { Task { @MainActor in await tu() } }
        quelle.resume()
    }

    deinit {
        quelle.cancel()
        ProcessInfo.processInfo.endActivity(aktivitaet)
    }
}
