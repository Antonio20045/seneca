import SwiftUI
import AppKit

@MainActor
final class Rollhalter: NSObject {
    private weak var roll: NSScrollView?
    private var eigen = false
    private var oben: CGFloat = 0
    private var hoehe: CGFloat = 0
    private var sicht: CGFloat = 0
    private(set) var folgt = true
    private var live = false
    private var wartet = false
    var meldeFolgt: (Bool) -> Void = { _ in }
    var obenNah: () -> Void = {}
    private var obenGemeldet = false
    var haltEnde = false
    nonisolated(unsafe) static var ansEndeGesetzt = 0
    nonisolated(unsafe) static var messungHand = false

    private static var protokollDatei: FileHandle?
    private static var protokoll: Bool { protokollDatei != nil }
    private static func pruefeProtokoll() {
        if ProcessInfo.processInfo.environment["SENECA_CHAT_LAGE"] == "1" { protokollDatei = FileHandle.standardError; return }
        guard FileManager.default.fileExists(atPath: "/tmp/seneca-chat-lage") else { protokollDatei = nil; return }
        if protokollDatei == nil {
            if !FileManager.default.fileExists(atPath: "/tmp/seneca-chat-lage.log") {
                FileManager.default.createFile(atPath: "/tmp/seneca-chat-lage.log", contents: nil, attributes: [.posixPermissions: 0o600])
            }
            protokollDatei = FileHandle(forWritingAtPath: "/tmp/seneca-chat-lage.log")
            protokollDatei?.seekToEndOfFile()
        }
    }

    func verbinde(_ s: NSScrollView) {
        guard s !== roll else { return }
        NotificationCenter.default.removeObserver(self)
        roll = s
        haltEnde = false; live = false; wartet = false
        Self.pruefeProtokoll()
        if Self.protokoll { Self.protokollDatei?.write(Data("LAGE verbunden\n".utf8)) }
        let clip = s.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(gerollt), name: NSView.boundsDidChangeNotification, object: clip)
        nc.addObserver(self, selector: #selector(groesse), name: NSView.frameDidChangeNotification, object: clip)
        if let d = s.documentView {
            d.postsFrameChangedNotifications = true
            nc.addObserver(self, selector: #selector(groesse), name: NSView.frameDidChangeNotification, object: d)
        }
        nc.addObserver(self, selector: #selector(liveAnfang), name: NSScrollView.willStartLiveScrollNotification, object: s)
        nc.addObserver(self, selector: #selector(handGerollt), name: NSScrollView.didLiveScrollNotification, object: s)
        nc.addObserver(self, selector: #selector(liveEnde), name: NSScrollView.didEndLiveScrollNotification, object: s)
        ansEnde()
    }

    func ansEnde() {
        setze(folgt: true)
        guard let s = roll, let d = s.documentView else { return }
        setzeOben(d.frame.height - s.contentView.bounds.height)
        merke()
    }

    private typealias Lage = (oben: CGFloat, hoehe: CGFloat, sicht: CGFloat)

    private func lage() -> Lage? {
        guard let s = roll, let d = s.documentView else { return nil }
        let b = s.contentView.bounds
        return (d.isFlipped ? b.minY : d.frame.height - b.maxY, d.frame.height, b.height)
    }

    private func merke() {
        guard let l = lage() else { return }
        oben = l.oben; hoehe = l.hoehe; sicht = l.sicht
    }

    private func setze(folgt neu: Bool) {
        guard neu != folgt else { return }
        folgt = neu
        meldeFolgt(neu)
    }

    private func setzeOben(_ y: CGFloat) {
        guard let s = roll, let d = s.documentView else { return }
        let clip = s.contentView
        let ziel = max(-s.contentInsets.top, y)
        let p = NSPoint(x: clip.bounds.origin.x, y: d.isFlipped ? ziel : d.frame.height - ziel - clip.bounds.height)
        guard abs(p.y - clip.bounds.origin.y) > 0.01 else { return }
        Self.ansEndeGesetzt += 1
        eigen = true
        clip.scroll(to: p)
        s.reflectScrolledClipView(clip)
        eigen = false
    }

    @objc private func groesse() {
        guard !eigen, let l = lage(), l.hoehe != hoehe || l.sicht != sicht else { return }
        if Self.protokoll { schreibe("groesse", l) }
        if folgt {
            setzeOben(l.hoehe - l.sicht)
        } else if haltEnde {
            setzeOben(l.hoehe - l.sicht - (hoehe - sicht - oben))
        } else if l.hoehe - l.sicht - l.oben <= Folgen.amEnde {
            setze(folgt: true)
        }
        haltEnde = false
        merke()
    }

    @objc private func gerollt() {
        guard !eigen, let l = lage() else { return }
        if l.oben < 160, !obenGemeldet { obenGemeldet = true; haltEnde = true; obenNah() } else if l.oben > 400 { obenGemeldet = false }
        if l.sicht != sicht || l.hoehe != hoehe { groesse(); return }
        if live || Self.messungHand {
            vonHand(l)
        } else if NSApp.currentEvent?.type == .scrollWheel {
            if !wartet {
                wartet = true
                RunLoop.main.perform(inModes: [.common]) { [weak self] in MainActor.assumeIsolated { self?.klaere() } }
            }
        } else {
            nichtVonHand(l)
        }
    }

    @objc private func liveAnfang() { live = true }
    @objc private func liveEnde() { live = false }

    @objc private func handGerollt() {
        wartet = false
        guard !eigen, let l = lage() else { return }
        vonHand(l)
    }

    private func klaere() {
        guard wartet else { return }
        wartet = false
        guard let l = lage() else { return }
        if l.sicht != sicht || l.hoehe != hoehe { groesse() } else { nichtVonHand(l) }
    }

    private func vonHand(_ l: Lage) {
        guard l.oben != oben else { return }
        if Self.protokoll { schreibe("gerollt", l) }
        setze(folgt: Folgen.folgt(obenAlt: oben, obenNeu: l.oben, abstand: l.hoehe - l.sicht - l.oben))
        merke()
    }

    private func nichtVonHand(_ l: Lage) {
        guard l.oben != oben else { return }
        if Self.protokoll { schreibe("versetzt", l) }
        if folgt {
            setzeOben(l.hoehe - l.sicht)
        } else if l.hoehe - l.sicht - l.oben <= Folgen.amEnde {
            setze(folgt: true)
        }
        merke()
    }

    private func schreibe(_ was: String, _ l: Lage) {
        Self.protokollDatei?.write(Data(String(format: "LAGE %@ inhalt %.0f>%.0f oben %.0f>%.0f abstand %.0f folgt %d live %d ereignis %d\n", was, hoehe, l.hoehe,
                                               oben, l.oben, l.hoehe - l.sicht - l.oben, folgt ? 1 : 0, live ? 1 : 0, Int(NSApp.currentEvent?.type.rawValue ?? 0)).utf8))
    }
}

struct RollFuehler: NSViewRepresentable {
    let halter: Rollhalter
    var erste: String?

    final class Koordinator { var erste: String? }
    func makeCoordinator() -> Koordinator { Koordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.erste = erste
        return Ansicht(halter: halter)
    }

    func updateNSView(_ v: NSView, context: Context) {
        (v as? Ansicht)?.verbinde()
        if let alt = context.coordinator.erste, alt != erste { halter.haltEnde = true }
        context.coordinator.erste = erste
    }

    final class Ansicht: NSView {
        let halter: Rollhalter
        init(halter: Rollhalter) { self.halter = halter; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        func verbinde() { if window != nil, let s = enclosingScrollView { halter.verbinde(s) } }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); verbinde() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); verbinde() }
        override func layout() { super.layout(); verbinde() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
