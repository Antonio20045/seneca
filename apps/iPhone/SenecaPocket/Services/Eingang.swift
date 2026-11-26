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
        AppShortcut(intent: SenecaSagenIntent(),
                    phrases: ["\(.applicationName) etwas sagen", "Mit \(.applicationName) sprechen", "Sprich mit \(.applicationName)"],
                    shortTitle: "Seneca etwas sagen", systemImageName: "mic")
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
        let ereignis = TageslaufEreignis(zeit: jetzt, art: "zusage", titel: titel, detail: ["aufgabe": true, "von_mir": true, "weg": "kurzbefehl"],
                                         schluessel: "aufgabe:\(Int(jetzt.timeIntervalSince1970)):\(titel.count)")
        guard let store = SenecaStore.aktuell else {
            gruppe?.set((gruppe?.stringArray(forKey: wartendKey) ?? []) + [titel], forKey: wartendKey)
            await Sinne.shared.melden([ereignis])
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
        var angekommen = false
        if store.isConnected {
            await store.flushOutbox()
            for _ in 0..<10 {
                if !store.outbox.contains(where: { $0.kind == .create && $0.title == titel }) { angekommen = true; break }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        await Sinne.shared.melden([ereignis])
        return angekommen
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

    static func wasStehtAn(jetzt: Date = Date()) async -> String {
        var wartet: [String] = []
        if let antwort = try? await Sinne.shared.rufe("seneca.tageslauf.heute", [:], zeitlimit: 4), let bild = TageslaufBild.lesen(antwort) {
            AblaufSpeicher.schreiben(bild)
            wartet = (bild.fuerDich ?? []).filter { $0.art == .antwort && !$0.von.isEmpty }.map(\.von)
        }
        Sinne.shared.hintergrundEnde()
        let satz = Tagesablauf.ansage(TagesablaufQuelle.punkteOhneOberflaeche(jetzt), jetzt: jetzt)
        return [satz, Tagesablauf.wartetAnsage(wartet)].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
