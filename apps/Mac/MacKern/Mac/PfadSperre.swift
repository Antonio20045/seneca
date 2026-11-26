import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum PfadSperre {
    static func halterPid(bei pfad: URL) -> Int32? {
        guard let text = try? String(contentsOf: pfad, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func lebtNoch(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    static func istFremdBelegt(bei pfad: URL, eigenePid: Int32 = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let halter = halterPid(bei: pfad), halter != eigenePid else { return false }
        return lebtNoch(halter)
    }

    static func belege(bei pfad: URL, eigenePid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        try? "\(eigenePid)".write(to: pfad, atomically: true, encoding: .utf8)
    }

    static func gibFrei(bei pfad: URL, eigenePid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        guard halterPid(bei: pfad) == eigenePid else { return }
        try? FileManager.default.removeItem(at: pfad)
    }

    static func wartetBisFrei(
        bei pfad: URL,
        eigenePid: Int32 = ProcessInfo.processInfo.processIdentifier,
        zeitlimit: TimeInterval = 5,
        schlafintervall: TimeInterval = 0.2,
        schlafe: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> Bool {
        let start = Date()
        while istFremdBelegt(bei: pfad, eigenePid: eigenePid) {
            if Date().timeIntervalSince(start) >= zeitlimit { return false }
            schlafe(schlafintervall)
        }
        return true
    }
}
