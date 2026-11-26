import SwiftUI

struct SenecaLayer: View {
    var m: Metrics
    var zug: Wisch.Wert<TransitionState>
    var aktiv: Bool
    var sichtbar: Bool
    @ObservedObject var model: ConversationModel
    var reduceMotion: Bool
    var keyboardHeight: CGFloat
    var close: () -> Void
    var allowTap: () -> Bool = { true }
    var zurueckZiel = "Heute"
    var zurueckZieht: (CGFloat) -> Void = { _ in }
    var zurueckLos: (CGFloat, CGFloat) -> Void = { _, _ in }

    @EnvironmentObject private var chat: ChatService
    @State private var mounted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if mounted {
                FadenLayer(m: m, aktiv: aktiv, model: model, speech: model.speech, keyboardHeight: keyboardHeight,
                           reduceMotion: reduceMotion, allowTap: allowTap, zurueck: close, zurueckZiel: zurueckZiel)
                    .gesture(ZurueckPan(zieht: zurueckZieht, losgelassen: zurueckLos))
                    .modifier(SenecaEin(zug: zug, breite: m.size.width, reduceMotion: reduceMotion))
            }
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("seneca.voice")
                .accessibilityLabel(model.spokenText)
                .accessibilityValue(model.voiceState)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .ignoresSafeArea(.keyboard)
        .accessibilityAction(.escape) { close() }
        .accessibilityAction(named: "Zurück zum Tag") { close() }
        .onChange(of: aktiv, initial: true) { _, vorn in chat.isShowing = vorn }
        .task(id: aktiv) { if aktiv { await chat.speicher.wache() } }
        .onChange(of: sichtbar, initial: true) { _, da in zeigen(da) }
        .onChange(of: model.target?.sessionKey, initial: true) { _, key in
            guard let key else { return }
            if let p = ChatPartner.zu(sessionKey: key, main: chat.mainKey) { chat.waehle(p) }
            model.target = nil
        }
    }

    private func zeigen(_ da: Bool) {
        if da {
            guard !mounted else { return }
            mounted = true
            Task { await chat.refreshFill(chat.partner) }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1000))
                if zug.wert.p == 0 && !zug.wert.dragging { mounted = false }
            }
        }
    }
}

private struct SenecaEin: ViewModifier {
    @ObservedObject var zug: Wisch.Wert<TransitionState>
    var breite: CGFloat
    var reduceMotion: Bool
    @State private var shown = TransitionState(p: 0, dragging: true)
    @State private var steht = false

    func body(content: Content) -> some View {
        content
            .modifier(SenecaZug(p: shown.p, seitlich: shown.seitlich, breite: breite, reduceMotion: reduceMotion))
            .animation(shown.animation(reduceMotion), value: shown.p)
            .onChange(of: zug.wert, initial: true) { _, new in
                if steht || new.dragging {
                    steht = true
                    shown = new
                    return
                }
                steht = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    shown = zug.wert
                }
            }
    }
}

private struct SenecaZug: ViewModifier, Animatable {
    var p: Double
    var seitlich: Bool
    var breite: CGFloat
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let q = min(1, max(0, p))
        content
            .opacity(seitlich ? (reduceMotion ? q : 1) : seg(q, 0.5, 1))
            .offset(x: seitlich && !reduceMotion ? CGFloat(1 - q) * breite : 0)
    }
}

enum LineBreaker {
    static func lines(_ segments: [AnswerLayout.Segment], width: CGFloat, size: CGFloat) -> [Text] {
        let regular = UIFont(name: "InstrumentSerif-Regular", size: size) ?? .systemFont(ofSize: size)
        let italic = UIFont(name: "InstrumentSerif-Italic", size: size) ?? .italicSystemFont(ofSize: size)
        let attributed = NSMutableAttributedString()
        for s in segments {
            attributed.append(NSAttributedString(string: s.text, attributes: [.font: s.italic ? italic : regular, .kern: -0.01 * size]))
        }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let ctLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        let full = attributed.string as NSString
        var ranges = ctLines.map { line -> NSRange in
            let r = CTLineGetStringRange(line)
            return NSRange(location: r.location, length: r.length)
        }
        if ranges.count == 2 {
            let comma = full.range(of: ", ", options: .backwards, range: NSRange(location: 0, length: ranges[0].location + ranges[0].length))
            if comma.location != NSNotFound, comma.location > full.length / 4 {
                let first = NSRange(location: 0, length: comma.location + 2)
                let second = NSRange(location: first.length, length: full.length - first.length)
                let fits = [first, second].allSatisfy { r in
                    CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed.attributedSubstring(from: r)), nil, nil, nil) <= Double(width)
                }
                if fits { ranges = [first, second] }
            }
        }
        return ranges.map { lineRange in
            var text = Text("")
            attributed.enumerateAttribute(.font, in: lineRange) { value, range, _ in
                let piece = full.substring(with: range).replacingOccurrences(of: "\n", with: "")
                let isItalic = (value as? UIFont)?.fontName == italic.fontName
                text = text + Text(piece).font(Sundartha.serif(size, italic: isItalic))
            }
            return text.tracking(-0.01 * size)
        }
    }
}
