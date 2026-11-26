import SwiftUI
import UIKit

enum VerschwindenArt: String {
    case a
    case b

    static let standard: VerschwindenArt = .a

    static let aktuell: VerschwindenArt = {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["SENECA_DEMO"] == "1", let art = env["SENECA_DEMO_VERSCHWINDEN"].flatMap({ VerschwindenArt(rawValue: $0.lowercased()) }) { return art }
        #endif
        return standard
    }()

    static let ruheVorLuecke = 0.25
    static let sammeln = 0.6

    func vorlauf(reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.5 }
        switch self {
        case .a: return 0.85
        case .b: return 0.8
        }
    }

    func dauer(stufen: Int, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.2 }
        switch self {
        case .a: return 0.6
        case .b: return Self.wortDauer + Self.versatz * Double(max(0, stufen - 1))
        }
    }

    static let wortDauer = 0.45
    static let versatz = 0.08

    static func woerter(_ text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isWhitespace {
                if let s = start { out.append(s..<i); start = nil }
            } else if start == nil { start = i }
            i = text.index(after: i)
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    static func stufe(wort: Int, von n: Int) -> Int { n <= 5 ? wort : wort * 5 / n }
    static func stufen(woerter n: Int) -> Int { min(max(n, 1), 5) }
}

enum VerschwindenKurve {
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func b(_ t: Double, _ a: Double, _ c: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * c + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<22 {
            t = (lo + hi) / 2
            if b(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return b(t, y1, y2)
    }
    static func ease(_ x: Double) -> Double { bezier(x, 0.22, 1, 0.36, 1) }
    static func inOut(_ x: Double) -> Double { bezier(x, 0.45, 0, 0.55, 1) }
}

func verschwindenAnimation(go: Bool, dauer: Double, reduceMotion: Bool) -> Animation {
    if reduceMotion { return .linear(duration: 0.2) }
    return .linear(duration: go ? dauer : min(0.4, dauer))
}

struct VerschwindenZeile: ViewModifier, Animatable {
    var p: Double
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let e = VerschwindenKurve.ease(p)
        content
            .compositingGroup()
            .scaleEffect(x: reduceMotion ? 1 : 1 + 0.04 * e, anchor: .leading)
            .offset(x: reduceMotion ? 0 : -10 * e)
            .blur(radius: reduceMotion ? 0 : 10 * VerschwindenKurve.inOut(seg(p, 0, 0.8)))
            .opacity(1 - (reduceMotion ? p : VerschwindenKurve.inOut(seg(p, 0.25, 1))))
    }
}

struct VerschwindenTeil: ViewModifier, Animatable {
    var p: Double
    var gesamt: Double
    var verzug: Double
    var reduceMotion: Bool
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let u = reduceMotion ? p : seg(p * gesamt, verzug, verzug + VerschwindenArt.wortDauer)
        let e = VerschwindenKurve.ease(u)
        content
            .blur(radius: reduceMotion ? 0 : 6 * VerschwindenKurve.inOut(seg(u, 0, 0.9)))
            .offset(y: reduceMotion ? 0 : -8 * e)
            .opacity(1 - (reduceMotion ? u : VerschwindenKurve.inOut(seg(u, 0.1, 1))))
    }
}

struct VerschwindenWorte: View {
    var text: String
    var size: CGFloat
    var font: Font
    var on: Bool
    var go: Bool
    var reduceMotion = false

    var body: some View {
        if !on {
            normal
        } else {
            let grenzen = Self.grenzen(text, size: size)
            let n = grenzen.count
            let gesamt = VerschwindenArt.b.dauer(stufen: VerschwindenArt.stufen(woerter: n), reduceMotion: reduceMotion)
            ZStack(alignment: .leading) {
                ForEach(0..<n, id: \.self) { i in
                    let von = grenzen[i].0, bis = grenzen[i].1
                    normal
                        .mask(alignment: .leading) {
                            Color.black.frame(width: bis - von, height: size * 3).offset(x: von)
                        }
                        .modifier(VerschwindenTeil(p: go ? 1 : 0, gesamt: gesamt,
                                                   verzug: VerschwindenArt.versatz * Double(VerschwindenArt.stufe(wort: i, von: n)),
                                                   reduceMotion: reduceMotion))
                        .animation(verschwindenAnimation(go: go, dauer: gesamt, reduceMotion: reduceMotion), value: go)
                }
            }
        }
    }

    private var normal: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Stil.tinte.voll)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    static func grenzen(_ text: String, size: CGFloat) -> [(CGFloat, CGFloat)] {
        let wo = VerschwindenArt.woerter(text)
        guard wo.count > 1 else { return [(-size * 4, 4000)] }
        let uifont = UIFont(name: "SpaceGrotesk-Regular", size: size) ?? .systemFont(ofSize: size)
        func breite(_ s: Substring) -> CGFloat { (String(s) as NSString).size(withAttributes: [.font: uifont]).width }
        var mitten: [CGFloat] = []
        for k in 1..<wo.count {
            let endeDavor = breite(text[..<wo[k - 1].upperBound])
            let anfangDanach = breite(text[..<wo[k].lowerBound])
            mitten.append((endeDavor + anfangDanach) / 2)
        }
        var out: [(CGFloat, CGFloat)] = []
        for i in 0..<wo.count {
            let von = i == 0 ? -size * 4 : mitten[i - 1]
            let bis = i == wo.count - 1 ? 4000 : mitten[i]
            out.append((von, bis))
        }
        return out
    }
}

extension View {
    @ViewBuilder
    func zeilenClip(_ art: VerschwindenArt?) -> some View {
        if art == nil {
            clipped()
        } else {
            mask { Rectangle().padding(.vertical, -Stil.abstand.xl) }
        }
    }

    @ViewBuilder
    func verschwindenZeile(_ art: VerschwindenArt?, go: Bool, reduceMotion: Bool) -> some View {
        if art == .a {
            modifier(VerschwindenZeile(p: go ? 1 : 0, reduceMotion: reduceMotion))
                .animation(verschwindenAnimation(go: go, dauer: VerschwindenArt.a.dauer(stufen: 1, reduceMotion: reduceMotion), reduceMotion: reduceMotion), value: go)
        } else {
            self
        }
    }

    @ViewBuilder
    func verschwindenTeil(_ art: VerschwindenArt?, go: Bool, woerter: Int, reduceMotion: Bool) -> some View {
        if art == .b {
            let gesamt = VerschwindenArt.b.dauer(stufen: VerschwindenArt.stufen(woerter: woerter), reduceMotion: reduceMotion)
            modifier(VerschwindenTeil(p: go ? 1 : 0, gesamt: gesamt, verzug: 0, reduceMotion: reduceMotion))
                .animation(verschwindenAnimation(go: go, dauer: gesamt, reduceMotion: reduceMotion), value: go)
        } else {
            self
        }
    }
}
