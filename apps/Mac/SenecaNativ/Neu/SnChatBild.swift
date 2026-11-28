import AppKit
import SwiftUI

struct SnChatBild: View {
    var stand: SenecaStand
    var agent: String
    var frageId: String?
    var strom: String?
    @StateObject private var store = SenecaStore()

    private var key: String { "agent:\(agent):main" }

    var body: some View {
        SnChatBildInhalt(stand: stand, agent: agent, frage: SnChatSeite.mehrFrage(stand, agent: agent, id: frageId), chat: store.chat, verlauf: store.chat.speicher)
            .task { await spiele() }
    }

    private func spiele() async {
        guard let pfad = strom, let d = try? Data(contentsOf: URL(fileURLWithPath: pfad)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { store.chat.speicher.oeffne(key); return }
        store.isConnected = true
        ChatPartner.agentNamen = Dictionary((stand.team ?? []).compactMap { m in m.id.map { ($0, m.name) } }, uniquingKeysWith: { a, _ in a })
        store.chat.speicher.ersetze(key, zeilen: j["vorher"] as? [[String: Any]] ?? [])
        store.chat.speicher.oeffne(key)
        guard let frage = j["frage"] as? String else { return }
        let e = (j["ereignisse"] as? [[String: Any]] ?? []).map { ($0["ms"] as? Double ?? 0, $0["event"] as? String ?? "chat", $0["payload"] as? [String: Any] ?? [:]) }
        #if DEBUG
        if let log = ProcessInfo.processInfo.environment["SENECA_CHAT_ABLAUF"] { await ablauf(frage, e, log); return }
        try? await Task.sleep(for: .milliseconds(Int((j["start_ms"] as? Double) ?? 1500)))
        await store.chat.spieleWieder(frage, sitzung: key, ereignisse: e)
        #endif
    }

    #if DEBUG
    private func ablauf(_ frage: String, _ e: [(Double, String, [String: Any])], _ log: String) async {
        func warte(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func flaeche(_ v: NSView) -> NSScrollView? {
            if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 200 { return s }
            return v.subviews.lazy.compactMap { flaeche($0) }.first
        }
        var p: [String] = []
        await warte(3200)
        guard let host = NSApp.windows.first?.contentView, let sv = flaeche(host) else { p.append("keine Scroll-Fläche"); try? p.joined(separator: "\n").write(toFile: log, atomically: true, encoding: .utf8); return }
        func setze(_ y: CGFloat) { sv.contentView.scroll(to: NSPoint(x: 0, y: y)); sv.reflectScrolledClipView(sv.contentView) }
        let unten = { max(0, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height) }
        setze(unten()); p.append(String(format: "start unten y=%.0f hoehe=%.0f", unten(), sv.documentView?.frame.height ?? 0))
        await warte(900)
        var y = unten(), n = 0
        while y > 0 { y = max(0, y - 22); setze(y); n += 1; await warte(16) }
        p.append("nach oben in \(n) Schritten, y=\(Int(sv.contentView.bounds.minY))")
        await warte(1200)
        NotificationCenter.default.post(name: .snProbeWahl, object: 1)
        await warte(900)
        NotificationCenter.default.post(name: .snProbeWahl, object: 1, userInfo: ["senden": true])
        p.append("Frage beantwortet (Zeile 2)")
        await warte(1800)
        let vorher = store.chat.speicher.bloecke.count, t0 = CFAbsoluteTimeGetCurrent()
        var eigene: Double?, zeile: Double?, zeichen: Double?
        let lauf = Task { await store.chat.spieleWieder(frage, sitzung: key, ereignisse: e) }
        while zeichen == nil, CFAbsoluteTimeGetCurrent() - t0 < 30 {
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if eigene == nil, store.chat.speicher.bloecke.count > vorher { eigene = ms }
            if zeile == nil, store.chat.lives[key] != nil { zeile = ms }
            if zeichen == nil, !(store.chat.lives[key]?.text ?? "").isEmpty { zeichen = ms }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(4))
        }
        p.append(String(format: "Senden bis eigene Nachricht im Bild: %.0f ms", eigene ?? -1))
        p.append(String(format: "Senden bis Arbeitszeile im Bild: %.0f ms", zeile ?? -1))
        p.append(String(format: "Senden bis erstes Zeichen der Antwort (Probe-Strom: erstes Textereignis bei %.0f ms): %.0f ms", e.first { $0.1 == "chat" || (($0.2["stream"] as? String) == "assistant") }?.0 ?? -1, zeichen ?? -1))
        try? p.joined(separator: "\n").write(toFile: log, atomically: true, encoding: .utf8)
        await lauf.value
    }
    #endif

}

private struct SnChatBildInhalt: View {
    var stand: SenecaStand
    var agent: String
    var frage: SenecaStand.Frage?
    @ObservedObject var chat: ChatService
    @ObservedObject var verlauf: ChatSpeicher

    var body: some View {
        GeometryReader { g in
            let seneca = agent == Hauptagent.id
            let (links, breite, rand) = SnChatSeite.spalte(g.size.width, seneca: seneca, frage: frage != nil)
            let name = stand.team?.first { $0.id == agent }?.name ?? "Seneca"
            let lauf = chat.lives[verlauf.sitzung].map { var k = $0; k.text = ""; k.activity = nil; return k }
            ZStack(alignment: .topLeading) {
                SnGespraechLeiste(stand: stand, aktiv: agent, waehle: { _ in }, neu: {}, fragt: frage)
                    .padding(.leading, 40).padding(.top, 108).padding(.bottom, 40).frame(height: g.size.height, alignment: .top)
                VStack(alignment: .leading, spacing: 24) {
                    VerlaufView(verlauf: verlauf, chat: chat, lauf: lauf, name: name, hinweis: nil, erneut: { _ in }, stand: stand, agent: agent,
                                oben: frage.map { SnFrageMehr(frage: $0, stand: stand) }, fragenOben: seneca ? [] : GL.fragen(stand, von: name).filter { $0.id != frage?.id })
                        .equatable()
                        .layoutPriority(1)
                    if let f = frage {
                        SnFrageMehrKnoepfe(frage: f, stand: stand, antworte: { _ in }, zuruecknehmen: {}, andereZeit: {})
                        SnFrageMehrFuss(frage: f) { _ in }
                    }
                }
                .frame(width: breite).padding(.leading, links).padding(.top, 92).padding(.bottom, SnDock.freiraum).frame(height: g.size.height)
                if rand > 0 { SnGespraechRand(stand: stand, agent: agent, frage: frage, zuProjekten: {}).padding(.leading, g.size.width - 40 - rand).padding(.top, 108) }
                let film = ProcessInfo.processInfo.environment["SENECA_FILM"] != nil
                HStack(spacing: 14) {
                    SnAnZeile(name: name, seneca: seneca)
                    SnAnZeile.platzhalter(seneca: seneca)
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
                }
                .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 14).frame(width: breite)
                .background { if film { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.09)) } }
                .modifier(SnGlasWenn(an: !film))
                .padding(.leading, links).padding(.top, g.size.height - 40 - 62)
                if !film { SnOrteKapsel(aktiv: .gespraeche, fragen: SnOrt.fragen(stand), waehle: { _ in }).padding(.top, 24).frame(width: g.size.width) }
            }
        }
    }
}

private struct SnGlasWenn: ViewModifier {
    var an: Bool
    func body(content: Content) -> some View {
        if an { content.snGlas(RoundedRectangle(cornerRadius: 22, style: .continuous)) } else { content }
    }
}
