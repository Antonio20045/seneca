import SwiftUI
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
                            case .code(let t): CodeBlockView(code: t, live: live)
                            case .table(let header, let rows): TabelleView(header: header, rows: rows)
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
    case code(String)
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
                    case .code(_, let s): return .code(s)
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
            }
            out.append(NSAttributedString(string: stueck, attributes: attrs))
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
                case .number(let n): praefix = "\(n).  "
                case .check(let an):
                    praefix = an ? "☑  " : "☐  "
                    praefixFarbe = an ? NSColor(Farbe.gruen) : NSColor(Farbe.ink3)
                }
                let s = NSMutableAttributedString(string: praefix, attributes: [.font: nsGrotesk(.light, 15), .foregroundColor: praefixFarbe])
                s.append(inlineNS(t, basis: nsGrotesk(.regular, 15), farbe: NSColor(TafelFarbe.zweit)))
                if case .check(true) = marker { s.addAttribute(.strikethroughStyle, value: 0, range: NSRange(location: 0, length: s.length)) }
                stueck = s
                para.headIndent = CGFloat(depth) * 18 + 22
                para.firstLineHeadIndent = CGFloat(depth) * 18 + 4
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
    var live: Bool
    @State private var offen = false
    @State private var ueber = false
    @State private var kopiert = false

    var body: some View {
        let langStr = CodeFalte.eingeklappt(code) && !live
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if langStr {
                    Button { withAnimation(Kurve.ease(0.25)) { offen.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(offen ? 90 : 0))
                            Text("Code · \(CodeFalte.zeilen(code)) Zeilen")
                        }
                        .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("code-falte")
                } else {
                    Spacer(minLength: 0)
                }
                kopierKnopf
            }
            if !langStr || offen {
                Text(code).font(Schrift.mono(13)).foregroundStyle(Farbe.ink)
                    .textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { ueber = $0 }
    }

    private var kopierKnopf: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            kopiert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { kopiert = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kopiert ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .medium))
                if kopiert { Text("Kopiert").font(Schrift.grotesk(11.5)) }
            }
            .foregroundStyle(kopiert ? Farbe.gruen : Farbe.ink3)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(ueber || kopiert ? 1 : 0.55)
        .accessibilityLabel("Code kopieren")
        .accessibilityIdentifier("code-kopieren")
    }
}

struct TabelleView: View {
    var header: [String]
    var rows: [[String]]

    var body: some View {
        let spalten = header.count
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                    Text(MDInline.attributed(h)).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink2)
                }
            }
            Divider().overlay(Farbe.linie).gridCellColumns(max(spalten, 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, zeile in
                GridRow {
                    ForEach(0..<spalten, id: \.self) { i in
                        Text(MDInline.attributed(i < zeile.count ? zeile[i] : "")).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .accessibilityIdentifier("antwort-tabelle")
    }
}

struct BildBlockView: View {
    var alt: String
    var src: String
    @State private var bild: NSImage?
    @State private var gross = false

    private var dateiPfad: String? { DateiErkennung.pfad(aus: src) }

    var body: some View {
        Group {
            if let bild {
                Image(nsImage: bild).resizable().scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
                    .onTapGesture { gross = true }
                    .accessibilityLabel(alt.isEmpty ? "Bild" : alt)
                    .accessibilityAddTraits(.isButton)
            } else {
                Label(alt.isEmpty ? "Bild nicht gefunden" : alt, systemImage: "photo")
                    .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink4)
            }
        }
        .task { lade() }
        .sheet(isPresented: $gross) {
            VStack(spacing: 0) {
                if let bild { Image(nsImage: bild).resizable().scaledToFit() }
                Button("Schließen") { gross = false }.buttonStyle(NebenKnopfStil()).padding(14)
            }
            .frame(minWidth: 420, minHeight: 320)
            .background(Farbe.grund)
        }
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

    var body: some View {
        Button { if existiert { AppActions.dateiOeffnen(pfad) } } label: {
            HStack(spacing: 10) {
                Group {
                    if let vorschau { Image(nsImage: vorschau).resizable().scaledToFill() }
                    else { Image(systemName: SnAnhangSymbol.name(fuer: (pfad as NSString).pathExtension)).font(.system(size: 17)).foregroundStyle(Farbe.himmel) }
                }
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(Schrift.grotesk(13, .medium)).foregroundStyle(Farbe.ink).lineLimit(1).truncationMode(.middle)
                    Text(existiert ? ordner : "nicht gefunden").font(Schrift.grotesk(12)).foregroundStyle(existiert ? Farbe.ink3 : Farbe.ink4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
            .opacity(existiert ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!existiert)
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
