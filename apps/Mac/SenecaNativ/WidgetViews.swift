import SwiftUI
import WebKit

extension Notification.Name {
    static let widgetGewachsen = Notification.Name("seneca.widgetGewachsen")
}

enum WidgetPfade {
    private static func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static let standard = "/mcp-app-sandbox?csp=" + b64url(#"{"resourceDomains":["https://cdnjs.cloudflare.com","https://cdn.jsdelivr.net","https://esm.sh","https://unpkg.com","https://fonts.googleapis.com","https://fonts.gstatic.com","https://fonts.bunny.net"],"mediaDomains":["https:","blob:"],"blockDescendantFrames":true}"#)
    static let streng = "/mcp-app-sandbox?csp=" + b64url(#"{"mediaDomains":["blob:"],"blockDescendantFrames":true}"#)
}

struct WidgetRahmen: View {
    enum Quelle: Equatable { case ansicht(String); case html(String, streng: Bool) }
    var quelle: Quelle
    var titel: String
    var modus: WidgetQuelle.Modus
    var anzeige = false
    var onHtml: ((String) -> Void)?
    @EnvironmentObject private var ansichten: AnsichtModell
    @State private var dok: WidgetDokument?
    @State private var fehler: String?
    @State private var hoehe: Double?
    @State private var geladen = false
    @State private var laufFehler: String?
    @State private var versuch = 0

    var body: some View {
        Group {
            if let fehler {
                HStack(spacing: 12) {
                    Text(fehler).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2)
                    if versuch > 0 {
                        Button("Nochmal") { self.fehler = nil; versuch = 0; geladen = false; hoehe = nil; Task { await lade() } }
                            .buttonStyle(.plain).font(Schrift.grotesk(13.5, .medium)).foregroundStyle(Farbe.ink).underline()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .accessibilityIdentifier("widget-fehler")
            } else {
                rahmen
            }
        }
        .task(id: quelle) { await lade() }
    }

    private var rahmen: some View {
        let maximal = WidgetQuelle.maxHoehe[modus] ?? 640
        let h = hoehe ?? WidgetQuelle.anfangsHoehe(modus)
        let abgeschnitten = hoehe.map { $0 > maximal } ?? false
        return ZStack(alignment: .bottom) {
            if let dok, let adresse = adresse(dok) {
                WidgetWeb(adresse: adresse, html: dok.html, gateway: ansichten.gateway, versuch: versuch,
                          rueckrufe: WidgetWeb.Rueckrufe(
                            geladen: { geladen = true },
                            hoehe: { hoehe = $0; if modus == .chat { NotificationCenter.default.post(name: .widgetGewachsen, object: nil) } },
                            laufFehler: { laufFehler = $0 },
                            vorschlag: { anzeige ? ansichten.vorschlagen($0) : ansichten.senden($0) },
                            zeitueberschreitung: {
                                if versuch < 1 { versuch += 1 } else { fehler = "Die Ansicht startet gerade nicht. Ein Neustart von Seneca hilft meistens." }
                            }))
                    .id(versuch)
            }
            if !geladen { SchimmerFlaeche(radius: 0).allowsHitTesting(false).transition(.opacity) }
            if abgeschnitten {
                LinearGradient(colors: [Color.white.opacity(0), Farbe.papier], startPoint: .top, endPoint: .bottom).frame(height: 72).allowsHitTesting(false)
            }
            if let m = laufFehler {
                HStack(spacing: 10) {
                    Text("Diese Ansicht hatte einen Fehler.").foregroundStyle(Farbe.koralle)
                    Spacer(minLength: 0)
                    Button("Reparieren lassen") {
                        ansichten.senden("Die Ansicht „\(titel)“ hatte einen Skriptfehler: \(m). Bitte reparier sie und zeig sie nochmal.")
                    }
                    .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).underline().foregroundStyle(Farbe.koralle)
                }
                .font(Schrift.grotesk(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Farbe.papier, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Farbe.schatten, radius: 7, y: 4)
                .padding(12)
                .accessibilityIdentifier("widget-hinweis")
            }
        }
        .frame(height: min(h, maximal))
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(Kurve.ease(0.35), value: hoehe)
        .animation(Kurve.ease(0.4), value: geladen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titel)
        .accessibilityIdentifier("widget")
    }

    private func adresse(_ d: WidgetDokument) -> URL? {
        WidgetQuelle.erlaubteAdresse(pfad: d.sandboxUrl, origin: d.sandboxOrigin, gateway: ansichten.gateway)
    }

    private func lade() async {
        fehler = nil
        switch quelle {
        case .ansicht(let id):
            switch await ansichten.dokument(docId: id) {
            case .success(let d):
                guard adresse(d) != nil else { fehler = AnsichtModell.WidgetFehler.fremd.text; return }
                dok = d; onHtml?(d.html)
            case .failure(let f): fehler = f.text
            }
        case .html(let h, let streng):
            let d = WidgetDokument(html: h, sandboxUrl: streng ? WidgetPfade.streng : WidgetPfade.standard, sandboxOrigin: nil)
            guard adresse(d) != nil else { fehler = AnsichtModell.WidgetFehler.fremd.text; return }
            dok = d; onHtml?(h)
        }
    }
}

private final class RahmenWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}

struct WidgetWeb: NSViewRepresentable {
    struct Rueckrufe {
        var geladen: () -> Void
        var hoehe: (Double) -> Void
        var laufFehler: (String) -> Void
        var vorschlag: (String) -> Void
        var zeitueberschreitung: () -> Void
    }
    var adresse: URL
    var html: String
    var gateway: String
    var versuch: Int
    var rueckrufe: Rueckrufe

    func makeCoordinator() -> Bruecke { Bruecke(adresse: adresse, html: html, gateway: gateway, rueckrufe: rueckrufe) }

    func makeNSView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.userContentController.add(WeakHandler(context.coordinator), name: "w")
        let w = RahmenWebView(frame: .zero, configuration: c)
        w.navigationDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = w
        context.coordinator.starte()
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) { context.coordinator.rueckrufe = rueckrufe }

    static func dismantleNSView(_ w: WKWebView, coordinator: Bruecke) {
        coordinator.beende()
        w.configuration.userContentController.removeScriptMessageHandler(forName: "w")
    }

    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var ziel: Bruecke?
        init(_ z: Bruecke) { ziel = z }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { ziel?.empfange(m.body) }
    }

    @MainActor
    final class Bruecke: NSObject, WKNavigationDelegate {
        weak var web: WKWebView?
        let adresse: URL
        let html: String
        let gateway: String
        var rueckrufe: Rueckrufe
        private var bereit = false
        private var renderId: String?
        private var promptRegel = WidgetPromptRegel()
        private var hostGeladen = false
        private var timer: Task<Void, Never>?
        private static var renderNr = 0

        init(adresse: URL, html: String, gateway: String, rueckrufe: Rueckrufe) {
            self.adresse = adresse; self.html = html; self.gateway = gateway; self.rueckrufe = rueckrufe
        }

        private var origin: String {
            var c = URLComponents(url: adresse, resolvingAgainstBaseURL: false)
            c?.path = ""; c?.query = nil; c?.fragment = nil
            return c?.string ?? ""
        }

        func starte() {
            let daten = (try? JSONSerialization.data(withJSONObject: [adresse.absoluteString, origin])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let seite = """
            <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}
            iframe{border:0;display:block;width:100%;height:100%;background:transparent;color-scheme:light}</style></head><body>
            <iframe id="f" title="Widget" sandbox="allow-scripts allow-same-origin allow-forms" referrerpolicy="origin"></iframe>
            <script>
            (function(){
              var C=\(daten.replacingOccurrences(of: "</", with: "<\\/")), f=document.getElementById('f'), port=null;
              function hoch(o){window.webkit.messageHandlers.w.postMessage(o)}
              window.__an=function(m){if(f.contentWindow)f.contentWindow.postMessage(m,C[1])};
              window.addEventListener('message',function(e){
                if(e.source!==f.contentWindow||e.origin!==C[1])return;
                var d=e.data; if(!d||typeof d!=='object')return;
                if(d.type==='openclaw:widget-bridge-port-offer'){if(e.ports[0])e.ports[0].close();return}
                if(d.type==='openclaw:widget-prompt-offer'){
                  var p=e.ports[0]; if(!p||port){if(p)p.close();return}
                  port=p;
                  p.addEventListener('message',function(m){var x=m.data;if(!x||x.type!=='openclaw:widget-prompt'||typeof x.prompt!=='string')return;
                    hoch({art:'prompt',prompt:x.prompt,fokus:document.activeElement===f})});
                  p.start(); p.postMessage({type:'openclaw:widget-prompt-host-ready'}); return}
                hoch({art:'nachricht',daten:d});
              });
              f.src=C[0];
            })();
            </script></body></html>
            """
            web?.loadHTMLString(seite, baseURL: URL(string: gateway))
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, !self.bereit else { return }
                self.rueckrufe.zeitueberschreitung()
            }
        }

        func beende() { timer?.cancel(); web?.navigationDelegate = nil; web?.stopLoading() }

        private func senden(_ m: [String: Any]) {
            guard let d = try? JSONSerialization.data(withJSONObject: m), let j = String(data: d, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.__an(\(j))", completionHandler: nil)
        }

        private func thema() {
            senden(WidgetThema.nachricht)
            senden(WidgetThema.chatHost)
        }

        func empfange(_ body: Any) {
            guard let o = body as? [String: Any] else { return }
            if o["art"] as? String == "prompt" {
                if let t = promptRegel.pruefe(o["prompt"], fokus: (o["fokus"] as? Bool) == true) { rueckrufe.vorschlag(t) }
                return
            }
            guard let d = o["daten"] as? [String: Any] else { return }
            switch d["method"] as? String {
            case "ui/notifications/sandbox-proxy-ready":
                bereit = true; timer?.cancel()
                Self.renderNr += 1
                let id = "r\(Self.renderNr)-\(String(Int(Date().timeIntervalSince1970 * 1000), radix: 36))"
                renderId = id
                senden(["jsonrpc": "2.0", "method": "ui/notifications/sandbox-resource-ready", "params": ["html": html, "renderId": id]])
                return
            case "ui/notifications/sandbox-resource-loaded":
                if (d["params"] as? [String: Any])?["renderId"] as? String == renderId { rueckrufe.geladen(); thema() }
                return
            default: break
            }
            switch d["type"] as? String {
            case "openclaw:widget-bridge-ready": thema()
            case "openclaw:widget-size": if let h = WidgetQuelle.hoehe(aus: d) { rueckrufe.hoehe(h) }
            case "openclaw:widget-runtime-error": if let m = d["message"] as? String { rueckrufe.laufFehler(String(m.prefix(300))) }
            default: break
            }
        }

        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let ziel = a.targetFrame else { decisionHandler(.cancel); return }
            if ziel.isMainFrame {
                decisionHandler(hostGeladen ? .cancel : .allow)
                hostGeladen = true
                return
            }
            let url = a.request.url
            let ok = url?.scheme == "about" || url?.scheme == "blob" || WidgetQuelle.erlaubt(url, gateway: gateway)
            decisionHandler(ok ? .allow : .cancel)
        }
    }
}

struct WidgetKarte: View {
    var quelle: WidgetRahmen.Quelle
    var titel: String
    var modus: WidgetQuelle.Modus = .chat
    var anzeige: AnzeigeInfo?
    var onEntfernen: (() -> Void)?
    @EnvironmentObject private var ansichten: AnsichtModell
    @State private var html: String?

    var body: some View {
        VStack(spacing: 0) {
            WidgetRahmen(quelle: quelle, titel: titel, modus: modus, anzeige: anzeige != nil, onHtml: { html = $0 })
            if let a = anzeige { AnzeigeFussView(info: a).padding(.horizontal, 16).padding(.top, 6) }
            HStack(spacing: 6) {
                Text(titel).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).lineLimit(1)
                Spacer(minLength: 6)
                if anzeige == nil {
                    Button("Groß ansehen") { gross() }.buttonStyle(KartenKnopfStil(leise: true)).accessibilityIdentifier("gross-ansehen")
                }
                if let weg = onEntfernen {
                    Button(action: weg) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Farbe.ink2).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help("Entfernen").accessibilityLabel("Entfernen")
                }
            }
            .padding(.top, 8).padding(.bottom, 8).padding(.leading, 18).padding(.trailing, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.067)).frame(height: 1) }
        }
        .background(Farbe.papier)
        .clipShape(RoundedRectangle(cornerRadius: modus == .pin ? 20 : 22, style: .continuous))
        .shadow(color: Farbe.schatten, radius: 15, y: 10)
        .karteEin()
        .accessibilityIdentifier("widgetkarte")
    }

    private func gross() {
        switch quelle {
        case .ansicht(let id): ansichten.oeffne(.widget(titel: titel, docId: id))
        case .html(let h, _): ansichten.oeffne(.html(titel: titel, html: h))
        }
    }
}
