import Foundation

enum AreasLogic {
    static func chatSession(_ target: String?, main: String) -> String {
        let t = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? main : t
    }

    static func agentID(of sessionKey: String) -> String {
        let parts = sessionKey.split(separator: ":")
        return parts.count >= 2 && parts[0] == "agent" ? String(parts[1]) : Hauptagent.id
    }
}
