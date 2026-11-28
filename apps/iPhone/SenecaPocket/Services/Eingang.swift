import AppIntents
import Foundation
import UIKit

struct AufgabeEintragenIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgabe eintragen"
    static var description = IntentDescription("Trägt einen Satz als deine Aufgabe für heute ein, ohne Seneca zu öffnen.")
    static var openAppWhenRun = false

    @Parameter(title: "Aufgabe", requestValueDialog: "Was soll ich eintragen?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Trage \(\.$text) als Aufgabe ein") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let titel = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titel.isEmpty else { return .result(dialog: "Ich habe nichts verstanden, deshalb habe ich nichts eingetragen.") }
        let angekommen = await Eingang.aufgabe(titel)
        return .result(dialog: IntentDialog(stringLiteral: Eingang.antwort(titel, angekommen: angekommen)))
    }
}

struct WasStehtAnIntent: AppIntent {
    static var title: LocalizedStringResource = "Was steht an?"
    static var description = IntentDescription("Sagt dir, was gerade läuft und was als Nächstes kommt.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let satz = await Eingang.wasStehtAn()
        return .result(value: satz, dialog: IntentDialog(stringLiteral: satz))
    }
}

struct SenecaKurzbefehle: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AufgabeEintragenIntent(),
                    phrases: ["Aufgabe in \(.applicationName) eintragen", "\(.applicationName) Aufgabe eintragen", "Neue Aufgabe für \(.applicationName)"],
                    shortTitle: "Aufgabe eintragen", systemImageName: "plus.circle")
        AppShortcut(intent: WasStehtAnIntent(),
                    phrases: ["Was steht an in \(.applicationName)", "\(.applicationName) was steht an", "Frag \(.applicationName) was ansteht"],
                    shortTitle: "Was steht an?", systemImageName: "calendar")
    }
    static var shortcutTileColor: ShortcutTileColor = .navy
}

@MainActor
enum Eingang {
    private static let wartendKey = "seneca-eingang.aufgaben"
    private static var gruppe: UserDefaults? { UserDefaults(suiteName: WidgetStore.group) }

    static func aufgabe(_ titel: String, jetzt: Date = Date()) async -> Bool {
        let halten = UIApplication.shared.beginBackgroundTask(withName: "seneca.eingang")
        defer { UIApplication.shared.endBackgroundTask(halten) }
        guard let store = SenecaStore.aktuell else {
            gruppe?.set((gruppe?.stringArray(forKey: wartendKey) ?? []) + [titel], forKey: wartendKey)
            return false
        }
        nachtragen(store)
        store.addTask(titel, plan: DayLogic.dayKey(jetzt, .current))
        if !store.isConnected, !store.demo {
            let adresse = UserDefaults.standard.string(forKey: "gatewayURL") ?? ""
            if !adresse.isEmpty {
                store.configure(url: adresse, token: CredentialStore.load(), sessionKey: UserDefaults.standard.string(forKey: "sitzung") ?? Hauptagent.sitzung)
                let verbinden = Task { @MainActor in await store.connect() }
                for _ in 0..<16 where !store.isConnected { try? await Task.sleep(for: .milliseconds(500)) }
                if !store.isConnected { verbinden.cancel() }
            }
        }
        for _ in 0..<10 where store.isConnected {
            if !store.neueTodos.contains(where: { ($0.wert?.roh as? [String: Any])?["titel"] as? String == titel }) { return true }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    static func nachtragen(_ store: SenecaStore) {
        guard let wartend = gruppe?.stringArray(forKey: wartendKey), !wartend.isEmpty else { return }
        gruppe?.removeObject(forKey: wartendKey)
        for titel in wartend { store.addTask(titel, plan: DayLogic.dayKey(Date(), .current)) }
    }

    static func antwort(_ titel: String, angekommen: Bool) -> String {
        angekommen ? "„\(titel)“ steht jetzt bei deinen Aufgaben für heute."
                   : "„\(titel)“ steht bei deinen Aufgaben für heute. Dein Mac bekommt sie, sobald er erreichbar ist."
    }

    static func wasStehtAn() async -> String {
        let satz = (SenecaStore.aktuell?.stand?.heute?.satz ?? []).joined(separator: " ")
        return satz.isEmpty ? "Das weiß ich gerade nicht. Öffne Seneca einmal, dann lade ich deinen Tag." : satz
    }
}
