import SwiftUI

struct ReadingView: View {
    var m: Metrics
    var doc: ReadingDocument
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var leaving = false
    @State private var offset: CGSize = .zero
    @State private var faded = false
    @State private var pull: CGFloat = 0

    private var textWidth: CGFloat { min(m.size.width - 2 * Stil.rand, 520) }
    private var blocks: [ReadingBlock] { doc.format == .bericht ? ReadingBlock.parse(doc.body) : [] }
    static let pullToClose: CGFloat = 45

    private var rueckWort: String {
        if doc.id.hasPrefix("bericht-") { return "Berichte" }
        if doc.id.hasPrefix("datei-") { return "Chat" }
        return "Heute"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            Seite(zurueck: rueckWort, scrollt: false, beimZurueck: dismiss) {
                scroll.weicheKante()
            }
        }
        .frame(width: m.size.width, height: m.size.height)
        .offset(reduceMotion ? .zero : offset)
        .opacity(reduceMotion && faded ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reading")
        .accessibilityAction(.escape) { dismiss() }
        .accessibilityAction(named: "Schließen") { dismiss() }
        .onAppear {
            if reduceMotion { shown = true; return }
            offset = CGSize(width: 0, height: m.size.height + 180)
            Bewegung.mit(.blatt) { offset = .zero }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                shown = true
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Stil.farbe.grund
            LightField.softLight(metrics: m)
                .scaleEffect(0.95)
                .opacity(0.72)
                .position(x: m.size.width * 0.28, y: m.size.height * 0.55)
            BottomShade()
        }
        .frame(width: m.size.width, height: m.size.height)
        .clipped()
        .overlay(alignment: .top) {
            LinearGradient(colors: [Sundartha.base.opacity(0), Sundartha.base], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
                .offset(y: -180)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    private func dismiss() {
        guard !leaving else { return }
        leaving = true
        if reduceMotion {
            Bewegung.mit(.klein) { faded = true }
        } else {
            Bewegung.mit(.blatt) { offset = CGSize(width: 0, height: m.size.height + 180) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 380))
            close()
        }
    }

    private var scroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(doc.kicker)
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .rise(shown, 0, reduceMotion: reduceMotion)
                title
                    .padding(.top, Stil.abstand.s)
                    .rise(shown, 0.06, reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 0) {
                    switch doc.format {
                    case .bericht:
                        if blocks.isEmpty {
                            Text("Mehr steht in diesem Bericht nicht.")
                                .schrift(.text)
                                .foregroundStyle(Stil.tinte.zweit)
                        }
                        ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                            blockView(block)
                                .padding(.top, i == 0 ? 0 : block.spaceAbove)
                                .rise(shown, 0.18 + 0.06 * Double(min(i, 6)), reduceMotion: reduceMotion)
                        }
                    case .markdown:
                        FadenMarkdown(text: doc.body, live: false, m: m)
                            .rise(shown, 0.18, reduceMotion: reduceMotion)
                    case .text:
                        Text(verbatim: doc.body)
                            .schrift(.zeile)
                            .foregroundStyle(Stil.tinte.voll)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .rise(shown, 0.18, reduceMotion: reduceMotion)
                    }
                }
                .padding(.top, Stil.abstand.xl)
                .accessibilityIdentifier("reading.body")
                if let ziel = doc.bewertung, doc.format == .bericht {
                    BewertungsKnoepfe(ziel: ziel)
                        .padding(.top, Stil.abstand.xxl)
                        .rise(shown, 0.4, reduceMotion: reduceMotion)
                }
            }
            .frame(width: textWidth, alignment: .leading)
            .padding(.leading, Stil.rand)
            .padding(.top, Stil.abstand.l)
            .padding(.bottom, Stil.fensterRaender.bottom + Stil.abstand.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) { PullReader(pull: $pull) }
        }
        .coordinateSpace(.named(PullReader.space))
        .modifier(PullToClose(pull: $pull, threshold: Self.pullToClose, close: dismiss))
    }

    private var title: some View {
        ReadingBlock.segments(doc.title).reduce(Text("")) { satz, teil in
            satz + Text(teil.text).font(teil.kursiv ? Stil.Schrift.gross.kursiv : Stil.Schrift.gross.font)
        }
        .kerning(Stil.Schrift.gross.sperrung)
        .foregroundStyle(Stil.tinte.voll)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(doc.title.replacingOccurrences(of: "*", with: ""))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("reading.title")
    }

    @ViewBuilder
    private func blockView(_ block: ReadingBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Group {
                if level <= 2 {
                    let font = (level == 1 ? Stil.Schrift.titel : Stil.Schrift.sache).font
                    ReadingBlock.inline(text, base: font, bold: font)
                        .foregroundStyle(Stil.tinte.voll)
                } else {
                    let font = Stil.Schrift.zeileWichtig.font
                    ReadingBlock.inline(text, base: font, bold: font)
                        .foregroundStyle(Stil.tinte.voll)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            paragraph(text)
        case .karte(let karte):
            SenecaKarteView(karte: karte, farbe: .weiss, k: m.f(1))
        case .quote(let text):
            paragraph(text)
                .padding(.leading, Stil.abstand.l)
                .overlay(alignment: .leading) { Rectangle().fill(Stil.tinte.leise).frame(width: 1) }
        case .list(let items, let numbered):
            VStack(alignment: .leading, spacing: Stil.abstand.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(numbered ? "\(i + 1)." : "–")
                            .schrift(.text)
                            .monospacedDigit()
                            .foregroundStyle(Stil.tinte.zweit)
                            .frame(width: 22, alignment: .leading)
                        paragraph(item)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        ReadingBlock.inline(text, base: Stil.Schrift.text.font, bold: Stil.Schrift.text.font.weight(.medium))
            .foregroundStyle(Stil.tinte.voll)
            .lineSpacing(Stil.Schrift.text.zeilenAbstand)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func rise(_ shown: Bool, _ delay: Double, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Stil.abstand.l)
            .animation(reduceMotion ? Bewegung.klein.kurve : Bewegung.blatt.kurve.delay(delay), value: shown)
    }

}

private struct PullReader: View {
    static let space = "reading.scroll"
    @Binding var pull: CGFloat
    var body: some View {
        if #available(iOS 18.0, *) {
            Color.clear
        } else {
            GeometryReader { g in
                Color.clear
                    .onChange(of: g.frame(in: .named(Self.space)).minY) { _, y in pull = max(0, y) }
            }
        }
    }
}

private struct PullToClose: ViewModifier {
    @Binding var pull: CGFloat
    var threshold: CGFloat
    var close: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { g in max(0, -(g.contentOffset.y + g.contentInsets.top)) } action: { _, new in
                    pull = new
                }
                .onScrollPhaseChange { old, new in
                    if old == .interacting && new != .interacting && pull >= threshold { close() }
                }
        } else {
            content.onChange(of: pull) { _, p in if p >= threshold * 1.3 { close() } }
        }
    }
}

enum ReadingBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case list(items: [String], numbered: Bool)
    case karte(SenecaKarte)

    static func parse(_ text: String) -> [ReadingBlock] {
        var blocks: [ReadingBlock] = []
        var paragraph: [String] = []
        var items: [String] = []
        var numbered = false
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items: items, numbered: numbered)); items = [] }
        }
        let zeilen = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = -1
        while i + 1 < zeilen.count {
            i += 1
            let raw = zeilen[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased() == "```seneca",
               let ende = zeilen[(i + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```" }),
               let karte = SenecaKarte.parse(zeilen[(i + 1)..<ende].joined(separator: "\n")) {
                flushParagraph(); flushList()
                blocks.append(.karte(karte))
                i = ende
                continue
            }
            if line.isEmpty { flushParagraph(); flushList(); continue }
            if line.hasPrefix("#") {
                flushParagraph(); flushList()
                let level = line.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level: min(level, 3), text: line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                if items.isEmpty { numbered = item.numbered }
                items.append(item.text)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph(); flushList()
                blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
                continue
            }
            if !items.isEmpty, raw.hasPrefix("  ") {
                items[items.count - 1] += " " + line
                continue
            }
            flushList()
            paragraph.append(line)
        }
        flushParagraph(); flushList()
        return blocks
    }

    private static func listItem(_ line: String) -> (text: String, numbered: Bool)? {
        for bullet in ["- ", "* ", "• ", "– "] where line.hasPrefix(bullet) {
            return (String(line.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces), false)
        }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 2 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return (rest.dropFirst(2).trimmingCharacters(in: .whitespaces), true) }
        }
        return nil
    }

    var spaceAbove: CGFloat {
        switch self {
        case .heading(let level, _): return level <= 2 ? Stil.abstand.xxl : Stil.abstand.xl
        case .paragraph, .quote, .list: return Stil.abstand.l
        case .karte: return Stil.abstand.xl
        }
    }

    static func inline(_ text: String, base: Font, bold: Font) -> Text {
        guard var attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return Text(text).font(base)
        }
        for run in attributed.runs {
            let strong = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            attributed[run.range].font = strong ? bold : base
        }
        return Text(attributed)
    }

    static func segments(_ title: String) -> [(text: String, kursiv: Bool)] {
        var out: [(text: String, kursiv: Bool)] = []
        for (i, part) in title.components(separatedBy: "*").enumerated() where !part.isEmpty {
            out.append((part, i % 2 == 1))
        }
        return out.isEmpty ? [(title, false)] : out
    }
}

#if DEBUG
extension ReadingDocument {
    static let demo = ReadingDocument(
        id: "demo-lesen", kicker: "Abendbericht · heute, 19:00 Uhr", title: "Ein ruhiger, *guter* Tag",
        body: """
        Du hast heute fast alles erledigt, und die Morgenroutine hat wieder gut geklappt. Das war ein ruhiger, runder Tag.

        ## Was gelaufen ist

        - Die Datenbank ist abgesichert; der alte Zugang ist geschlossen.
        - Die Rufnummern-Prüfung bei Vodafone läuft wieder und meldet keine Fehler mehr.
        - Der Sundartha-Agent hat drei neue Ideen für die Preisseite gesammelt.

        ## Was morgen wartet

        Um 10 Uhr steht der Kaffee mit Lena an. Danach ist der Vormittag frei, und ich würde dir eine halbe Stunde für die Website-Texte einplanen, weil der Entwurf seit gestern bereitliegt und die Änderungen klein sind.

        1. Website-Texte freigeben
        2. Zugang für die Rufnummern-Prüfung bestätigen
        3. Steuerunterlagen sortieren

        ### Ideenlauf Sundartha

        Zwei der drei Ideen betreffen die Preisseite, eine den Newsletter. Ich würde mit der **Preisseite** beginnen, weil dort die meisten Besucher abspringen. Der Newsletter kann bis Donnerstag warten, denn die nächste Ausgabe geht erst am Freitag hinaus.

        > Weniger, aber besser.

        Schlaf gut. Morgen früh um 7:30 Uhr kommt das Briefing wie gewohnt.
        """)
}
#endif

private struct BewertungsKnoepfe: View {
    var ziel: BerichtBewertung
    @EnvironmentObject private var store: SenecaStore
    @State private var laeuft = false
    @State private var urteil: Bool?
    @State private var meldung = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            HStack(spacing: Stil.abstand.s) {
                knopf("Passt", passt: true)
                knopf("Passt nicht", passt: false)
            }
            if !meldung.isEmpty {
                Text(meldung).schrift(.klein).foregroundStyle(Stil.tinte.zweit)
                    .accessibilityIdentifier("reading.bewertung.meldung")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func knopf(_ titel: String, passt: Bool) -> some View {
        let gewaehlt = urteil == passt
        return Button(titel) { senden(passt) }
            .buttonStyle(KapselStil(art: gewaehlt ? .haupt : .zweit))
            .disabled(laeuft)
            .accessibilityIdentifier(passt ? "reading.passt" : "reading.passtNicht")
            .accessibilityAddTraits(gewaehlt ? .isSelected : [])
    }

    private func senden(_ passt: Bool) {
        guard !laeuft else { return }
        laeuft = true
        Haptik.tipp()
        Task { @MainActor in
            defer { laeuft = false }
            do {
                _ = try await store.rufe("seneca.bewerten", params: ziel.params(passt, quelle: "app"), timeout: 15)
                urteil = passt
                meldung = passt ? "Danke, „Passt“ ist notiert." : "Danke, „Passt nicht“ ist notiert."
            } catch {
                meldung = "Die Bewertung ging nicht durch. Versuch es gleich noch einmal."
            }
        }
    }
}
