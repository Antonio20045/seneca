import Foundation
import UIKit
import Vision
import PDFKit

@MainActor
enum TeilenVerarbeiten {
    static var hatFragen: Bool { TeilenEingang.alle().contains { !$0.nurMerken } }

    static func merken() async {
        for e in TeilenEingang.alle() where e.nurMerken {
            let z = TeilenEingang.merkzettel(e, gelesen: await lesen(e))
            await Sinne.shared.melden([TageslaufEreignis(zeit: e.zeit, quelle: "iphone-teilen", art: z.art, titel: z.titel, detail: z.detail, schluessel: "teilen:\(e.id)")])
            TeilenEingang.entfernen(e)
        }
    }

    static func fragen(_ senden: (String, String?, [URL]) -> Bool) async {
        for e in TeilenEingang.alle() where !e.nurMerken {
            let text = TeilenEingang.nachricht(e, gelesen: await lesen(e))
            let bilder = e.dateien.compactMap { n in TeilenEingang.ordner?.appendingPathComponent(n) }.filter { UIImage(contentsOfFile: $0.path) != nil }
            guard senden(text, e.an, bilder) else { return }
            TeilenEingang.entfernen(e)
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    static func lesen(_ e: TeilenEintrag) async -> String? {
        guard let ordner = TeilenEingang.ordner, !e.dateien.isEmpty else { return nil }
        let pfade = e.dateien.map { ordner.appendingPathComponent($0) }
        let text = await Task.detached(priority: .userInitiated) { () -> String in
            var teile: [String] = []
            for url in pfade {
                if let pdf = PDFDocument(url: url), let t = pdf.string, !t.isEmpty { teile.append(t); continue }
                if let bild = UIImage(contentsOfFile: url.path)?.cgImage {
                    let anfrage = VNRecognizeTextRequest()
                    anfrage.recognitionLevel = .accurate
                    anfrage.recognitionLanguages = ["de-DE", "en-US"]
                    try? VNImageRequestHandler(cgImage: bild).perform([anfrage])
                    let zeilen = (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    if !zeilen.isEmpty { teile.append(zeilen.joined(separator: "\n")) }
                    continue
                }
                if let daten = try? Data(contentsOf: url), daten.count < 400_000, let t = String(data: daten, encoding: .utf8), !t.isEmpty { teile.append(t) }
            }
            return teile.joined(separator: "\n\n")
        }.value
        return text.isEmpty ? nil : text
    }
}
