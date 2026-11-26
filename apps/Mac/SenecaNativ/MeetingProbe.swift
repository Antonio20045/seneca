#if DEBUG
import AVFoundation
import AppKit

@MainActor
enum MeetingProbe {
    static func laufe(datei: URL, dienst: MeetingDienst) async {
        func sage(_ t: String) { FileHandle.standardError.write(Data(("[meeting] " + t + "\n").utf8)) }
        defer { dienst.prozess.beendeKind(); NSApp.terminate(nil) }
        var istOrdner: ObjCBool = false
        if FileManager.default.fileExists(atPath: datei.path, isDirectory: &istOrdner), istOrdner.boolValue {
            await erneut(ordner: datei, dienst: dienst, sage: sage)
            return
        }
        do {
            let f = try AVAudioFile(forReading: datei)
            guard let puffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { sage("kein Puffer"); return }
            try f.read(into: puffer)
            let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-probe-\(getpid())", isDirectory: true)
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let kanaele = Int(f.processingFormat.channelCount)
            var schreiber: [MeetingSchreiber] = []
            for k in 0..<min(2, kanaele) {
                let s = try MeetingSchreiber(url: ordner.appendingPathComponent(k == 0 ? "mikrofon.wav" : "systemton.wav"))
                let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: f.processingFormat.sampleRate, channels: 1, interleaved: false)!, frameCapacity: puffer.frameLength)!
                mono.frameLength = puffer.frameLength
                mono.floatChannelData![0].update(from: puffer.floatChannelData![k], count: Int(puffer.frameLength))
                if let w = MeetingWandler().wandle(mono) { s.schreibe(w) }
                s.schliesse()
                schreiber.append(s)
            }
            let dauer = Double(f.length) / f.processingFormat.sampleRate
            sage("Probe: \(String(format: "%.1f", dauer)) s, \(kanaele) Kanäle")
            let e = MeetingDienst.MeetingEingabe(mikro: nil, system: nil, beginn: Date().addingTimeInterval(-dauer), dauer: dauer, titelVorgabe: "Probe",
                                                 vorHinweise: ["Probeaufnahme aus Testdatei (zwei Computerstimmen), kein echtes Mikrofon."],
                                                 mikroDatei: schreiber[0].url, systemDatei: schreiber.count > 1 ? schreiber[1].url : nil)
            guard let a = await dienst.verarbeite(e, probe: true) else { sage("FEHLER: \(dienst.zustand)"); return }
            sage("Datei: \(a.datei.path)")
            sage("Segmente: \(a.ergebnis.segmente.count), Sprecher: \(MeetingTranskript.sprecherAnzahl(a.ergebnis.segmente))")
            sage("Titel: \(a.ergebnis.titel)")
            sage("Aufgaben: \(a.ergebnis.aufgaben)")
            sage("Ollama: \(dienst.ollama.map { "\($0)" } ?? "?")")
            await dienst.frage("Was wurde zuletzt gesagt?")
            sage("Antwort: \(dienst.antworten.last?.text ?? "-")")
            await dienst.uebergebeAufgaben(trocken: true)
            for z in dienst.uebernahme.split(separator: "\n") { sage(String(z)) }
            try? FileManager.default.removeItem(at: ordner)
        } catch { sage("FEHLER: \(error)") }
    }

    private static func erneut(ordner: URL, dienst: MeetingDienst, sage: (String) -> Void) async {
        let liste = MeetingArchiv.eintraege(aufnahmen: ordner.deletingLastPathComponent(), dokumente: MeetingDienst.ordner)
        guard let a = liste.first(where: { $0.name == ordner.lastPathComponent }) else { sage("FEHLER: keine Aufnahme in \(ordner.path)"); return }
        sage("Aufnahme \(a.name): \(Int(a.dauer)) s, Stand vorher: \(a.standText), Datei vorher: \(a.dokument == nil ? "keine" : "vorhanden")")
        let t0 = Date()
        await dienst.werteErneutAus(a)
        guard let erg = dienst.ablage else { sage("FEHLER: \(dienst.zustand)"); return }
        let e = erg.ergebnis
        sage("Datei liegt in: \(erg.datei.deletingLastPathComponent().path)")
        sage("Beiträge: \(e.segmente.count), Sprecher: \(MeetingTranskript.sprecherAnzahl(e.segmente))")
        sage("Stand: \(e.stand)")
        sage("Entscheidungen: \(e.entscheidungen.count), Aufgaben: \(e.alleAufgaben.count) (davon Antonio: \(e.aufgaben.count)), offene Fragen: \(e.offeneFragen.count)")
        sage("Hinweise: \(dienst.hinweise.count)")
        sage("Ollama: \(dienst.ollama.map { "\($0)" } ?? "?")")
        sage("Gesamt: \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
    }
}
#endif
