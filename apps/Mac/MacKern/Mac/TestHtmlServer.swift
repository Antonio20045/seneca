import Foundation
import Network

final class TestHtmlServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "seneca.test-html-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var verbindungen: [ObjectIdentifier: NWConnection] = [:]
    private var pfade: [String] = []
    private(set) var port: UInt16 = 0
    var origin: String { "http://127.0.0.1:\(port)" }

    func angeforderte() -> [String] { lock.lock(); defer { lock.unlock() }; return pfade }

    func starte() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: .any)
        let bereit = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { [weak self, weak l] state in
            if case .ready = state { self?.port = l?.port?.rawValue ?? 0; bereit.signal() }
            if case .failed = state { bereit.signal() }
        }
        l.newConnectionHandler = { [weak self] c in self?.neu(c) }
        l.start(queue: queue)
        guard bereit.wait(timeout: .now() + 5) == .success, port != 0 else { throw URLError(.cannotConnectToHost) }
        listener = l
    }

    func stoppe() {
        listener?.cancel(); listener = nil
        lock.lock(); let alle = verbindungen.values; verbindungen = [:]; lock.unlock()
        for c in alle { c.cancel() }
    }

    private func neu(_ c: NWConnection) {
        lock.lock(); verbindungen[ObjectIdentifier(c)] = c; lock.unlock()
        c.stateUpdateHandler = { [weak self] s in
            if case .cancelled = s { self?.lock.lock(); self?.verbindungen[ObjectIdentifier(c)] = nil; self?.lock.unlock() }
        }
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let kopf = String(data: data, encoding: .utf8) else { c.cancel(); return }
            let zeile = kopf.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let teile = zeile.split(separator: " ")
            let pfad = teile.count > 1 ? String(teile[1]) : "/"
            self.lock.lock(); self.pfade.append(pfad); self.lock.unlock()
            let (status, inhalt) = pfad.hasPrefix("/mcp-app-sandbox") ? ("200 OK", Self.bruecke) : ("404 Not Found", "nicht vorhanden")
            let body = Data(inhalt.utf8)
            let antwort = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            c.send(content: Data(antwort.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    static let bruecke = """
    <!doctype html><html><head><meta charset="utf-8"><title>sandbox</title>
    <style>html,body{margin:0;height:100%;background:transparent}iframe{border:0;width:100%;height:100%;display:block;background:transparent}</style></head>
    <body><iframe id="w" sandbox="allow-scripts" title="widget"></iframe>
    <script>
    (function(){
      var f=document.getElementById('w');
      window.addEventListener('message',function(e){
        var d=e.data;
        if(e.source===window.parent){
          if(d&&d.method==='ui/notifications/sandbox-resource-ready'&&d.params){
            var id=d.params.renderId;
            f.onload=function(){window.parent.postMessage({jsonrpc:'2.0',method:'ui/notifications/sandbox-resource-loaded',params:{renderId:id}},'*');};
            f.srcdoc=d.params.html||'';
          } else if(d&&typeof d.type==='string'&&d.type.indexOf('openclaw:')===0&&f.contentWindow){
            f.contentWindow.postMessage(d,'*');
          }
        } else if(e.source===f.contentWindow){
          window.parent.postMessage(d,'*',e.ports&&e.ports.length?Array.prototype.slice.call(e.ports):undefined);
        }
      });
      window.parent.postMessage({jsonrpc:'2.0',method:'ui/notifications/sandbox-proxy-ready'},'*');
    })();
    </script></body></html>
    """

    static let beispielWidget = """
    <!doctype html><html><head><meta charset="utf-8">
    <style>
    :root{--surface:#fff;--card:#f3f7fc;--text:#14284a;--text-strong:#0d2a52;--muted:#5a7398;--accent:#2f6db5;--accent-fill:#0d2a52;--ok:#2e9e5b;--warn:#c58a12;--radius:14px;--font-body:system-ui,sans-serif}
    html,body{margin:0}
    body{padding:18px 20px 20px;background:var(--surface);color:var(--text);font:14px/1.45 var(--font-body)}
    h1{margin:0 0 2px;font-size:19px;color:var(--text-strong)}
    p{margin:0 0 14px;color:var(--muted);font-size:13px}
    .zeile{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:14px}
    .z{background:var(--card);border-radius:var(--radius);padding:10px 12px}
    .z b{display:block;font-size:23px;color:var(--text-strong)}
    .z span{font-size:12px;color:var(--muted)}
    .bar{display:flex;align-items:flex-end;gap:8px;height:84px;margin-bottom:12px}
    .bar i{flex:1;background:var(--accent);border-radius:6px 6px 2px 2px;opacity:.9}
    small{display:block;margin-top:12px;color:var(--muted)}
    </style></head><body>
    <h1>Wochenverbrauch</h1><p>Erfundene Beispieldaten, nur zum Testen des Widget-Rahmens.</p>
    <div class="zeile"><div class="z"><b>128</b><span>kWh gesamt</span></div><div class="z"><b>18,3</b><span>pro Tag</span></div><div class="z"><b style="color:var(--ok)">-6 %</b><span>zur Vorwoche</span></div></div>
    <div class="bar"><i style="height:62%"></i><i style="height:78%"></i><i style="height:54%"></i><i style="height:91%"></i><i style="height:70%"></i><i style="height:40%"></i><i style="height:48%"></i></div>
    <small id="t">Thema: noch nicht erhalten</small>
    <script>
    function hoehe(){var h=Math.ceil(document.body.getBoundingClientRect().height);window.parent.postMessage({type:'openclaw:widget-size',height:h},'*');}
    window.addEventListener('message',function(e){
      var d=e.data;
      if(d&&d.type==='openclaw:widget-theme'){
        var r=document.documentElement.style;for(var k in d.tokens){r.setProperty('--'+k,d.tokens[k]);}
        document.getElementById('t').textContent='Thema: '+d.mode+' · Akzent '+(d.tokens['accent']||'');
        hoehe();
      }
    });
    window.parent.postMessage({type:'openclaw:widget-bridge-ready'},'*');
    hoehe();
    </script></body></html>
    """
}
