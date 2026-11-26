#if DEBUG
import SwiftUI
import AppKit
import AVFoundation

@MainActor
final class DiktatMessFeld: ObservableObject {
    @Published var text = ""
}

struct DiktatMessungView: View {
    @ObservedObject var feld: DiktatMessFeld
    @ObservedObject var dienst: DiktatDienst
    @FocusState private var fokus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diktat-Messung").font(Schrift.serif(25)).foregroundStyle(Farbe.ink1)
            Text(dienst.modellBereit ? "Modell geladen" : (dienst.modellFehler ?? "Modell lädt …"))
                .font(Schrift.grotesk(13)).foregroundStyle(dienst.modellFehler == nil ? Farbe.ink2 : Farbe.koralle)
            TextField("", text: $feld.text, prompt: Text("Testfeld").foregroundColor(Farbe.ink4), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($fokus)
                .font(Schrift.grotesk(15))
                .foregroundStyle(Farbe.ink1)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Farbe.flaeche2, in: RoundedRectangle(cornerRadius: Mass.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Mass.radius, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
                .accessibilityIdentifier("diktat-messfeld")
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Farbe.grund)
        .onAppear { fokus = true }
    }
}

struct DiktatVergleich {
    var referenzWorte: Int
    var erkannteWorte: Int
    var ersetzt: Int
    var eingefuegt: Int
    var ausgelassen: Int

    var wer: Double { referenzWorte == 0 ? 0 : Double(ersetzt + eingefuegt + ausgelassen) / Double(referenzWorte) }
    var abdeckung: Double { referenzWorte == 0 ? 1 : Double(referenzWorte - ausgelassen) / Double(referenzWorte) }

    static let zahlwort: [String: String] = [
        "0": "null", "1": "eins", "2": "zwei", "3": "drei", "4": "vier", "5": "fünf", "6": "sechs",
        "7": "sieben", "8": "acht", "9": "neun", "10": "zehn", "11": "elf", "12": "zwölf",
    ]

    static func worte(_ t: String) -> [String] {
        var s = t.lowercased().replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: "(?<=[0-9])[.,](?=[0-9])", with: "", options: .regularExpression)
        return s.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'äöüß-")).inverted)
            .filter { !$0.isEmpty }
            .map { zahlwort[$0] ?? $0 }
    }

    static func zwischen(referenz: String, erkannt: String) -> DiktatVergleich {
        let r = worte(referenz)
        let e = worte(erkannt)
        var d = Array(repeating: Array(repeating: 0, count: e.count + 1), count: r.count + 1)
        for i in 0...r.count { d[i][0] = i }
        for j in 0...e.count { d[0][j] = j }
        if r.count > 0, e.count > 0 {
            for i in 1...r.count {
                for j in 1...e.count {
                    let gleich = r[i - 1] == e[j - 1]
                    d[i][j] = min(d[i - 1][j - 1] + (gleich ? 0 : 1), d[i - 1][j] + 1, d[i][j - 1] + 1)
                }
            }
        }
        var i = r.count, j = e.count
        var s = 0, ein = 0, aus = 0
        while i > 0 || j > 0 {
            if i > 0, j > 0, r[i - 1] == e[j - 1], d[i][j] == d[i - 1][j - 1] { i -= 1; j -= 1; continue }
            if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + 1 { s += 1; i -= 1; j -= 1; continue }
            if i > 0, d[i][j] == d[i - 1][j] + 1 { aus += 1; i -= 1; continue }
            if j > 0 { ein += 1; j -= 1; continue }
            break
        }
        return DiktatVergleich(referenzWorte: r.count, erkannteWorte: e.count, ersetzt: s, eingefuegt: ein, ausgelassen: aus)
    }
}

struct DiktatMessSatz: Codable {
    var datei: String
    var referenz: String
}

struct DiktatMessZeile: Codable {
    var nummer: Int
    var datei: String
    var referenz: String
    var erkannt: String
    var ziel: String
    var ergebnis: String
    var imFeld: Bool
    var vollstaendig: Bool
    var verloren: Bool
    var wer: Double
    var abdeckung: Double
    var ersetzt: Int
    var eingefuegt: Int
    var ausgelassen: Int
    var wartezeitMs: Int
    var meldung: String?
}

struct DiktatMessBericht: Codable {
    var zeilen: [DiktatMessZeile]
    var medianMs: Int
    var maxMs: Int
    var vollstaendig: Int
    var anzahl: Int
    var medianWer: Double
    var modellOrdner: String
    var vorwaermenMs: Int
}

@MainActor
enum DiktatMessung {
    static var ordner: URL? {
        guard let p = ProcessInfo.processInfo.environment["SENECA_DIKTAT_MESSUNG"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var aktiv: Bool { ordner != nil }

    static func laufe(feld: DiktatMessFeld, dienst: DiktatDienst) async {
        guard let ordner else { return }
        func sage(_ t: String) {
            FileHandle.standardError.write(Data(("[messung] " + t + "\n").utf8))
        }
        guard let roh = try? Data(contentsOf: ordner.appendingPathComponent("saetze.json")),
              let saetze = try? JSONDecoder().decode([DiktatMessSatz].self, from: roh), !saetze.isEmpty else {
            sage("saetze.json fehlt oder ist leer: \(ordner.path)")
            NSApp.terminate(nil)
            return
        }

        let w0 = Date()
        await dienst.waermeVor()
        let vorwaermen = Int(Date().timeIntervalSince(w0) * 1000)
        if let f = dienst.modellFehler {
            sage("Modell nicht geladen: \(f)")
            try? JSONEncoder().encode(DiktatMessBericht(zeilen: [], medianMs: 0, maxMs: 0, vollstaendig: 0, anzahl: 0,
                                                        medianWer: 0, modellOrdner: DiktatPfade.modellOrdner.path,
                                                        vorwaermenMs: vorwaermen))
                .write(to: ordner.appendingPathComponent("ergebnis.json"), options: .atomic)
            NSApp.terminate(nil)
            return
        }
        sage("Modell geladen in \(vorwaermen) ms")

        Hintergrund.aktiviere()
        let fokusFrist = Date().addingTimeInterval(5)
        while DiktatEinfueger.feldImFokus() == nil, Date() < fokusFrist {
            Hintergrund.aktiviere()
            try? await Task.sleep(for: .milliseconds(50))
        }
        sage(DiktatEinfueger.feldImFokus() == nil ? "WARNUNG: kein Feld im Fokus" : "Testfeld hat den Fokus")

        await tastenprobe(sage)
        await aufnahmeprobe(sage)

        var zeilen: [DiktatMessZeile] = []
        for (i, satz) in saetze.enumerated() {
            Hintergrund.aktiviere()
            feld.text = ""
            try? await Task.sleep(for: .milliseconds(120))
            let datei = ordner.appendingPathComponent(satz.datei)

            let losgelassen = Date()
            let ergebnis = await dienst.verarbeite(aufnahme: datei, losgelassen: losgelassen)

            var text = ""
            var art = "fehlgeschlagen"
            var ziel = "—"
            var meldung: String?
            switch ergebnis {
            case .eingefuegt(let t, let z): text = t; art = "erfolgreich"; ziel = z
            case .zwischenablage(let t): text = t; art = "zwischenablage"; ziel = "zwischenablage"
            case .fehlgeschlagen(let m): meldung = m
            }

            var imFeld = false
            let frist = Date().addingTimeInterval(5)
            while Date() < frist {
                if !text.isEmpty, feld.text.contains(text) { imFeld = true; break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            let wartezeit = Int(Date().timeIntervalSince(losgelassen) * 1000)

            let v = DiktatVergleich.zwischen(referenz: satz.referenz, erkannt: text)
            let verloren = !imFeld || text.isEmpty || v.abdeckung < 0.8
            zeilen.append(DiktatMessZeile(nummer: i + 1, datei: satz.datei, referenz: satz.referenz, erkannt: text,
                                          ziel: ziel, ergebnis: art, imFeld: imFeld, vollstaendig: !verloren,
                                          verloren: verloren, wer: v.wer, abdeckung: v.abdeckung,
                                          ersetzt: v.ersetzt, eingefuegt: v.eingefuegt, ausgelassen: v.ausgelassen,
                                          wartezeitMs: wartezeit, meldung: meldung))
            sage(String(format: "%2d/%d  %4d ms  vollständig=%@  WER=%.2f  %@", i + 1, saetze.count, wartezeit,
                        verloren ? "nein" : "ja", v.wer, text))
            dienst.schliessePille()
        }

        let zeiten = zeilen.map(\.wartezeitMs).sorted()
        let median = zeiten.isEmpty ? 0 : (zeiten.count % 2 == 1 ? zeiten[zeiten.count / 2]
                                           : (zeiten[zeiten.count / 2 - 1] + zeiten[zeiten.count / 2]) / 2)
        let wers = zeilen.map(\.wer).sorted()
        let medianWer = wers.isEmpty ? 0 : (wers.count % 2 == 1 ? wers[wers.count / 2]
                                            : (wers[wers.count / 2 - 1] + wers[wers.count / 2]) / 2)
        let bericht = DiktatMessBericht(zeilen: zeilen, medianMs: median, maxMs: zeiten.last ?? 0,
                                        vollstaendig: zeilen.filter(\.vollstaendig).count, anzahl: zeilen.count,
                                        medianWer: medianWer, modellOrdner: DiktatPfade.modellOrdner.path,
                                        vorwaermenMs: vorwaermen)
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? kodierer.encode(bericht) {
            try? d.write(to: ordner.appendingPathComponent("ergebnis.json"), options: .atomic)
        }
        sage("fertig: \(bericht.vollstaendig)/\(bericht.anzahl) vollständig, Median \(median) ms, Max \(bericht.maxMs) ms")
        NSApp.terminate(nil)
    }

    private static func tastenprobe(_ sage: (String) -> Void) async {
        let t = DiktatTaste()
        var tipps = 0, escapes = 0
        t.tipp = { tipps += 1 }
        t.escape = { escapes += 1 }
        let rechts: UInt = 0x100000 | 0x10, ohne: UInt = 0x100
        func tippen(_ z0: Double, dauer: Double, dazwischen: DiktatTippErkennung.Ereignis? = nil) {
            t.pruefe(.flaggen(code: 54, flags: rechts, zeit: z0))
            if let d = dazwischen { t.pruefe(d) }
            t.pruefe(.flaggen(code: 54, flags: ohne, zeit: z0 + dauer))
        }
        tippen(1, dauer: 0.12)
        let nachTipp = tipps
        tippen(2, dauer: 0.12, dazwischen: .taste(code: 8, zeit: 2.05))
        let nachKuerzel = tipps
        tippen(3, dauer: 0.9)
        let nachHalten = tipps
        t.pruefe(.taste(code: 53, zeit: 4))
        let ok = nachTipp == 1 && nachKuerzel == 1 && nachHalten == 1 && escapes == 1
        sage("Tastenprobe: \(ok ? "in Ordnung" : "FEHLER") — Tippen=\(nachTipp) ⌘-Kürzel=\(nachKuerzel - nachTipp) langes-Halten=\(nachHalten - nachKuerzel) Escape=\(escapes)")
    }

    private static func aufnahmeprobe(_ sage: (String) -> Void) async {
        if DiktatMikrofonRegel.gesperrtFuerHintergrundOderTest(
            hintergrundAktiv: Hintergrund.aktiv, profilTest: MacPfade.profil == .test,
            datenOrdnerUeberschrieben: ProcessInfo.processInfo.environment["SENECA_DATEN"] != nil) {
            sage("Aufnahmeprobe: übersprungen (Hintergrund-/Test-Instanz darf das echte Mikrofon nicht anfassen)")
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            sage("Aufnahmeprobe: übersprungen (Mikrofon noch nicht freigegeben — bitte bei der Handprobe prüfen)")
            return
        }
        let a = DiktatAufnahme()
        do {
            _ = try a.starte()
        } catch {
            sage("Aufnahmeprobe: FEHLER beim Starten — \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            return
        }
        try? await Task.sleep(for: .milliseconds(1200))
        guard let u = a.beende(), let datei = try? AVAudioFile(forReading: u) else {
            sage("Aufnahmeprobe: FEHLER — keine lesbare Datei")
            return
        }
        let sekunden = Double(datei.length) / datei.fileFormat.sampleRate
        sage(String(format: "Aufnahmeprobe: in Ordnung — %.2f s bei %.0f Hz, %@", sekunden, datei.fileFormat.sampleRate, u.lastPathComponent))
        try? FileManager.default.removeItem(at: u)
    }
}
#endif
