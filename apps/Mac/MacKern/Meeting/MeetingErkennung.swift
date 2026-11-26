import Foundation

enum MeetingErkennung {
    static let konferenzApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.google.Chrome": "Chrome (Meet)",
        "com.apple.FaceTime": "FaceTime",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark": "Webex",
    ]

    static func vorschlag(mikrofonSeit seit: Date?, laufendeApps: [String], nimmtAuf: Bool, schonGefragt: Bool, jetzt: Date, schwelle: TimeInterval = 45) -> String? {
        guard !nimmtAuf, !schonGefragt, let seit, jetzt.timeIntervalSince(seit) >= schwelle else { return nil }
        for k in laufendeApps { if let n = konferenzApps[k] { return n } }
        return nil
    }
}
