import Foundation
import AppKit
import os

enum Leistungsmessung {
    private static let env = ProcessInfo.processInfo.environment
    static var aktiv: Bool { Hintergrund.aktiv && pfad != nil }
    static var pfad: String? { env["SENECA_TEST_MESSUNG"].flatMap { $0.isEmpty ? nil : $0 } }
    static var endeSekunden: Double? { env["SENECA_TEST_ENDE"].flatMap(Double.init) }

    static let log = OSLog(subsystem: "de.antonio.seneca.nativ", category: "leistung")

    private static let sperre = NSLock()
    nonisolated(unsafe) private static var wache = HauptfadenWache()
    nonisolated(unsafe) private static var abschnitt = "start"
    nonisolated(unsafe) private static var proben: [String: HauptfadenWache] = [:]
    nonisolated(unsafe) private static var cpuStart: [String: (Double, Date)] = [:]
    nonisolated(unsafe) private static var cpuWerte: [String: Double] = [:]
    nonisolated(unsafe) private static var notizen: [String] = []

    static func starte() {
        guard aktiv else { return }
        FileHandle.standardError.write(Data("MESSUNG: an, Protokoll \(pfad ?? "-")\n".utf8))
        setzeAbschnitt("leerlauf")
        let takt: TimeInterval = 0.01
        Thread.detachNewThread {
            Thread.current.name = "seneca-hauptfadenwache"
            while true {
                let t0 = Date()
                let fertig = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    let ms = Date().timeIntervalSince(t0) * 1000
                    sperre.lock()
                    wache.notiere(ms)
                    if ms > 50 { notizen.append(String(format: "Hänger %.1f ms in „%@“ nach %.1f s", ms, abschnitt, Date().timeIntervalSince(cpuStart[abschnitt]?.1 ?? t0))) }
                    sperre.unlock()
                    fertig.signal()
                }
                fertig.wait()
                Thread.sleep(forTimeInterval: takt)
            }
        }
        if let e = endeSekunden {
            Thread.detachNewThread {
                Thread.current.name = "seneca-messfrist"
                Thread.sleep(forTimeInterval: e)
                schreibe()
                exit(0)
            }
        }
    }

    static func setzeAbschnitt(_ name: String) {
        guard aktiv else { return }
        sperre.lock()
        if abschnitt != "start" {
            proben[abschnitt] = wache
            if let (t0, d0) = cpuStart[abschnitt] {
                let dauer = Date().timeIntervalSince(d0)
                cpuWerte[abschnitt] = dauer > 0 ? (prozessorzeit() - t0) / dauer * 100 : 0
            }
        }
        wache = HauptfadenWache()
        abschnitt = name
        cpuStart[name] = (prozessorzeit(), Date())
        sperre.unlock()
        os_signpost(.event, log: log, name: "abschnitt", "%{public}@", name)
    }

    static func notiere(_ zeile: String) {
        guard aktiv else { return }
        sperre.lock(); notizen.append(zeile); sperre.unlock()
    }

    static func prozessorzeit() -> Double {
        var info = rusage()
        guard getrusage(RUSAGE_SELF, &info) == 0 else { return 0 }
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(info.ru_utime) + s(info.ru_stime)
    }

    static func schreibe() {
        guard aktiv, let p = pfad else { return }
        setzeAbschnitt("ende")
        sperre.lock()
        var zeilen = ["# Messung Seneca Nativ (PID \(ProcessInfo.processInfo.processIdentifier))"]
        for name in ["leerlauf", "scrollen", "strom", "nach-scrollen", "start"] {
            guard let w = proben[name], !w.proben.isEmpty else { continue }
            zeilen.append(w.bericht(name))
            if let cpu = cpuWerte[name] { zeilen.append(String(format: "%@: CPU %.1f %%", name, cpu)) }
        }
        zeilen.append(contentsOf: notizen)
        zeilen.append(String(format: "Prozessorzeit gesamt: %.2f s", prozessorzeit()))
        sperre.unlock()
        try? (zeilen.joined(separator: "\n") + "\n").write(toFile: p, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("MESSUNG: geschrieben nach \(p)\n".utf8))
    }
}
