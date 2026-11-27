import SwiftUI
import PDFKit
import AVFoundation
import AppKit
import Quartz

struct SenecaTextView: View {
    var text: String
    var live: Bool

    var body: some View {
        Abschnitte(teile: live ? Inhaltsspeicher.baue(text, art: .offen) : Inhaltsspeicher.teile(text), live: live)
    }
}

struct Abschnitte: View {
    var teile: [FertigerTeil]
    var live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(teile.enumerated()), id: \.offset) { _, teil in
                switch teil {
                case .abschnitte(let gruppen):
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(gruppen.enumerated()), id: \.offset) { _, g in
                            switch g {
                            case .fluss(let attr): MarkdownFlussView(text: attr)
                            case .code(let t, let titel): CodeBlockView(code: t, titel: titel, live: live)
                            case .table(let header, let rows): TabelleAnsicht(t: Karte.Tabelle(spalten: header, zeilen: rows)).textSelection(.enabled).accessibilityIdentifier("antwort-tabelle")
                            case .image(let alt, let src): BildBlockView(alt: alt, src: src)
                            case .datei(let pfad): DateiKachelView(pfad: pfad)
                            case .trenner: Divider().overlay(Farbe.linie)
                            }
                        }
                    }
                case .entwurf(let e): EntwurfKarteView(entwurf: e)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum FertigerAbschnitt {
    case fluss(NSAttributedString)
    case code(String, titel: String?)
    case table(header: [String], rows: [[String]])
    case image(alt: String, src: String)
    case datei(String)
    case trenner
}

enum FertigerTeil {
    case abschnitte([FertigerAbschnitt])
    case entwurf(Entwurf)

    var istLeer: Bool { if case .abschnitte(let a) = self { return a.isEmpty }; return false }
}

@MainActor
enum Inhaltsspeicher {
    static let maxEintraege = 96

    enum Art { case fertig, fest, offen }

    private static var speicher: [String: (teile: [FertigerTeil], nr: UInt64)] = [:]
    private static var zaehler: UInt64 = 0

    static func teile(_ text: String) -> [FertigerTeil] {
        zaehler += 1
        if let fertig = speicher[text] {
            speicher[text] = (fertig.teile, zaehler)
            return fertig.teile
        }
        let gebaut = baue(text, art: .fertig)
        speicher[text] = (gebaut, zaehler)
        if speicher.count > maxEintraege, let aeltester = speicher.min(by: { $0.value.nr < $1.value.nr })?.key {
            speicher[aeltester] = nil
        }
        return gebaut
    }

    static func baue(_ text: String, art: Art) -> [FertigerTeil] {
        let rohTeile: [EntwurfTeil] = art == .fertig ? EntwurfErkennung.teile(text) : [.text(text)]
        return rohTeile.map { teil in
            switch teil {
            case .entwurf(let e): return .entwurf(e)
            case .text(let t):
                return .abschnitte(Inhaltsabschnitt.gruppiere(MDParser.parse(t, live: art == .offen)).map { g in
                    switch g {
                    case .fluss(let b): return .fluss(Inhaltsabschnitt.flussAttributed(b))
                    case .code(let l, let s): return .code(s, titel: l.flatMap { $0.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) })
                    case .table(let h, let r): return .table(header: h, rows: r)
                    case .image(let alt, let src): return .image(alt: alt, src: src)
                    case .datei(let p): return .datei(p)
                    case .trenner: return .trenner
                    }
                })
            }
        }
    }
}

enum Inhaltsabschnitt {
    case fluss([MDBlock])
    case code(lang: String?, text: String)
    case table(header: [String], rows: [[String]])
    case image(alt: String, src: String)
    case datei(String)
    case trenner

    static func gruppiere(_ bloecke: [MDBlock]) -> [Inhaltsabschnitt] {
        var out: [Inhaltsabschnitt] = []
        var lauf: [MDBlock] = []
        func flush() { if !lauf.isEmpty { out.append(.fluss(lauf)); lauf = [] } }
        for b in bloecke {
            switch b.kind {
            case .code(let lang, let t): flush(); out.append(.code(lang: lang, text: t))
            case .table(let h, let r): flush(); out.append(.table(header: h, rows: r))
            case .image(let alt, let src): flush(); out.append(.image(alt: alt, src: src))
            case .rule: flush(); out.append(.trenner)
            case .paragraph(let t):
                if let pfad = DateiErkennung.alleinstehend(t) { flush(); out.append(.datei(pfad)) }
                else { lauf.append(b) }
            default: lauf.append(b)
            }
        }
        flush()
        return out
    }

    private static func nsGrotesk(_ gewicht: Schrift.Gewicht, _ groesse: CGFloat) -> NSFont {
        NSFont(name: "SpaceGrotesk-\(gewicht.rawValue)", size: groesse)
            ?? .systemFont(ofSize: groesse, weight: gewicht == .medium ? .medium : gewicht == .light ? .light : .regular)
    }
    private static func nsSerif(_ groesse: CGFloat, kursiv: Bool = false) -> NSFont {
        NSFont(name: kursiv ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: groesse) ?? .systemFont(ofSize: groesse)
    }
    private static func nsMono(_ groesse: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: groesse, weight: .regular) }

    private static func inlineNS(_ t: String, basis: NSFont, farbe: NSColor) -> NSMutableAttributedString {
        let a = MDInline.attributed(t)
        let out = NSMutableAttributedString()
        for run in a.runs {
            let stueck = String(a.characters[run.range])
            guard !stueck.isEmpty else { continue }
            var font = basis
            if let absicht = run.inlinePresentationIntent {
                if absicht.contains(.code) { font = nsMono(13) }
                else if absicht.contains(.stronglyEmphasized) { font = nsGrotesk(.medium, 15) }
                else if absicht.contains(.emphasized) { font = nsSerif(18, kursiv: true) }
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: farbe]
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor(Farbe.himmel)
                attrs[.cursor] = NSCursor.pointingHand
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = NSColor(Farbe.himmel).withAlphaComponent(0.4)
            }
            out.append(NSAttributedString(string: stueck, attributes: attrs))
            if let ziel = run.link?.host, !stueck.contains(ziel) {
                let pfad = (ziel + run.link!.path)
                out.append(NSAttributedString(string: " " + (pfad.count > 15 ? String(pfad.prefix(15)) + "…" : pfad), attributes: [.font: nsMono(11), .foregroundColor: NSColor(TafelFarbe.aus)]))
            }
        }
        return out
    }

    static func flussAttributed(_ bloecke: [MDBlock]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, b) in bloecke.enumerated() {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 4
            para.paragraphSpacingBefore = i == 0 ? 0 : 8
            let stueck: NSMutableAttributedString
            switch b.kind {
            case .paragraph(let t):
                stueck = inlineNS(t, basis: nsGrotesk(.regular, 15), farbe: NSColor(TafelFarbe.zweit))
            case .heading(let level, let t):
                let groesse: CGFloat = level == 1 ? 30 : level == 2 ? 25 : 21
                stueck = inlineNS(t, basis: nsSerif(groesse), farbe: NSColor(Farbe.ink1))
                para.paragraphSpacingBefore = i == 0 ? 0 : 12
            case .item(let depth, let marker, let t):
                var praefixFarbe = NSColor(Farbe.ink3)
                let praefix: String
                switch marker {
                case .bullet: praefix = "•  "; praefixFarbe = NSColor(Farbe.himmel)
                case .number(let n): praefix = "\(n)\t"; praefixFarbe = NSColor(TafelFarbe.himmel)
                case .check(let an):
                    praefix = an ? "☑  " : "☐  "
                    praefixFarbe = an ? NSColor(Farbe.gruen) : NSColor(Farbe.ink3)
                }
                let nummer: Bool = { if case .number = marker { return true }; return false }()
                let s = NSMutableAttributedString(string: praefix, attributes: [.font: nummer ? nsMono(12) : nsGrotesk(.light, 15), .foregroundColor: praefixFarbe])
                s.append(inlineNS(t, basis: nsGrotesk(.regular, 15), farbe: NSColor(nummer ? TafelFarbe.text : TafelFarbe.zweit)))
                if case .check(true) = marker { s.addAttribute(.strikethroughStyle, value: 0, range: NSRange(location: 0, length: s.length)) }
                stueck = s
                para.headIndent = CGFloat(depth) * 18 + 22
                para.firstLineHeadIndent = CGFloat(depth) * 18 + (nummer ? 0 : 4)
                para.tabStops = [NSTextTab(textAlignment: .left, location: CGFloat(depth) * 18 + 22)]
                para.paragraphSpacingBefore = i == 0 ? 0 : 6
            case .quote(let t):
                let s = NSMutableAttributedString(string: "▌ ", attributes: [.font: nsGrotesk(.regular, 18), .foregroundColor: NSColor(Farbe.himmel).withAlphaComponent(0.5)])
                s.append(inlineNS(t, basis: nsSerif(18, kursiv: true), farbe: NSColor(Farbe.ink2)))
                stueck = s
                para.headIndent = 14
            case .rule, .code, .table, .image: continue
            }
            stueck.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: stueck.length))
            out.append(stueck)
            if i < bloecke.count - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }
}

enum AppActions {
    static func dateiOeffnen(_ pfad: String) {
        guard FileManager.default.fileExists(atPath: pfad) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: pfad))
    }
}

enum SenecaLinkOeffnen {
    static func oeffne(_ url: URL) {
        if let pfad = MDLink.dateiPfad(aus: url) { AppActions.dateiOeffnen(pfad) }
        else { NSWorkspace.shared.open(url) }
    }
}

@MainActor
enum HoehenSpeicher {
    static let maxEintraege = 512

    private struct Schluessel: Hashable { var text: String; var breite: CGFloat }
    private static var speicher: [Schluessel: (text: NSAttributedString, hoehe: CGFloat, nr: UInt64)] = [:]
    private static var zaehler: UInt64 = 0

    static func hoehe(_ text: NSAttributedString, breite: CGFloat) -> CGFloat? {
        let k = Schluessel(text: text.string, breite: breite)
        guard let t = speicher[k], t.text.isEqual(to: text) else { return nil }
        zaehler += 1
        speicher[k] = (t.text, t.hoehe, zaehler)
        return t.hoehe
    }

    static func merke(_ text: NSAttributedString, breite: CGFloat, hoehe: CGFloat) {
        zaehler += 1
        speicher[Schluessel(text: text.string, breite: breite)] = (NSAttributedString(attributedString: text), hoehe, zaehler)
        if speicher.count > maxEintraege, let aeltester = speicher.min(by: { $0.value.nr < $1.value.nr })?.key {
            speicher[aeltester] = nil
        }
    }
}

@MainActor
enum TextMass {
    private static let speicher = NSTextStorage()
    private static let behaelter: NSTextContainer = {
        let tc = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        return tc
    }()
    private static let satz: NSLayoutManager = {
        let lm = NSLayoutManager()
        lm.addTextContainer(behaelter)
        speicher.addLayoutManager(lm)
        return lm
    }()

    static func hoehe(_ text: NSAttributedString, breite: CGFloat) -> CGFloat {
        let lm = satz
        behaelter.size = NSSize(width: breite, height: .greatestFiniteMagnitude)
        speicher.setAttributedString(text)
        lm.ensureLayout(for: behaelter)
        return ceil(lm.usedRect(for: behaelter).height)
    }
}

struct MarkdownFlussView: NSViewRepresentable {
    var text: NSAttributedString

    func makeNSView(context: Context) -> NSTextView {
        let v = NSTextView(usingTextLayoutManager: false)
        v.isEditable = false
        v.isSelectable = true
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = true
        v.isHorizontallyResizable = false
        v.delegate = context.coordinator
        v.linkTextAttributes = [:]
        v.textStorage?.setAttributedString(text)
        return v
    }

    func updateNSView(_ v: NSTextView, context: Context) {
        guard v.textStorage?.isEqual(to: text) != true else { return }
        v.textStorage?.setAttributedString(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NSTextView, context: Context) -> CGSize? {
        let breite = proposal.width ?? 680
        let co = context.coordinator
        if co.cachedWidth == breite, co.cachedText?.isEqual(to: text) == true {
            return co.cachedSize
        }
        let groesse: CGSize
        if let gemerkt = HoehenSpeicher.hoehe(text, breite: breite) {
            groesse = CGSize(width: breite, height: gemerkt)
        } else {
            groesse = CGSize(width: breite, height: TextMass.hoehe(text, breite: breite))
            HoehenSpeicher.merke(text, breite: breite, hoehe: groesse.height)
        }
        co.cachedWidth = breite
        co.cachedText = text
        co.cachedSize = groesse
        return groesse
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var cachedWidth: CGFloat = -1
        var cachedText: NSAttributedString?
        var cachedSize: CGSize?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            SenecaLinkOeffnen.oeffne(url)
            return true
        }
    }
}

struct CodeBlockView: View {
    var code: String
    var titel: String?
    var live: Bool
    @State private var offen = false
    @State private var kopiert = false

    var body: some View {
        let langStr = CodeFalte.eingeklappt(code) && !live
        VStack(alignment: .leading, spacing: 0) {
            if langStr {
                Button { withAnimation(Kurve.ease(0.25)) { offen.toggle() } } label: {
                    Text((offen ? "▾ " : "▸ ") + "\(titel ?? "Code") · \(CodeFalte.zeilen(code)) Zeilen").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("code-falte")
            } else if let titel {
                Text(titel).foregroundStyle(TafelFarbe.leise)
            }
            if !langStr || offen { Text(code).foregroundStyle(TafelFarbe.text).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
        }
        .font(Schrift.mono(13)).lineHeight(.exact(points: 20))
        .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(TafelFarbe.hex(0x030A18, 0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .topTrailing) { kopierKnopf.padding(.trailing, 10).padding(.top, 8) }
    }

    private var kopierKnopf: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            kopiert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { kopiert = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kopiert ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .medium))
                Text(kopiert ? "Kopiert" : "Kopieren").font(Schrift.grotesk(12))
            }
            .foregroundStyle(kopiert ? TafelFarbe.gruen : TafelFarbe.zweit).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Code kopieren")
        .accessibilityIdentifier("code-kopieren")
    }
}

struct BildBlockView: View {
    var alt: String
    var src: String
    var von = "von Seneca"
    @State private var bild: NSImage?
    @Environment(\.bildBuehne) private var buehne
    @Environment(\.bildZeit) private var zeit

    private var dateiPfad: String? { DateiErkennung.pfad(aus: src) }

    var body: some View {
        Group {
            if let bild {
                Image(nsImage: bild).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 188, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .fixedSize()
                    .onTapGesture { buehne?.offen = src }
                    .onAppear { buehne?.melde(.init(id: src, bild: bild, titel: alt.isEmpty ? (src as NSString).lastPathComponent : alt, herkunft: von + (zeit.map { " · " + Formate.hhmm($0) } ?? ""))) }
                    .accessibilityLabel(alt.isEmpty ? "Bild" : alt)
                    .accessibilityAddTraits(.isButton)
            } else {
                Label(alt.isEmpty ? "Bild nicht gefunden" : alt, systemImage: "photo")
                    .font(Schrift.grotesk(12.5)).foregroundStyle(TafelFarbe.leise)
            }
        }
        .task { lade() }
    }

    private func lade() {
        guard bild == nil else { return }
        if let pfad = dateiPfad { bild = NSImage(contentsOfFile: pfad) }
        else if let url = URL(string: src), url.scheme?.hasPrefix("http") == true {
            Task.detached {
                guard let (daten, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: daten) else { return }
                await MainActor.run { bild = img }
            }
        }
    }
}

struct DateiKachelView: View {
    var pfad: String
    @State private var vorschau: NSImage?
    @State private var quickLook = false

    private var existiert: Bool { FileManager.default.fileExists(atPath: pfad) }
    private var name: String { (pfad as NSString).lastPathComponent }
    private var ordner: String { ((pfad as NSString).deletingLastPathComponent as NSString).lastPathComponent }
    private var url: URL { URL(fileURLWithPath: pfad) }

    private var endung: String { (pfad as NSString).pathExtension.lowercased() }
    private var meta: String {
        let groesse = ((try? FileManager.default.attributesOfItem(atPath: pfad)[.size]) as? Int).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let seiten = endung == "pdf" ? PDFDocument(url: url).map { "\($0.pageCount) Seiten" } : nil
        return existiert ? ([seiten, groesse].compactMap { $0 } + ["Vorschau mit Leertaste"]).joined(separator: " · ") : "nicht gefunden"
    }

    var body: some View {
        Group {
            if existiert, ["m4a", "mp3", "wav", "aac", "caf"].contains(endung) { SnTonKachel(url: url) } else { kachel }
        }
        .frame(width: 360, alignment: .leading)
        .snFlaeche(endung == "pdf" ? 12 : 14, deckkraft: 0.07)
        .task { ladeVorschau() }
        .background(DateiVorschauView(url: url, ausloesen: $quickLook))
        .contextMenu {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(!existiert)
            Button("Pfad kopieren") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pfad, forType: .string)
            }
            Button("Schnellansicht") { quickLook = true }.disabled(!existiert)
        }
        .accessibilityLabel("Datei \(name)\(existiert ? "" : ", nicht gefunden")")
        .accessibilityIdentifier("datei-kachel")
    }

    private var kachel: some View {
        Button { if existiert { AppActions.dateiOeffnen(pfad) } } label: {
            HStack(spacing: 12) {
                Group {
                    if let vorschau { Image(nsImage: vorschau).resizable().scaledToFill() }
                    else { Text(endung.uppercased()).font(Schrift.mono(8, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading) }
                }
                .frame(width: 30, height: 38).background(TafelFarbe.hex(0xE9ECF1)).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.middle)
                    Text(meta).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).opacity(existiert ? 1 : 0.6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!existiert)
    }

    private func ladeVorschau() {
        guard existiert, ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains((pfad as NSString).pathExtension.lowercased()) else { return }
        vorschau = NSImage(contentsOfFile: pfad)
    }
}

private final class DateiVorschauHelfer: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var url: URL?
    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else { super.keyDown(with: event); return }
        zeige()
    }

    func zeige() {
        window?.makeFirstResponder(self)
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }
}

private struct DateiVorschauView: NSViewRepresentable {
    var url: URL
    @Binding var ausloesen: Bool

    func makeNSView(context: Context) -> DateiVorschauHelfer {
        let v = DateiVorschauHelfer(); v.url = url; return v
    }

    func updateNSView(_ v: DateiVorschauHelfer, context: Context) {
        v.url = url
        guard ausloesen else { return }
        v.zeige()
        DispatchQueue.main.async { ausloesen = false }
    }
}

struct EntwurfKarteView: View {
    var entwurf: Entwurf
    @State private var kopiert = false

    private var mailtoURL: URL? {
        var teile: [String] = []
        if let b = entwurf.betreff { teile.append("subject=" + (b.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) }
        teile.append("body=" + (entwurf.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        let empfaenger = entwurf.empfaenger?.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "/?@&=").inverted) ?? ""
        return URL(string: "mailto:\(empfaenger)?" + teile.joined(separator: "&"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "envelope").font(.system(size: 12)).foregroundStyle(Farbe.himmel)
                Text("Entwurf").font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink3)
                Spacer()
                HStack(spacing: 14) {
                    Button(kopiert ? "Kopiert" : "Kopieren") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entwurf.text, forType: .string)
                        kopiert = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { kopiert = false }
                    }
                    if let mailtoURL { Button("In Mail öffnen") { NSWorkspace.shared.open(mailtoURL) } }
                }
                .buttonStyle(.plain).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel)
            }
            if let betreff = entwurf.betreff {
                Text(betreff).font(Schrift.serif(19)).foregroundStyle(Farbe.ink1)
            }
            if let empfaenger = entwurf.empfaenger {
                Text("An \(empfaenger)").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
            Text(entwurf.text).font(Schrift.grotesk(14, .light)).foregroundStyle(Farbe.ink).lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .accessibilityIdentifier("entwurf-karte")
    }
}

struct SnTonKachel: View {
    var url: URL
    @State private var spieler: AVAudioPlayer?
    @State private var dauer: Double = 0
    private static let balken: [CGFloat] = [6, 12, 18, 10, 20, 14, 8, 16, 22, 12, 6, 14, 18, 10, 8, 12, 16, 6, 10, 14]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let anteil = dauer > 0 ? (spieler?.currentTime ?? 0) / dauer : 0
            HStack(spacing: 12) {
                Button {
                    if spieler == nil { spieler = try? AVAudioPlayer(contentsOf: url) }
                    if spieler?.isPlaying == true { spieler?.pause() } else { spieler?.play() }
                } label: {
                    Image(systemName: spieler?.isPlaying == true ? "pause.fill" : "play.fill").font(.system(size: 13)).foregroundStyle(TafelFarbe.aufHimmel)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                HStack(spacing: 2) {
                    ForEach(Array(Self.balken.enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(Double(i) / Double(Self.balken.count) < max(anteil, 0.45) ? 0.7 : 0.25)).frame(width: 3, height: h)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(VerlaufLogik.uhrDauer(dauer)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.zweit).monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .task { dauer = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0 }
    }
}
