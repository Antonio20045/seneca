import SwiftUI
import AppKit
import os

struct SnMehrzeilenFeld: View {
    @Binding var text: String
    var maxZeilen = 8
    var fokusAnfrage = 0
    var senden: () -> Void = {}
    var escape: () -> Void = {}
    var einfuegenAnhang: (NSPasteboard) -> Bool = { _ in false }
    @State private var hoehe: CGFloat = SnMehrzeilenFeldInnen.zeilenhoehe

    var body: some View {
        SnMehrzeilenFeldInnen(text: $text, hoehe: $hoehe, maxZeilen: maxZeilen, fokusAnfrage: fokusAnfrage, senden: senden, escape: escape, einfuegenAnhang: einfuegenAnhang)
            .frame(height: hoehe)
    }
}

final class SnEingabeTextView: NSTextView {
    var einfuegenAnhang: (NSPasteboard) -> Bool = { _ in false }

    private var sperre = EinfuegeSperre()
    private var zusammensetzung = false

    override func keyDown(with e: NSEvent) {
        zusammensetzung = hasMarkedText()
        super.keyDown(with: e)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let e = NSApp.currentEvent
        let druck = e?.type == .keyDown ? e?.timestamp : nil
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let ersetzt = replacementRange.location != NSNotFound || zusammensetzung || hasMarkedText()
        if sperre.istDoppelt(text, druck: druck, ersetzt: ersetzt) {
            Logger(subsystem: "de.antonio.seneca.nativ", category: "tasten").notice("doppeltes Einfügen verworfen, bisher \(self.sperre.verworfen)")
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        if einfuegenAnhang(.general) { return }
        super.paste(sender)
    }
}

struct SnMehrzeilenFeldInnen: NSViewRepresentable {
    @Binding var text: String
    @Binding var hoehe: CGFloat
    var maxZeilen: Int
    var fokusAnfrage: Int
    var senden: () -> Void
    var escape: () -> Void
    var einfuegenAnhang: (NSPasteboard) -> Bool = { _ in false }

    static let schrift = NSFont(name: "SpaceGrotesk-Regular", size: 16) ?? .systemFont(ofSize: 16)
    static let zeilenhoehe: CGFloat = NSLayoutManager().defaultLineHeight(for: schrift).rounded(.up)

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let speicher = NSTextStorage()
        let layout = NSLayoutManager()
        let behaelter = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        behaelter.widthTracksTextView = true
        behaelter.lineFragmentPadding = 0
        speicher.addLayoutManager(layout)
        layout.addTextContainer(behaelter)

        let tv = SnEingabeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: Self.zeilenhoehe), textContainer: behaelter)
        tv.einfuegenAnhang = einfuegenAnhang
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize.zero
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = NSView.AutoresizingMask.width
        tv.font = Self.schrift
        tv.textColor = NSColor.white
        tv.insertionPointColor = NSColor.white
        tv.typingAttributes = [NSAttributedString.Key.font: Self.schrift, NSAttributedString.Key.foregroundColor: NSColor.white]
        tv.string = text
        tv.setAccessibilityLabel("Nachricht")
        tv.setAccessibilityIdentifier("chatfeld")

        let rolle = NSScrollView()
        rolle.documentView = tv
        rolle.drawsBackground = false
        rolle.borderType = .noBorder
        rolle.hasVerticalScroller = true
        rolle.hasHorizontalScroller = false
        rolle.autohidesScrollers = true
        rolle.scrollerStyle = .overlay
        rolle.verticalScrollElasticity = .allowed
        rolle.postsFrameChangedNotifications = true
        let k = context.coordinator
        k.textView = tv
        k.rolle = rolle
        k.letzteAnfrage = fokusAnfrage
        k.beobachter = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: rolle, queue: .main) { [weak k] _ in
            MainActor.assumeIsolated { k?.planeMessung() }
        }
        k.planeMessung()
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        k.probeEinsetzen()
        return rolle
    }

    func updateNSView(_ rolle: NSScrollView, context: Context) {
        let k = context.coordinator
        k.eltern = self
        guard let tv = k.textView else { return }
        (tv as? SnEingabeTextView)?.einfuegenAnhang = einfuegenAnhang
        if tv.string != text, !tv.hasMarkedText() {
            tv.string = text
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            k.planeMessung()
        }
        if k.letzteAnfrage != fokusAnfrage {
            k.letzteAnfrage = fokusAnfrage
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    @MainActor
    final class Koordinator: NSObject, NSTextViewDelegate {
        var eltern: SnMehrzeilenFeldInnen
        weak var textView: NSTextView?
        weak var rolle: NSScrollView?
        var letzteAnfrage = 0
        var beobachter: NSObjectProtocol?
        private var geplant = false

        init(_ eltern: SnMehrzeilenFeldInnen) { self.eltern = eltern }

        deinit { if let b = beobachter { NotificationCenter.default.removeObserver(b) } }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if eltern.text != tv.string { eltern.text = tv.string }
            planeMessung()
        }

        func planeMessung() {
            guard !geplant else { return }
            geplant = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.geplant = false
                    self?.miss()
                }
            }
        }

        private func miss() {
            guard let tv = textView, let rolle, let layout = tv.layoutManager, let behaelter = tv.textContainer else { return }
            let breite = rolle.contentSize.width
            guard breite > 20 else { return }
            if abs(behaelter.size.width - breite) > 0.5 { behaelter.size = NSSize(width: breite, height: CGFloat.greatestFiniteMagnitude) }
            layout.ensureLayout(for: behaelter)
            let zeile = SnMehrzeilenFeldInnen.zeilenhoehe
            let inhalt = max(layout.usedRect(for: behaelter).maxY, layout.extraLineFragmentRect.maxY, zeile).rounded(.up)
            let sicht = min(inhalt, zeile * CGFloat(eltern.maxZeilen))
            let dokument = NSSize(width: breite, height: max(inhalt, sicht))
            if abs(tv.frame.width - dokument.width) > 0.5 || abs(tv.frame.height - dokument.height) > 0.5 { tv.setFrameSize(dokument) }
            if abs(eltern.hoehe - sicht) > 0.5 { eltern.hoehe = sicht }
            let clip = rolle.contentView
            if inhalt <= sicht + 0.5 {
                if clip.bounds.origin.y != 0 { clip.scroll(to: .zero); rolle.reflectScrolledClipView(clip) }
            } else {
                tv.scrollRangeToVisible(tv.selectedRange())
            }
        }

        func probeEinsetzen() {
            let env = ProcessInfo.processInfo.environment
            guard let h = env["SENECA_HINTERGRUND"], !h.isEmpty, h != "0",
                  let n = env["SENECA_HINTERGRUND_EINGABE_ZEILEN"].flatMap({ Int($0) }), n > 0,
                  env["SENECA_HINTERGRUND_ZIEL"] != nil else { return }
            let nach = env["SENECA_HINTERGRUND_EINGABE_NACH"].flatMap { Double($0) } ?? 8
            let dauer = env["SENECA_HINTERGRUND_EINGABE_DAUER"].flatMap { Double($0) } ?? 14
            DispatchQueue.main.asyncAfter(deadline: .now() + nach) { [weak self] in
                MainActor.assumeIsolated {
                    self?.eltern.text = (1...n).map { "Zeile \($0): Prüftext für das Chatfeld, nur eine Anzeigeprobe" }.joined(separator: "\n")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + nach + dauer) { [weak self] in
                MainActor.assumeIsolated { self?.eltern.text = "" }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy befehl: Selector) -> Bool {
            switch befehl {
            case #selector(NSResponder.insertNewline(_:)):
                let tasten = NSApp.currentEvent?.modifierFlags ?? []
                if tasten.contains(.shift) || tasten.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    eltern.senden()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                eltern.escape()
                return true
            default:
                return false
            }
        }
    }
}
