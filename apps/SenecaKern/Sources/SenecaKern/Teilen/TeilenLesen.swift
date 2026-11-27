import Foundation
import Vision
import PDFKit

extension TeilenEingang {
    static func team(_ s: SenecaStand) -> [[String]] {
        (s.team ?? []).filter { $0.id != Hauptagent.id }.map { m in
            switch GespraecheTafelLogik.mitglied(m, s).punkt {
            case .arbeitet: [m.name, "arbeitet"]
            case .wartet: [m.name, "fragt"]
            case .fertig: [m.name, "fertig"]
            case .ruht: [m.name, "ruht"]
            }
        }
    }

    static func lesen(_ e: TeilenEintrag) async -> String? {
        guard let ordner, !e.dateien.isEmpty else { return nil }
        let pfade = e.dateien.map { ordner.appendingPathComponent($0) }
        let text = await Task.detached(priority: .userInitiated) { () -> String in
            var teile: [String] = []
            for url in pfade {
                if let pdf = PDFDocument(url: url), let t = pdf.string, !t.isEmpty { teile.append(t); continue }
                if let b = bild(url) {
                    let anfrage = VNRecognizeTextRequest()
                    anfrage.recognitionLevel = .accurate
                    anfrage.recognitionLanguages = ["de-DE", "en-US"]
                    try? VNImageRequestHandler(cgImage: b).perform([anfrage])
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
