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

    static func app(_ mikrofon: Set<String>, nie: Set<String>) -> String? { mikrofon.sorted().first { konferenzApps[$0] != nil && !nie.contains($0) } }
}
