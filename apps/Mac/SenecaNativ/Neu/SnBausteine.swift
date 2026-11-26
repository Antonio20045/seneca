import SwiftUI
import WebKit

struct SeitenBaustein: Identifiable, Equatable, Decodable {
    let id: String
    let titel: String
    let seite: String
    let html: String
}

@MainActor
final class BausteinModell: ObservableObject {
    @Published private(set) var liste: [SeitenBaustein] = []
    private var agent: String?
    private var lauf: Task<Void, Never>?

    private static func datei(_ agent: String) -> URL? {
        MacPfade.datenOrdner?.appendingPathComponent("bausteine-\(agent.replacingOccurrences(of: "/", with: "_")).json")
    }
    private static func vonPlatte(_ agent: String) -> [SeitenBaustein] {
        guard let url = datei(agent), let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SeitenBaustein].self, from: d)) ?? []
    }

    func zeige(agent neu: String) {
        guard TageslaufModell.erlaubt, neu != agent || lauf == nil else { return }
        if neu != agent { liste = Self.vonPlatte(neu) }
        agent = neu
        lauf?.cancel()
        lauf = Task { [weak self] in
            while !Task.isCancelled {
                let daten = await Kindprozess.laufe(TageslaufModell.befehl, ["baustein", "--agent", neu, "--ohne-lauf"], limit: 45)
                guard let self, !Task.isCancelled else { return }
                if let daten, let gelesen = try? JSONDecoder().decode([SeitenBaustein].self, from: daten) {
                    if gelesen != self.liste { self.liste = gelesen }
                    if let url = Self.datei(neu) { try? daten.write(to: url, options: .atomic) }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func halte() { lauf?.cancel(); lauf = nil }
}

enum SeitenHuelle {
    private static let schriften: String = {
        [("SpaceGrotesk-Regular", "Space Grotesk", 400), ("SpaceGrotesk-Medium", "Space Grotesk", 500), ("InstrumentSerif-Regular", "Instrument Serif", 400)]
            .compactMap { datei, familie, gewicht -> String? in
                guard let u = Bundle.main.url(forResource: datei, withExtension: "ttf"), let d = try? Data(contentsOf: u) else { return nil }
                return "@font-face{font-family:'\(familie)';font-weight:\(gewicht);src:url(data:font/ttf;base64,\(d.base64EncodedString())) format('truetype')}"
            }.joined()
    }()

    static func seite(_ inhalt: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: blob:; font-src data:">
        <style>\(schriften)
        :root{--text:#E2E4E9;--stark:#FFFFFF;--leise:#939EAD;--linie:rgba(255,255,255,.10);--gut:#6BD98F;--schlecht:#E88A6B;--akzent:#8FB6E3;
        --grotesk:'Space Grotesk',-apple-system,sans-serif;--serif:'Instrument Serif',Georgia,serif;color-scheme:dark}
        *{box-sizing:border-box}html,body{margin:0;background:transparent;overflow:hidden}
        body{font:13px/1.45 var(--grotesk);color:var(--text);-webkit-font-smoothing:antialiased;cursor:default;-webkit-user-select:none}
        </style></head><body><div id="baustein">\(inhalt)</div>
        <script>(function(){var l=0,b=document.getElementById('baustein');function r(){var h=Math.ceil(b.getBoundingClientRect().height)+2;
        if(h!==l){l=h;window.webkit.messageHandlers.h.postMessage(h)}}new ResizeObserver(r).observe(b);addEventListener('load',r);
        if(document.fonts)document.fonts.ready.then(r);r()})()</script></body></html>
        """
    }
}

private final class DurchrollWeb: WKWebView {
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}

struct SeitenWeb: NSViewRepresentable {
    let html: String
    @Binding var hoehe: CGFloat

    func makeCoordinator() -> Halter { Halter(hoehe: $hoehe) }

    func makeNSView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.userContentController.add(Schwach(context.coordinator), name: "h")
        let w = DurchrollWeb(frame: .zero, configuration: c)
        w.setValue(false, forKey: "drawsBackground")
        w.navigationDelegate = context.coordinator
        context.coordinator.geladen = html
        w.loadHTMLString(SeitenHuelle.seite(html), baseURL: nil)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        context.coordinator.hoehe = $hoehe
        guard context.coordinator.geladen != html else { return }
        context.coordinator.geladen = html
        w.loadHTMLString(SeitenHuelle.seite(html), baseURL: nil)
    }

    static func dismantleNSView(_ w: WKWebView, coordinator: Halter) {
        w.navigationDelegate = nil
        w.configuration.userContentController.removeScriptMessageHandler(forName: "h")
    }

    private final class Schwach: NSObject, WKScriptMessageHandler {
        weak var ziel: Halter?
        init(_ z: Halter) { ziel = z }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { ziel?.empfange(m.body) }
    }

    @MainActor
    final class Halter: NSObject, WKNavigationDelegate {
        var hoehe: Binding<CGFloat>
        var geladen = ""
        init(hoehe: Binding<CGFloat>) { self.hoehe = hoehe }

        func empfange(_ body: Any) {
            guard let h = (body as? NSNumber)?.doubleValue, h > 0 else { return }
            let neu = CGFloat(min(h, 4000))
            if abs(hoehe.wrappedValue - neu) > 0.5 { hoehe.wrappedValue = neu }
        }

        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(a.navigationType == .other ? .allow : .cancel)
        }
    }
}

struct SeitenBausteinView: View {
    let baustein: SeitenBaustein
    @State private var hoehe: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(baustein.titel).font(Schrift.serif(24)).foregroundStyle(Farbe.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
            SeitenWeb(html: baustein.html, hoehe: $hoehe).frame(height: max(hoehe, 1))
        }
        .opacity(hoehe > 0 ? 1 : 0)
        .offset(y: hoehe > 0 ? 0 : 10)
        .animation(Kurve.sn(0.5), value: hoehe > 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("baustein")
    }
}

struct SnSeitenflaeche: View {
    let bausteine: [SeitenBaustein]
    var laeuft: [Aufgabe] = []
    var oeffne: (String) -> Void = { _ in }
    var zumBoard: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 44) {
                if !laeuft.isEmpty { SnLaeuftGerade(aufgaben: laeuft, oeffne: oeffne, zumBoard: zumBoard) }
                ForEach(bausteine) { SeitenBausteinView(baustein: $0) }
            }
            .padding(.top, 2).padding(.bottom, 24)
        }
    }
}

struct SnSeiten: View {
    @ObservedObject var modell: BausteinModell
    var laeuft: [Aufgabe] = []
    var oeffne: (String) -> Void = { _ in }
    var zumBoard: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let frei = (g.size.width - 720) / 2 - 56 - 28
            if frei >= 220, !modell.liste.isEmpty || !laeuft.isEmpty {
                let breite = min(300, frei)
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)
                    SnSeitenflaeche(bausteine: modell.liste.filter { $0.seite == "links" }, laeuft: laeuft, oeffne: oeffne, zumBoard: zumBoard).frame(width: breite)
                    Spacer(minLength: 0).frame(width: 720 + 112)
                    SnSeitenflaeche(bausteine: modell.liste.filter { $0.seite != "links" }).frame(width: breite)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
