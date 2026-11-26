import AppIntents
import Foundation

enum SenecaWunsch {
    static let diktat = "diktat"
    static let gruppe = "group.de.antonio.senecapocket"
    private static let key = "seneca-wunsch"
    static let meldung = Notification.Name("seneca.wunsch")
    static let haltbar: TimeInterval = 30

    static func setzen(_ was: String, jetzt: Date = Date()) {
        UserDefaults(suiteName: gruppe)?.set(["was": was, "zeit": jetzt.timeIntervalSince1970], forKey: key)
        NotificationCenter.default.post(name: meldung, object: nil)
    }

    static func abholen(jetzt: Date = Date()) -> String? {
        let defaults = UserDefaults(suiteName: gruppe)
        guard let w = defaults?.dictionary(forKey: key), let was = w["was"] as? String, let zeit = w["zeit"] as? Double else { return nil }
        defaults?.removeObject(forKey: key)
        return jetzt.timeIntervalSince1970 - zeit <= haltbar ? was : nil
    }
}

struct SenecaSagenIntent: AppIntent {
    static var title: LocalizedStringResource = "Seneca etwas sagen"
    static var description = IntentDescription("Öffnet Seneca und hört dir sofort zu.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SenecaWunsch.setzen(SenecaWunsch.diktat)
        return .result()
    }
}
