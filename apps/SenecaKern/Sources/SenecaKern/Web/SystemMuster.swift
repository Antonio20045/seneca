import Foundation

enum SystemMuster {
    static let versteckteZeilen: [(String, String)] = [
        (#"^OpenClaw resumed this CLI session"#, "i"),
        (#"^An async command completion event"#, "i"),
        (#"^\[OpenClaw heartbeat"#, "i"),
        (#"^/(reset|new|clear)$"#, "i"),
        (#"^HEARTBEAT"#, "i"),
    ]
    static let systemPraefixZeile = (#"^OpenClaw resumed this CLI session[^\n]*\n?"#, "im")
    static let systemKlammer = (#"^\[OpenClaw"#, "i")

    static func istVersteckt(_ text: String) -> Bool { versteckteZeilen.contains { text.passt($0.0, $0.1) } }

    static func istProbe(_ text: String) -> Bool {
        text.passt(#"^\s*\[Messpunkt, automatisch\]"#, "m") || text.passt(#"Kettenprobe k\d|KETTE-"#)
    }
    static func fortgesetztRest(_ text: String) -> String? {
        guard text.passt(#"^OpenClaw resumed this CLI session"#, "i") else { return nil }
        var rest = text
        if let r = rest.range(of: "\n\n") { rest = String(rest[r.upperBound...]) } else { return "" }
        if let r = rest.range(of: "Follow the heartbeat monitor scratch context") { rest = String(rest[..<r.lowerBound]) }
        return rest.jsTrim
    }
    static func beginntMitKlammer(_ text: String) -> Bool { text.passt(systemKlammer.0, systemKlammer.1) }
    static func ohnePraefixZeile(_ text: String) -> String { text.ersetze(systemPraefixZeile.0, "", systemPraefixZeile.1) }

    static func istSystemAnbieter(_ p: Any?) -> Bool { (p as? String) == "openclaw" }

    static func istProbeQuittung(_ text: String) -> Bool { text.passt(#"^\s*KETTE-[A-ZÄÖÜ]+"#) }

    static func verwaltungsBefehl(_ cmd: String) -> String? {
        guard cmd.passt(#"\bopenclaw\s+(status|doctor|automations|cron|mcp|channels|models|sessions|agents)\b"#) else { return nil }
        return cmd.treffer(#"openclaw\s+(\w+)"#)?[1] ?? ""
    }
}
