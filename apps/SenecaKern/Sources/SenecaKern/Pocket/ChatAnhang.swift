import Foundation
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct ChatAnhang: Identifiable, Equatable, Sendable {
    static let maxFrame = 1024 * 1024
    static let frameRand = 96 * 1024
    static let maxBildKante = 1568
    static let jpegQualitaet = 0.8

    static func base64Groesse(_ bytes: Int) -> Int { (bytes + 2) / 3 * 4 }
    static var maxBase64: Int { maxFrame - frameRand }
    static var hoechstens: String { "Höchstens " + ByteCountFormatter.string(fromByteCount: Int64(maxBase64 / 4 * 3), countStyle: .file) + "." }

    let id = UUID()
    let url: URL
    let name: String
    let mime: String
    let groesse: Int
    var vorher: Int?

    var istBild: Bool { mime.hasPrefix("image/") }

    var problem: String? {
        if groesse == 0 { return "Datei ist leer" }
        if Self.base64Groesse(groesse) > Self.maxBase64 { return "zu groß" }
        return nil
    }

    static func problem(anhaenge: [ChatAnhang], text: String) -> String? {
        if let p = anhaenge.compactMap(\.problem).first { return p }
        let summe = anhaenge.reduce(text.utf8.count) { $0 + base64Groesse($1.groesse) }
        return summe > maxBase64 ? "Anhänge zusammen zu groß für eine Nachricht" : nil
    }

    static func verkleinert(_ daten: Data) -> Data? {
        var letzte: Data?
        for (kante, qualitaet) in [(maxBildKante, jpegQualitaet), (1280, 0.7), (1024, 0.6), (768, 0.5)] {
            guard let k = verkleinert(daten, kante: kante, qualitaet: qualitaet) else { return letzte }
            letzte = k
            if base64Groesse(k.count) <= maxBase64 / 2 { break }
        }
        return letzte
    }

    private static func verkleinert(_ daten: Data, kante: Int, qualitaet: Double) -> Data? {
        guard let quelle = CGImageSourceCreateWithData(daten as CFData, nil) else { return nil }
        let opt: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceThumbnailMaxPixelSize: kante]
        guard let bild = CGImageSourceCreateThumbnailAtIndex(quelle, 0, opt as CFDictionary) else { return nil }
        guard let ctx = CGContext(data: nil, width: bild.width, height: bild.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: bild.width, height: bild.height))
        ctx.draw(bild, in: CGRect(x: 0, y: 0, width: bild.width, height: bild.height))
        guard let flach = ctx.makeImage() else { return nil }
        let aus = NSMutableData()
        guard let ziel = CGImageDestinationCreateWithData(aus, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(ziel, flach, [kCGImageDestinationLossyCompressionQuality: qualitaet] as CFDictionary)
        guard CGImageDestinationFinalize(ziel) else { return nil }
        return aus as Data
    }

    private static func verkleinerbar(_ mime: String) -> Bool {
        mime.hasPrefix("image/") && !(mime.contains("gif") || mime.contains("svg") || mime.contains("pdf"))
    }

    static func von(_ url: URL, fm: FileManager = .default) -> ChatAnhang? {
        guard url.isFileURL else { return nil }
        var istOrdner: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &istOrdner), !istOrdner.boolValue else { return nil }
        let groesse = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        let mime = mimeTyp(url.pathExtension)
        if verkleinerbar(mime), groesse > 0, let daten = try? Data(contentsOf: url), let klein = verkleinert(daten), klein.count < daten.count {
            let basis = (url.lastPathComponent as NSString).deletingPathExtension
            if var a = ausDaten(klein, name: "\(basis)-\(Int(Date().timeIntervalSince1970 * 1000)).jpg", mime: "image/jpeg", ordner: MacPfade.datenOrdner ?? fm.temporaryDirectory, verkleinern: false) { a.vorher = groesse; return a }
        }
        return ChatAnhang(url: url, name: url.lastPathComponent, mime: mime, groesse: groesse)
    }

    static func ziehSatz(_ namen: [String], summe: Int, klein: Int?) -> String {
        let zahl = ["Ein", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn"]
        let n = namen.count, wort = n <= zahl.count ? zahl[n - 1] : String(n)
        let foto = namen.allSatisfy { $0.lowercased().hasPrefix("bildschirmfoto") || $0.lowercased().hasPrefix("screenshot") }
        let bild = namen.allSatisfy { mimeTyp(($0 as NSString).pathExtension).hasPrefix("image/") }
        let art = foto ? (n == 1 ? "Bildschirmfoto" : "Bildschirmfotos") : bild ? (n == 1 ? "Bild" : "Bilder") : (n == 1 ? "Datei" : "Dateien")
        let mb = { (b: Int) in ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file) }
        let anfang = (n == 1 ? (art == "Datei" ? "Eine" : "Ein") : wort) + " " + art + " · " + (n == 1 ? "" : "zusammen ") + mb(summe)
        return anfang + (klein.map { $0 < summe ? " · \(n == 1 ? "wird" : "werden") auf etwa \(mb($0)) verkleinert" : "" } ?? "")
    }

    static func mimeTyp(_ endung: String) -> String {
        #if canImport(UniformTypeIdentifiers)
        if let t = UTType(filenameExtension: endung), let m = t.preferredMIMEType { return m }
        #endif
        return "application/octet-stream"
    }

    static func endung(fuerMime mime: String) -> String {
        #if canImport(UniformTypeIdentifiers)
        if let t = UTType(mimeType: mime), let e = t.preferredFilenameExtension { return e }
        #endif
        return mime == "image/png" ? "png" : mime == "image/tiff" ? "tiff" : mime == "image/jpeg" ? "jpg" : ""
    }

    static func ausDaten(_ daten: Data, name: String? = nil, mime: String, ordner: URL? = MacPfade.datenOrdner, verkleinern: Bool = true) -> ChatAnhang? {
        guard let ordner, !daten.isEmpty else { return nil }
        var daten = daten, mime = mime, name = name
        let vorher = daten.count
        if verkleinern, verkleinerbar(mime), let klein = verkleinert(daten), klein.count < daten.count {
            daten = klein; mime = "image/jpeg"
            if let n = name { name = (n as NSString).deletingPathExtension + ".jpg" }
        }
        let anhaengeOrdner = ordner.appendingPathComponent("anhaenge", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: anhaengeOrdner, withIntermediateDirectories: true)) != nil else { return nil }
        let endung = endung(fuerMime: mime)
        let dateiname = name ?? "bildschirmfoto-\(Int(Date().timeIntervalSince1970 * 1000))" + (endung.isEmpty ? "" : ".\(endung)")
        let url = anhaengeOrdner.appendingPathComponent(dateiname)
        guard (try? daten.write(to: url, options: .atomic)) != nil else { return nil }
        return ChatAnhang(url: url, name: dateiname, mime: mime, groesse: daten.count, vorher: vorher > daten.count ? vorher : nil)
    }

    func json() throws -> [String: Any] {
        let daten = try Data(contentsOf: url)
        return ["type": istBild ? "image" : "file", "mimeType": mime, "fileName": name, "origin": "file",
                "content": daten.base64EncodedString(), "sizeBytes": daten.count]
    }

    private static let muster = try! NSRegularExpression(pattern: #"\n?\[media attached(?:\s+\d+/\d+)?:\s*([^\]]+)\]"#, options: [.caseInsensitive])

    static func hinweis(_ name: String) -> String { "[media attached: \(name)]" }

    static func zerlege(_ text: String) -> (text: String, namen: [String]) {
        guard text.contains("[media attached") else { return (text, []) }
        let ns = text as NSString
        let treffer = muster.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !treffer.isEmpty else { return (text, []) }
        let namen = treffer.map { anzeigeName(ns.substring(with: $0.range(at: 1))) }
        let rest = muster.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (rest.trimmingCharacters(in: .whitespacesAndNewlines), namen)
    }


    static func anzeigeName(_ ref: String) -> String {
        var s = ref.trimmingCharacters(in: .whitespaces)
        if let i = s.lastIndex(where: { $0 == "/" }) { s = String(s[s.index(after: i)...]) }
        if let r = s.range(of: "---") {
            let endung = (s as NSString).pathExtension
            s = String(s[..<r.lowerBound]) + (endung.isEmpty ? "" : "." + endung)
        }
        return s.isEmpty ? ref : s
    }

    static func faden(text: String, anhaenge: [ChatAnhang]) -> String {
        ([text] + anhaenge.map { hinweis($0.name) }).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static let leerText = "Siehe Anhang."
}

extension ChatAnhang {
    static func ausEingefuegtem(alt: String, neu: String, fm: FileManager = .default) -> (text: String, urls: [URL])? {
        guard neu.count > alt.count, neu.contains("/") else { return nil }
        let a = Array(alt), n = Array(neu)
        var vorn = 0
        while vorn < a.count, a[vorn] == n[vorn] { vorn += 1 }
        var hinten = 0
        while hinten < a.count - vorn, a[a.count - 1 - hinten] == n[n.count - 1 - hinten] { hinten += 1 }
        let eingefuegt = String(n[vorn ..< (n.count - hinten)])
        let zeilen = eingefuegt.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !zeilen.isEmpty else { return nil }
        var urls: [URL] = []
        for z in zeilen {
            var pfad = z
            if let u = URL(string: z), u.isFileURL { pfad = u.path }
            else if pfad.hasPrefix("~") { pfad = (pfad as NSString).expandingTildeInPath }
            var ordner: ObjCBool = false
            guard pfad.hasPrefix("/"), fm.fileExists(atPath: pfad, isDirectory: &ordner), !ordner.boolValue else { return nil }
            urls.append(URL(fileURLWithPath: pfad))
        }
        let rest = String(n[0 ..< vorn]) + String(n[(n.count - hinten)...])
        return (rest.trimmingCharacters(in: .whitespacesAndNewlines) == "" ? "" : rest, urls)
    }
}
