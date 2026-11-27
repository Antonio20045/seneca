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
