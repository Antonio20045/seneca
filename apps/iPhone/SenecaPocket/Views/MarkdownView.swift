import SwiftUI

enum AntwortFarbe {
    static let tinte = Stil.tinte.voll
    static let link = Stil.farbe.himmel
}

struct MDStil {
    var art: String
    var groesse: CGFloat
    var normal: Font
    var fett: Font
    var kursiv: Font
    var code: Font
    var farbe: Color
    var zeilenabstand: CGFloat

    static let fettText = Sundartha.grotesk(Stil.Schrift.text.groesse, .medium)
    static let codeSchrift = Font.system(.subheadline, design: .monospaced)

    static func fuer(_ kind: MDBlock.Kind, art: String) -> MDStil {
        let text = Stil.Schrift.text
        switch kind {
        case .heading(let level, _):
            if level <= 2 {
                let s = Stil.Schrift.sache
                return MDStil(art: art, groesse: s.groesse, normal: s.font, fett: s.font, kursiv: s.kursiv, code: codeSchrift,
                              farbe: Stil.tinte.voll, zeilenabstand: Stil.abstand.xs)
            }
            return MDStil(art: art, groesse: text.groesse, normal: fettText, fett: fettText, kursiv: text.kursiv, code: codeSchrift,
                          farbe: Stil.tinte.voll, zeilenabstand: text.zeilenAbstand)
        case .quote:
            return MDStil(art: art, groesse: text.groesse, normal: text.font, fett: fettText, kursiv: text.kursiv, code: codeSchrift,
                          farbe: Stil.tinte.zweit, zeilenabstand: text.zeilenAbstand)
        case .code:
            return MDStil(art: art, groesse: text.groesse, normal: codeSchrift, fett: codeSchrift, kursiv: codeSchrift, code: codeSchrift,
                          farbe: Stil.tinte.voll, zeilenabstand: Stil.abstand.xs)
        case .paragraph, .item, .rule:
            return MDStil(art: art, groesse: text.groesse, normal: text.font, fett: fettText, kursiv: text.kursiv, code: codeSchrift,
                          farbe: Stil.tinte.voll, zeilenabstand: text.zeilenAbstand)
        }
    }

    func gestalte(_ text: String) -> AttributedString {
        var a = MDInline.attributed(text)
        for run in a.runs {
            let intent = run.inlinePresentationIntent ?? []
            let font: Font
            if intent.contains(.code) { font = code }
            else if intent.contains(.emphasized) { font = kursiv }
            else if intent.contains(.stronglyEmphasized) { font = fett }
            else { font = normal }
            a[run.range].font = font
            a[run.range].foregroundColor = farbe
            if intent.contains(.strikethrough) { a[run.range].strikethroughStyle = .single }
            if intent.contains(.code) { a[run.range].backgroundColor = Stil.tinte.flaecheStark }
            if run.link != nil {
                a[run.range].underlineStyle = .single
                a[run.range].foregroundColor = AntwortFarbe.link
            }
        }
        return a
    }

    func abgeblendet(_ original: AttributedString, frisch: FrischSpanne) -> AttributedString {
        guard !frisch.istKeine else { return original }
        var a = original
        let n = a.characters.count
        let neu = min(frisch.neu, n)
        let alt = min(frisch.alt, n - neu)
        func faerbe(vomEnde von: Int, bisZumEnde bis: Int, faktor: Double) {
            guard bis > von else { return }
            let ende = a.index(a.endIndex, offsetByCharacters: -von)
            let anfang = a.index(a.endIndex, offsetByCharacters: -bis)
            let teile = a[anfang..<ende].runs.map { ($0.range, $0.link != nil) }
            for (bereich, istLink) in teile {
                a[bereich].foregroundColor = (istLink ? AntwortFarbe.link : farbe).opacity(faktor)
            }
        }
        faerbe(vomEnde: 0, bisZumEnde: neu, faktor: FrischSpanne.stufeNeu)
        faerbe(vomEnde: neu, bisZumEnde: neu + alt, faktor: FrischSpanne.stufeAlt)
        return a
    }
}

final class MDStilCache: @unchecked Sendable {
    static let shared = MDStilCache()
    private let lock = NSLock()
    private var gestaltet: [MDCacheSchluessel: AttributedString] = [:]
    private var zerlegt: [String: [MDBlock]] = [:]

    func attributed(_ schluessel: MDCacheSchluessel, bau: () -> AttributedString) -> AttributedString {
        lock.lock(); let treffer = gestaltet[schluessel]; lock.unlock()
        if let treffer { return treffer }
        let neu = bau()
        lock.lock()
        if gestaltet.count > 400 { gestaltet.removeAll(keepingCapacity: true) }
        gestaltet[schluessel] = neu
        lock.unlock()
        return neu
    }

    func bloecke(fertig text: String) -> [MDBlock] {
        lock.lock(); let treffer = zerlegt[text]; lock.unlock()
        if let treffer { return treffer }
        let neu = MDParser.parse(text, live: false)
        lock.lock()
        if zerlegt.count > 40 { zerlegt.removeAll(keepingCapacity: true) }
        zerlegt[text] = neu
        lock.unlock()
        return neu
    }
}

struct FadenMarkdown: View {
    var text: String
    var live: Bool
    var m: Metrics? = nil
    var frisch: FrischSpanne = .keine
    var sprecher: String? = nil
    var ansage: String? = nil

    var body: some View {
        let blocks = live ? MDParser.parse(text, live: true) : MDStilCache.shared.bloecke(fertig: text)
        let letzte = blocks.last?.id
        let oben = Self.abstaende(blocks)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks, id: \.id) { block in
                let istLetzter = block.id == letzte
                MDBlockView(block: block, live: live && istLetzter, oben: block.id < oben.count ? oben[block.id] : 0,
                            frisch: live && istLetzter ? frisch : .keine,
                            sprecher: block.id == 0 ? sprecher : nil)
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(ansagen)
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ansage ?? "")
                .accessibilityHidden(!ansagen)
        }
    }

    private var ansagen: Bool { live && ansage != nil }

    static func abstaende(_ blocks: [MDBlock]) -> [CGFloat] {
        let a = Stil.abstand
        return blocks.enumerated().map { i, b in
            guard i > 0 else { return 0 }
            let davor = blocks[i - 1].kind
            switch (davor, b.kind) {
            case (.rule, _), (_, .rule): return a.l
            case (.heading, .heading): return a.s
            case (.heading, _): return a.s
            case (_, .heading): return a.xl
            case (.item, .item(let d, _, _)): return d > 0 ? a.xs : a.s
            default: return a.m
            }
        }
    }
}

struct MDBlockView: View, Equatable {
    var block: MDBlock
    var live: Bool
    var oben: CGFloat
    var frisch: FrischSpanne
    var sprecher: String?

    static func == (l: MDBlockView, r: MDBlockView) -> Bool {
        l.block == r.block && l.live == r.live && l.oben == r.oben && l.frisch == r.frisch && l.sprecher == r.sprecher
    }
    @Environment(\.appActions) private var actions
    @State private var datei: DateiRueckmeldung?

    private var hatLink: Bool {
        if case .code = block.kind { return false }
        return block.text.contains("](")
    }

    var body: some View {
        let dateiOeffnen = actions.dateiOeffnen
        let fest = inhalt
            .padding(.top, oben)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(!live)
        Group {
            if hatLink { fest.textSelection(.disabled) } else { fest.textSelection(.enabled) }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let pfad = MDLink.dateiPfad(aus: url) {
                if datei == nil { dateiAntippen(url, pfad: pfad, oeffnen: dateiOeffnen) }
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder private var inhalt: some View {
        let stil = MDStil.fuer(block.kind, art: block.art)
        switch block.kind {
        case .paragraph:
            fliesstext(stil)
        case .heading:
            fliesstext(stil).accessibilityAddTraits(.isHeader)
        case .item(let depth, let marker, _):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                markierung(marker, stil: stil)
                fliesstext(stil)
            }
            .padding(.leading, CGFloat(depth) * Stil.abstand.xl)
        case .quote:
            fliesstext(stil)
                .padding(.leading, Stil.abstand.m)
                .overlay(alignment: .leading) {
                    Capsule().fill(Stil.tinte.leise).frame(width: 2)
                }
        case .code(let lang, let code):
            if lang?.lowercased() == "seneca", let karte = SenecaKarte.parse(code) {
                SenecaKarteView(karte: karte, farbe: .tinte)
            } else {
                Text(verbatim: code)
                    .font(stil.normal)
                    .foregroundStyle(stil.farbe)
                    .lineSpacing(stil.zeilenabstand)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Stil.abstand.m)
                    .background(RoundedRectangle(cornerRadius: Stil.radius.klein, style: .continuous).fill(Stil.tinte.flaeche))
            }
        case .rule:
            Rectangle().fill(Stil.tinte.linie).frame(height: 1).accessibilityHidden(true)
        }
    }

    private func attributed(_ stil: MDStil) -> AttributedString {
        let roh = block.text
        let text = live ? MDInline.schliesse(roh) : roh
        let schluessel = MDCacheSchluessel(id: block.id, text: text, art: stil.art, groesse: Double(stil.groesse))
        let a = MDStilCache.shared.attributed(schluessel) { stil.gestalte(text) }
        return live ? stil.abgeblendet(a, frisch: frisch) : a
    }

    private func dateiAntippen(_ url: URL, pfad: String, oeffnen: @escaping (String) async -> String?) {
        datei = DateiRueckmeldung(url: url, satz: nil)
        Task { @MainActor in
            if let fehler = await oeffnen(pfad) {
                datei = DateiRueckmeldung(url: url, satz: fehler)
                try? await Task.sleep(for: .seconds(3))
            }
            datei = nil
        }
    }

    private func rueckmeldung(_ original: AttributedString, _ stil: MDStil) -> AttributedString {
        guard let datei else { return original }
        let bereiche = original.runs.filter { $0.link == datei.url }.map(\.range)
        guard let letzter = bereiche.last else { return original }
        var a = original
        for b in bereiche { a[b].foregroundColor = Stil.tinte.leise }
        if let satz = datei.satz {
            var zusatz = AttributedString(" – " + satz)
            zusatz.font = stil.normal
            zusatz.foregroundColor = Stil.tinte.zweit
            a.insert(zusatz, at: letzter.upperBound)
        }
        return a
    }

    @ViewBuilder private func fliesstext(_ stil: MDStil) -> some View {
        let a = rueckmeldung(attributed(stil), stil)
        let text = Text(a)
            .font(stil.normal)
            .lineSpacing(stil.zeilenabstand)
            .tint(AntwortFarbe.link)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let sprecher, !a.runs.contains(where: { $0.link != nil }) {
            text.accessibilityLabel("\(sprecher): \(block.klartext)")
        } else {
            text
        }
    }

    @ViewBuilder private func markierung(_ marker: MDBlock.Marker, stil: MDStil) -> some View {
        switch marker {
        case .bullet:
            Circle()
                .fill(Stil.tinte.leise)
                .frame(width: 5, height: 5)
                .padding(.leading, Stil.abstand.xs)
                .frame(width: Stil.abstand.xl, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 2.5 }
                .accessibilityHidden(true)
        case .number(let n):
            Text("\(n).")
                .font(stil.normal)
                .foregroundStyle(Stil.tinte.zweit)
                .frame(width: Stil.abstand.xl + Stil.abstand.xs, alignment: .leading)
        }
    }
}

struct DateiRueckmeldung: Equatable {
    var url: URL
    var satz: String?
}
