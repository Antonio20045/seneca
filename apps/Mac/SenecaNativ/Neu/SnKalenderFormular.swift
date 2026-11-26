import SwiftUI
import AppKit

struct SnKalFormular: View {
    @ObservedObject var k: SnKalenderSpeicher
    @FocusState private var fokus: Feld?
    @State private var datumOffen: Int?
    @State private var notizHoehe: CGFloat = 80

    private enum Feld { case titel, ort }

    var body: some View {
        let form = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let inhalt = VStack(alignment: .leading, spacing: 0) {
            if let q = k.entwurf {
                if let o = k.original, !o.aenderbar { nurLesen(o) } else { felder(q) }
            }
        }
        .padding(20)
        ViewThatFits(in: .vertical) {
            inhalt
            ScrollView(.vertical, showsIndicators: false) { inhalt }
        }
        .background(form.fill(Color.white.opacity(0.055)))
        .overlay(form.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(form)
        .frame(maxHeight: .infinity, alignment: .top)
        .onExitCommand { k.schliesse() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(k.original == nil ? "Neuer Termin" : "Termin")
        .accessibilityIdentifier("kalender-formular")
    }

    private func bind<W>(_ pfad: WritableKeyPath<KalEntwurf, W>, _ leer: W) -> Binding<W> {
        Binding(get: { k.entwurf?[keyPath: pfad] ?? leer }, set: { k.entwurf?[keyPath: pfad] = $0 })
    }

    @ViewBuilder private func felder(_ q: KalEntwurf) -> some View {
        let neu = k.original == nil
        HStack {
            Text(neu ? "Neuer Termin" : (k.original?.serie == true ? "Termin einer Serie · nur dieser Tag" : "Termin"))
                .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            Spacer()
            SnKalMiniKnopf(symbol: "xmark", name: "Schließen") { k.schliesse(verwerfen: neu) }
        }
        TextField("", text: bind(\.titel, ""), prompt: Text("Titel").foregroundColor(Farbe.ink4), axis: .vertical)
            .textFieldStyle(.plain).font(Schrift.grotesk(20, .medium)).foregroundStyle(Color.white).lineLimit(1...3)
            .focused($fokus, equals: .titel)
            .onSubmit { k.sichere() }
            .padding(.top, 6)
            .accessibilityLabel("Titel")
            .onAppear { if neu { fokus = .titel } }
        trenner
        zeit(q)
        if k.kannAendern {
            if k.kalender.contains(where: \.schreibbar) {
                trenner
                zeile("calendar") { kalenderWahl(q) }
            }
            trenner
            zeile("mappin.and.ellipse") {
                TextField("", text: bind(\.ort, ""), prompt: Text("Ort").foregroundColor(Farbe.ink4))
                    .textFieldStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1)
                    .focused($fokus, equals: .ort)
                    .accessibilityLabel("Ort")
            }
            trenner
            zeile("text.alignleft", oben: true) {
                SnKalNotizFeld(text: bind(\.notiz, ""), hoehe: $notizHoehe, escape: { k.schliesse() })
                    .frame(height: notizHoehe)
                    .overlay(alignment: .topLeading) {
                        if q.notiz.isEmpty { Text("Notizen").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink4).allowsHitTesting(false) }
                    }
                    .accessibilityLabel("Notizen")
            }
        } else {
            Text("Ort, Notizen, Ändern und Löschen gehen, sobald Seneca direkt auf Apple Kalender zugreifen darf.")
                .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
        if let m = q.mangel ?? k.meldung {
            Text(m).font(Schrift.grotesk(13)).foregroundStyle(Farbe.warnText).padding(.top, 14)
        }
        HStack(spacing: 6) {
            Button { k.sichere() } label: {
                Text(neu ? "Eintragen" : "Sichern").font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.aufWeiss)
                    .padding(.horizontal, 18).padding(.vertical, 8).background(Capsule().fill(Farbe.himmel)).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .help("⌘⏎")
            Button { k.schliesse(verwerfen: true) } label: {
                Text(neu ? "Abbrechen" : "Verwerfen").font(Schrift.grotesk(14, .medium)).padding(.vertical, 8).padding(.horizontal, 10).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            Spacer()
            if let o = k.original {
                Button { k.loesche(o) } label: {
                    Text("Löschen").font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.koralle).padding(.vertical, 8).padding(.leading, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Entf")
            }
        }
        .padding(.top, 20)
    }

    private var trenner: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.vertical, 12) }

    private func zeile<I: View>(_ symbol: String, oben: Bool = false, @ViewBuilder _ inhalt: () -> I) -> some View {
        HStack(alignment: oben ? .top : .center, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Farbe.ink3).frame(width: 18, height: 20)
            inhalt().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func zeit(_ q: KalEntwurf) -> some View {
        let cal = k.cal
        zeile("clock", oben: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SnKalWert(text: KalRaster.tagKurz(q.start, cal), an: datumOffen == 0) { datumOffen = datumOffen == 0 ? nil : 0 }
                    if q.ganztags {
                        Text("bis").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                        SnKalWert(text: KalRaster.tagKurz(q.ende, cal), an: datumOffen == 1) { datumOffen = datumOffen == 1 ? nil : 1 }
                    } else {
                        SnKalZeitFeld(stunde: KalRaster.stunde(q.start, cal), name: "Beginn") { setzeStart($0) }
                        Text("–").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                        SnKalZeitFeld(stunde: KalRaster.stunde(q.ende, cal), name: "Ende") { setzeEnde($0) }
                    }
                }
                if let d = datumOffen {
                    SnKalMiniMonat(cal: cal, gewaehlt: cal.startOfDay(for: d == 0 ? q.start : q.ende), heute: cal.startOfDay(for: k.jetzt), zelle: 28) { setzeTag($0, ende: d == 1) }
                        .padding(.vertical, 4)
                }
                if !q.ganztags {
                    let minuten = Int((q.ende.timeIntervalSince(q.start) / 60).rounded())
                    HStack(spacing: 4) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                            SnKalChip(text: m < 60 ? "\(m)" : (m == 60 ? "1 h" : (m == 90 ? "1,5 h" : "2 h")), an: minuten == m) {
                                k.entwurf?.ende = q.start.addingTimeInterval(Double(m) * 60)
                            }
                            .help(KalRaster.dauer(m))
                        }
                    }
                    .accessibilityLabel("Dauer")
                }
                if k.kannAendern {
                    SnKalChip(text: "Ganztägig", an: q.ganztags, haken: true) { schalteGanztags() }
                }
            }
        }
    }

    private func setzeStart(_ h: Double) {
        guard var q = k.entwurf else { return }
        let dauer = q.ende.timeIntervalSince(q.start)
        q.start = KalRaster.zeit(q.start, stunde: h, k.cal)
        q.ende = q.start.addingTimeInterval(dauer)
        k.entwurf = q
    }

    private func setzeEnde(_ h: Double) {
        guard var q = k.entwurf else { return }
        var e = KalRaster.zeit(q.start, stunde: h, k.cal)
        if e <= q.start { e = KalRaster.zeit(k.cal.date(byAdding: .day, value: 1, to: q.start)!, stunde: h, k.cal) }
        q.ende = e
        k.entwurf = q
    }

    private func setzeTag(_ tag: Date, ende: Bool) {
        guard var q = k.entwurf else { return }
        let cal = k.cal
        if ende {
            q.ende = max(cal.startOfDay(for: q.start), tag).addingTimeInterval(86_399)
        } else if q.ganztags {
            let tage = cal.dateComponents([.day], from: cal.startOfDay(for: q.start), to: cal.startOfDay(for: q.ende)).day ?? 0
            q.start = tag
            q.ende = cal.date(byAdding: .day, value: tage, to: tag)!.addingTimeInterval(86_399)
        } else {
            let dauer = q.ende.timeIntervalSince(q.start)
            q.start = KalRaster.zeit(tag, stunde: KalRaster.stunde(q.start, cal), cal)
            q.ende = q.start.addingTimeInterval(dauer)
        }
        k.entwurf = q
        datumOffen = nil
    }

    private func schalteGanztags() {
        guard var q = k.entwurf else { return }
        let tag = k.cal.startOfDay(for: q.start)
        q.ganztags.toggle()
        if q.ganztags { q.start = tag; q.ende = tag.addingTimeInterval(86_399) }
        else { q.start = KalRaster.zeit(tag, stunde: 9, k.cal); q.ende = KalRaster.zeit(tag, stunde: 10, k.cal) }
        k.entwurf = q
        datumOffen = nil
    }

    private func kalenderWahl(_ q: KalEntwurf) -> some View {
        let gewaehlt = k.kalender.first { $0.id == q.kalenderId }
        return Menu {
            ForEach(k.kalender.filter(\.schreibbar)) { kal in
                Button(kal.name) { k.entwurf?.kalenderId = kal.id }
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.kal(gewaehlt?.farbe)).frame(width: 8, height: 8)
                Text(gewaehlt?.name ?? "Kalender").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Farbe.ink3)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Kalender")
    }

    @ViewBuilder private func nurLesen(_ e: KalEreignis) -> some View {
        let cal = k.cal
        HStack {
            Text("Termin").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            Spacer()
            SnKalMiniKnopf(symbol: "xmark", name: "Schließen") { k.schliesse() }
        }
        Text(e.titel).font(Schrift.grotesk(20, .medium)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            .textSelection(.enabled)
        trenner
        zeile("clock") {
            Text(e.ganztags
                 ? KalRaster.tagKurz(e.start, cal) + (KalRaster.letzterTag(e, cal) > cal.startOfDay(for: e.start) ? " bis \(KalRaster.tagKurz(KalRaster.letzterTag(e, cal), cal))" : "") + " · ganztägig"
                 : "\(KalRaster.tagKurz(e.start, cal)) · \(KalRaster.uhr(e.start, cal)) – \(KalRaster.uhr(e.ende, cal))")
                .font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1)
        }
        if let n = e.kalender {
            trenner
            zeile("calendar") {
                HStack(spacing: 8) { Circle().fill(Color.kal(e.farbe)).frame(width: 8, height: 8); Text(n).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1) }
            }
        }
        if let o = e.ort {
            trenner
            zeile("mappin.and.ellipse") { Text(o).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1).textSelection(.enabled) }
        }
        if let n = e.notiz {
            trenner
            zeile("text.alignleft", oben: true) {
                Text(Self.mitLinks(n)).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).tint(Farbe.himmel)
            }
        }
        Text(k.kannAendern
             ? "Dieser Termin hat Gäste oder liegt in einem Kalender, der sich nicht ändern lässt. Ändern in Apple Kalender."
             : "Ändern, Löschen und Notizen gehen, sobald Seneca direkt auf Apple Kalender zugreifen darf.")
            .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
    }

    static func mitLinks(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        for l in KalRaster.links(text) {
            guard let von = AttributedString.Index(l.bereich.lowerBound, within: a), let bis = AttributedString.Index(l.bereich.upperBound, within: a) else { continue }
            a[von..<bis].link = l.url
            a[von..<bis].underlineStyle = .single
        }
        return a
    }
}

private struct SnKalWert: View {
    let text: String
    var an = false
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Text(text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(an ? 0.14 : (hover ? 0.10 : 0.06))))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.fixedSize()
    }
}

private struct SnKalZeitFeld: View {
    let stunde: Double
    let name: String
    let setze: (Double) -> Void
    @State private var text = ""
    @FocusState private var fokus: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain).font(Schrift.mono(13)).foregroundStyle(Farbe.ink1).multilineTextAlignment(.center)
            .frame(width: 46).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(fokus ? 0.14 : 0.06)))
            .focused($fokus)
            .onSubmit(nimm)
            .onChange(of: fokus) { _, drin in if !drin { nimm() } }
            .onChange(of: stunde, initial: true) { _, h in text = KalRaster.uhr(h) }
            .accessibilityLabel(name)
    }

    private func nimm() {
        if let h = KalRaster.liesUhr(text), abs(h - stunde) > 0.001 { setze(h) }
        text = KalRaster.uhr(KalRaster.liesUhr(text) ?? stunde)
    }
}

private struct SnKalChip: View {
    let text: String
    var an = false
    var haken = false
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 5) {
                if haken { Image(systemName: an ? "checkmark.circle.fill" : "circle").font(.system(size: 11)).foregroundStyle(an ? Farbe.himmel : Farbe.ink3) }
                Text(text).font(Schrift.grotesk(12, .medium)).foregroundStyle(an || hover ? Color.white : Farbe.ink2)
            }
            .padding(.horizontal, haken ? 9 : 8).frame(minWidth: 30, minHeight: 24)
            .background(Capsule().fill(an && !haken ? Farbe.himmel.opacity(0.28) : Color.white.opacity(hover ? 0.10 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityAddTraits(an ? .isSelected : [])
    }
}

struct SnKalMiniMonat: View {
    let cal: Calendar
    var beginn: Date?
    var gewaehlt: Date?
    var markiert: Set<Date> = []
    let heute: Date
    var zelle: CGFloat = 32
    let waehle: (Date) -> Void
    @State private var monat: Date?

    var body: some View {
        let m = monat ?? KalRaster.monatsErster(gewaehlt ?? beginn ?? heute, cal)
        let stand = KalStand(ansicht: .monat, anker: m, cal)
        let tage = KalRaster.tage(stand, cal)
        VStack(spacing: 8) {
            HStack {
                Text(KalRaster.titel(stand, cal)).font(Schrift.grotesk(13, .medium)).foregroundStyle(Color.white)
                Spacer()
                SnKalMiniKnopf(symbol: "chevron.left", name: "Monat zurück") { monat = cal.date(byAdding: .month, value: -1, to: m) }
                SnKalMiniKnopf(symbol: "chevron.right", name: "Monat weiter") { monat = cal.date(byAdding: .month, value: 1, to: m) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(zelle), spacing: 2), count: 7), spacing: 2) {
                ForEach(KalRaster.wochentageKurz, id: \.self) { Text($0).font(Schrift.grotesk(10.5)).foregroundStyle(Farbe.ink3).frame(height: 18) }
                ForEach(tage, id: \.self) { d in
                    let im = cal.isDate(d, equalTo: m, toGranularity: .month)
                    Button { waehle(d) } label: {
                        Text("\(cal.component(.day, from: d))").font(Schrift.grotesk(12.5, d == heute ? .medium : .regular))
                            .foregroundStyle(d == gewaehlt ? Farbe.aufWeiss : (d == heute ? Farbe.himmel : (im ? Color.white : Farbe.ink4)))
                            .frame(width: zelle - 2, height: zelle - 2)
                            .background(Circle().fill(d == gewaehlt ? Farbe.himmel : (markiert.contains(d) ? Color.white.opacity(0.08) : .clear)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fixedSize()
    }
}

struct SnKalNotizFeld: NSViewRepresentable {
    @Binding var text: String
    @Binding var hoehe: CGFloat
    var escape: () -> Void = {}

    static let schrift = NSFont(name: "SpaceGrotesk-Regular", size: 14) ?? .systemFont(ofSize: 14)
    static let zeile: CGFloat = 20
    static let farbe = NSColor(srgbRed: 0xE2 / 255.0, green: 0xE4 / 255.0, blue: 0xE9 / 255.0, alpha: 1)
    static let linkFarbe = NSColor(srgbRed: 0x8F / 255.0, green: 0xB6 / 255.0, blue: 0xE3 / 255.0, alpha: 1)

    final class Feld: NSTextView {
        var escape: () -> Void = {}
        override func cancelOperation(_ sender: Any?) { escape() }
    }

    func makeCoordinator() -> Halter { Halter(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let rolle = NSScrollView()
        rolle.drawsBackground = false
        rolle.hasVerticalScroller = true
        rolle.scrollerStyle = .overlay
        rolle.autohidesScrollers = true
        rolle.borderType = .noBorder
        let t = Feld()
        t.delegate = context.coordinator
        t.escape = escape
        t.drawsBackground = false
        t.isRichText = false
        t.allowsUndo = true
        t.isAutomaticQuoteSubstitutionEnabled = false
        t.isAutomaticDashSubstitutionEnabled = false
        t.isAutomaticTextReplacementEnabled = false
        t.font = Self.schrift
        t.textColor = Self.farbe
        t.insertionPointColor = Self.linkFarbe
        t.typingAttributes = Self.grund
        t.linkTextAttributes = [.foregroundColor: Self.linkFarbe, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        t.textContainerInset = .zero
        t.textContainer?.lineFragmentPadding = 0
        t.textContainer?.widthTracksTextView = true
        t.isVerticallyResizable = true
        t.isHorizontallyResizable = false
        t.autoresizingMask = [.width]
        t.minSize = .zero
        t.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        t.string = text
        rolle.documentView = t
        context.coordinator.feld = t
        context.coordinator.zeichne()
        return rolle
    }

    func updateNSView(_ rolle: NSScrollView, context: Context) {
        context.coordinator.eltern = self
        guard let t = context.coordinator.feld else { return }
        t.escape = escape
        if t.string != text { t.string = text; context.coordinator.zeichne() }
        else { context.coordinator.miss() }
    }

    static var grund: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = zeile; p.maximumLineHeight = zeile
        return [.font: schrift, .foregroundColor: farbe, .paragraphStyle: p]
    }

    @MainActor
    final class Halter: NSObject, NSTextViewDelegate {
        var eltern: SnKalNotizFeld
        weak var feld: Feld?
        init(_ e: SnKalNotizFeld) { eltern = e }

        func textDidChange(_ n: Notification) {
            guard let t = feld else { return }
            if eltern.text != t.string { eltern.text = t.string }
            zeichne()
        }

        func zeichne() {
            guard let t = feld, let s = t.textStorage else { return }
            let text = t.string
            let alles = NSRange(location: 0, length: s.length)
            s.beginEditing()
            s.setAttributes(SnKalNotizFeld.grund, range: alles)
            for l in KalRaster.links(text) { s.addAttribute(.link, value: l.url, range: NSRange(l.bereich, in: text)) }
            s.endEditing()
            t.typingAttributes = SnKalNotizFeld.grund
            miss()
        }

        func miss() {
            guard let t = feld, let lm = t.layoutManager, let c = t.textContainer else { return }
            lm.ensureLayout(for: c)
            let zeilen = max(4, min(12, (lm.usedRect(for: c).height / SnKalNotizFeld.zeile).rounded(.up) + (t.string.hasSuffix("\n") ? 1 : 0)))
            let neu = zeilen * SnKalNotizFeld.zeile
            if abs(neu - eltern.hoehe) > 0.5 { DispatchQueue.main.async { [weak self] in self?.eltern.hoehe = neu } }
        }
    }
}
