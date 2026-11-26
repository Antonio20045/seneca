import SwiftUI

struct GebuendelterSchritt: Identifiable {
    var id: Int
    var schritt: Schritt
    var n = 1
}

func buendeln(_ schritte: [Schritt]) -> [GebuendelterSchritt] {
    var out: [GebuendelterSchritt] = []
    for s in schritte {
        if let l = out.last, s.art != .gedanke, l.schritt.text == s.text, l.schritt.detail == s.detail {
            out[out.count - 1].n += 1
            continue
        }
        out.append(GebuendelterSchritt(id: out.count, schritt: s))
    }
    return out
}

func agentName(_ id: String?) -> String {
    guard let id, !id.isEmpty else { return "" }
    if id == "main" { return "Seneca" }
    return id.prefix(1).uppercased() + id.dropFirst()
}

private struct Zeichen: View {
    var symbol: String
    var farbe: Color = Farbe.ink3
    var body: some View { Image(systemName: symbol).font(.system(size: 11, weight: .regular)).foregroundStyle(farbe).frame(width: 14, height: 14) }
}

private struct Pfeil: View {
    var offen: Bool
    var body: some View {
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Farbe.ink3).opacity(0.7)
            .rotationEffect(.degrees(offen ? 180 : 0))
            .animation(Kurve.ease(0.35), value: offen)
    }
}

struct SpurView: View {
    var zug: Zug
    var frisch: Bool
    #if DEBUG
    @State private var offen = MacPfade.profil == .demo && ProcessInfo.processInfo.environment["SENECA_TEST_SPUR_OFFEN"] == "1"
    #else
    @State private var offen = false
    #endif
    @State private var ueber = false

    static func kurzText(_ schritte: [Schritt]) -> String {
        let n = schritte.filter { $0.art != .gedanke }.count
        return n == 0 ? "Gedankengang" : n == 1 ? "1 Schritt" : "\(n) Schritte"
    }

    private var dauer: Double {
        if let von = zug.von, von != 0, let ts = zug.antwort?.ts, ts != 0 { return ts - von }
        if let von = zug.von, von != 0, let bis = zug.bis, bis != 0 { return bis - von }
        return 0
    }

    var body: some View {
        if !zug.schritte.isEmpty {
            let z = Arbeitsspur.zusammenfassung(zug.schritte, dauerMs: dauer)
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(Kurve.ease(0.4)) { offen.toggle() } } label: {
                    HStack(spacing: 13) {
                        HStack(spacing: 4) {
                            ForEach(Array(zug.schritte.suffix(5).enumerated()), id: \.offset) { i, s in
                                Perle(art: s.art, groesse: 6).perleLandet(frisch, index: i)
                            }
                        }
                        Text(SpurView.kurzText(zug.schritte)).fixedSize()
                        if !z.dauer.isEmpty { Text("· " + z.dauer).foregroundStyle(Farbe.ink4).monospacedDigit() }
                        Pfeil(offen: offen).padding(.leading, -6)
                    }
                    .font(Schrift.grotesk(12.5)).foregroundStyle(offen || ueber ? Farbe.ink2 : Farbe.ink3)
                    .lineLimit(1)
                    .padding(.leading, 7).padding(.trailing, 12).padding(.vertical, 5)
                    .background(offen || ueber ? Farbe.pille : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { ueber = $0 }
                .padding(.leading, -7)
                .spurLandet(frisch)
                .accessibilityLabel(offen ? "Arbeitsweg zuklappen" : "Ansehen, wie die Antwort entstanden ist")
                .accessibilityValue(z.teile.map(\.text).joined(separator: ", "))
                .accessibilityIdentifier("spurzeile")
                if offen { liste }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var liste: some View {
        let reihe = buendeln(zug.schritte)
        let tech = zug.schritte.contains { ($0.tech ?? "").isEmpty == false }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(reihe) { r in
                if r.schritt.art == .gedanke {
                    HStack(alignment: .top, spacing: 9) {
                        Zeichen(symbol: SchrittArt.gedanke.symbol, farbe: Farbe.gedankeZeichen).padding(.top, 2.5)
                        Text(r.schritt.text).font(Schrift.serif(15.5, kursiv: true)).foregroundStyle(Farbe.ink2).lineLimit(3)
                            .help(r.schritt.titel ?? "")
                    }
                } else {
                    HStack(alignment: .top, spacing: 9) {
                        Zeichen(symbol: r.schritt.art.symbol, farbe: r.schritt.art.farbe).padding(.top, 2.5)
                        HStack(spacing: 0) {
                            Text(r.schritt.text)
                            if r.n > 1 { Text(" ×\(r.n)").foregroundStyle(Farbe.ink3).monospacedDigit() }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        if let d = r.schritt.detail, !d.isEmpty {
                            Text(d).font(Schrift.grotesk(12)).lineLimit(1).truncationMode(.tail)
                                .padding(.horizontal, 7)
                                .background(Farbe.kapsel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .help(r.schritt.titel ?? d)
                        }
                        Spacer(minLength: 14)
                        if let t = r.schritt.tech, !t.isEmpty {
                            Text(t.ersetze(#"^mcp__[^_]+(?:_[^_]+)*?__"#, "")).font(Schrift.mono(10.5)).foregroundStyle(Farbe.ink4).lineLimit(1)
                        }
                    }
                }
            }
            if tech { Text("Grau steht der technische Name jedes Schritts.").font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink4).padding(.top, 2) }
        }
        .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
        .padding(.leading, 16).padding(.vertical, 6).padding(.trailing, 4)
        .overlay(alignment: .leading) { Rectangle().fill(Farbe.linie).frame(width: 1) }
        .padding(.leading, 6).padding(.top, 6).padding(.bottom, 4)
        .erscheint(.auf)
        .accessibilityIdentifier("spurliste")
    }
}

struct EreignisZeileView: View {
    var e: ZugEreignis
    var klein = false
    @State private var offen = false

    private var von: String { agentName(e.von) }
    private var titel: String {
        switch e.art {
        case .meldung:
            return e.titel == "Meldung" || e.titel == "Rückmeldung" ? "\(e.titel) von \(von.isEmpty ? "einem Agenten" : von)" : "\(e.titel)\(von.isEmpty ? "" : " · \(von)")"
        default: return e.titel
        }
    }
    private var symbol: String {
        e.art == .fehler || e.warnung ? "exclamationmark.triangle" : e.art == .automation ? "clock" : e.art == .meldung ? "arrow.turn.down.right" : "info.circle"
    }
    private var warnend: Bool { e.art == .fehler || e.warnung }
    private var vorschau: String {
        guard e.art == .meldung, let t = e.text else { return "" }
        return String(t.ersetzeAlle(#"[#*`_>|]"#, "").ersetzeAlle(#"\s+"#, " ").jsTrim.jsSlice(0, 110))
    }
    private var kannAuf: Bool { if let t = e.text?.jsTrim, !t.isEmpty, t != e.titel { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { if kannAuf { withAnimation(Kurve.ease(0.3)) { offen.toggle() } } } label: {
                HStack(spacing: 8) {
                    Zeichen(symbol: symbol, farbe: warnend ? Farbe.koralle : Farbe.himmel)
                    Text(titel)
                    if let ts = e.ts, ts != 0 { Text(Formate.hhmm(ts)).foregroundStyle(Farbe.ink4).monospacedDigit() }
                    if kannAuf { Pfeil(offen: offen) }
                }
                .font(Schrift.grotesk(klein ? 12 : 12.5)).foregroundStyle(Farbe.ink2)
                .lineLimit(1)
                .padding(.leading, klein ? 9 : 10).padding(.trailing, klein ? 11 : 13).padding(.vertical, klein ? 4 : 6)
                .background(warnend ? Farbe.warnFlaeche : Farbe.pille, in: Capsule())
                .overlay(Capsule().stroke(warnend ? Farbe.warnKante : Farbe.linie, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!kannAuf)
            if !offen, !vorschau.isEmpty {
                Text(vorschau + "…").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(1)
                    .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Farbe.linie).frame(width: 1) }
                    .padding(.leading, 10).frame(maxWidth: 540, alignment: .leading)
            }
            if offen, let t = e.text {
                Group {
                    if e.art == .meldung { SenecaTextView(text: t, live: false) }
                    else { Text(t).font(Schrift.mono(12)).foregroundStyle(Farbe.ink2).textSelection(.enabled) }
                }
                .padding(.horizontal, 17).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
                .erscheint(.auf)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ereignis-\(e.art.rawValue)")
    }
}

struct KanalNachrichtView: View {
    var e: ZugEreignis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Zeichen(symbol: "person.wave.2", farbe: Farbe.himmel)
                Text(e.titel).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink2)
                if let ts = e.ts, ts != 0 { Text(Formate.hhmm(ts)).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink4).monospacedDigit() }
            }
            .lineLimit(1)
            if let t = e.text?.jsTrim, !t.isEmpty {
                Text(t)
                    .font(Schrift.grotesk(15, .light)).foregroundStyle(Farbe.ink).lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
                    .frame(maxWidth: 440, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kanal-nachricht")
    }
}

struct AntwortKarteView: View {
    var text: String
    var ts: Double?
    var frisch: Bool
    var live = false
    var gross = false

    @State private var ueber = false
    @State private var kopiert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if live {
                let s = StromSchnitt.teile(text)
                ForEach(s.fest.indices, id: \.self) { i in
                    AntwortStueck(text: s.fest[i], art: .fest, erster: i == 0, folgtMehr: true, gross: gross).equatable()
                }
                AntwortStueck(text: s.offen, art: .offen, erster: s.fest.isEmpty, folgtMehr: false, gross: gross)
                BlinkStrich().padding(.top, 6)
            } else {
                AntwortStueck(text: text, art: .fertig, erster: true, folgtMehr: false, gross: gross, frisch: frisch, ts: ts)
                kopierKnopf.padding(.top, 8)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .entfaltet(frisch)
        .onHover { ueber = $0 }
        .accessibilityIdentifier("antwort")
    }

    private var kopierKnopf: some View {
        Button {
            let alsMarkdown = NSEvent.modifierFlags.contains(.option)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(alsMarkdown ? KopierText.markdown(text) : KopierText.text(text), forType: .string)
            kopiert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { kopiert = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kopiert ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .medium))
                Text(kopiert ? "Kopiert" : "Kopieren").font(Schrift.grotesk(11.5))
            }
            .foregroundStyle(kopiert ? Farbe.gruen : Farbe.ink3)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Farbe.pille, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(ueber || kopiert ? 1 : 0)
        .animation(Kurve.ease(0.15), value: ueber)
        .help("Kopieren (⌥ für Markdown)")
        .accessibilityLabel("Antwort kopieren")
        .accessibilityIdentifier("antwort-kopieren")
    }
}

struct AntwortStueck: View, Equatable {
    var text: String
    var art: Inhaltsspeicher.Art
    var erster: Bool
    var folgtMehr: Bool
    var gross: Bool
    var frisch = false
    var ts: Double?

    private var live: Bool { art != .fertig }

    var body: some View {
        ForEach(Array(teile(text).enumerated()), id: \.offset) { i, teil in
            switch teil {
            case .text(let t): textTeil(t, platz: i)
            case .karte(let k):
                KarteAnsicht(karte: k, ort: live ? .panel : .chat, kartenId: live ? nil : ts.map { "chat-\(Int($0))-\(i)" })
                    .padding(.vertical, 6)
            case .baut: BautKarte().padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private func textTeil(_ t: String, platz: Int) -> some View {
        if erster, platz == 0 {
            let (kern, rest) = Antwortform.kernUndRest(t, folgtMehr: folgtMehr)
            if let kern {
                Text(MDInline.attributed(kern)).font(Schrift.serif(gross ? 32 : 24)).foregroundStyle(gross ? Farbe.ink1 : Farbe.ink2).lineHeight(.exact(points: gross ? 40 : 30))
                    .padding(.bottom, rest.isEmpty ? (folgtMehr ? 1 : 0) : 11)
                    .kernRein(frisch)
            }
            if !rest.isEmpty { inhalt(rest).kernRein(frisch, dauer: 0.7, verzoegerung: 0.34) }
        } else if platz == 0, live {
            inhalt(t).padding(.top, 10)
        } else {
            inhalt(t).padding(.vertical, 4)
        }
    }

    @ViewBuilder private func inhalt(_ t: String) -> some View {
        let gebaut = art == .fertig ? Inhaltsspeicher.teile(t) : Inhaltsspeicher.baue(t, art: art)
        if !gebaut.allSatisfy(\.istLeer) { Abschnitte(teile: gebaut, live: live) }
    }
}

struct LaufQuelle {
    let chat: ChatService
    let key: String
    let frisch: FrischMerker
}

struct LiveZugView: View {
    @ObservedObject private var chat: ChatService
    private let key: String
    private let frisch: FrischMerker
    var zug: Zug?
    var name: String
    @State private var offen = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    init(quelle: LaufQuelle, zug: Zug?, name: String) {
        _chat = ObservedObject(wrappedValue: quelle.chat)
        key = quelle.key
        frisch = quelle.frisch
        self.zug = zug
        self.name = name
    }

    final class Merker { var text = ""; var w = Werkzeugtext.Ergebnis(rest: "", schritte: [], bereinigt: false); var gefuellt = false; var zuletzt = Date(); var gezeigt = false }
    @State private var merker = Merker()

    private func bereinigt(_ live: ChatLive) -> Werkzeugtext.Ergebnis {
        if merker.gefuellt, merker.text == live.text { return merker.w }
        let w = Werkzeugtext.bereinige(live.text)
        merker.text = live.text; merker.w = w; merker.gefuellt = true; merker.zuletzt = Date()
        return w
    }

    var body: some View {
        if let live = chat.lives[key] { laufZeile(live) }
    }

    private func laufZeile(_ live: ChatLive) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let nun = ctx.date
            let w = bereinigt(live)
            let hist = (zug?.schritte ?? []).filter { $0.art != .gedanke }
            let alle = hist + w.schritte
            let ruhigMs = nun.timeIntervalSince(merker.zuletzt) * 1000
            let sofort = alle.isEmpty && !w.rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let schreibt = merker.gezeigt || sofort || Antwortform.antwortartig(w.rest, ruhigMs: ruhigMs)
            let _ = (merker.gezeigt = schreibt && !w.rest.isEmpty)
            let _ = (frisch.schrieb = schreibt)
            let angekommen = chat.speicher.zustand(sitzung: live.sessionKey, schluessel: live.schluessel).map { $0 >= .angekommen } ?? (live.phase != .sending)
            let zeile = Laufzeile.text(name: name, phase: live.phase, angekommen: angekommen, taetigkeit: live.activity, schritte: alle.count,
                                       schreibt: schreibt, seit: max(0, nun.timeIntervalSince(live.startedAt)), verbunden: chat.store?.isConnected ?? true)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(ruhig ? .easeOut(duration: 0.15) : Kurve.ease(0.3)) { offen.toggle() } } label: {
                        HStack(spacing: 12) {
                            Kugel()
                            Text(zeile).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink).monospacedDigit().lineLimit(1)
                            Spacer(minLength: 8)
                            if !alle.isEmpty {
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Farbe.ink3)
                                    .rotationEffect(.degrees(offen ? 180 : 0))
                            }
                        }
                        .padding(.leading, 12).padding(.trailing, 18).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(alle.isEmpty)
                    if offen && !alle.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(alle.suffix(12).enumerated()), id: \.offset) { _, s in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle().fill(Farbe.ink4).frame(width: 4, height: 4).offset(y: -2)
                                    Text(s.text).foregroundStyle(Farbe.ink2)
                                    if let d = s.detail, !d.isEmpty { Text(d).foregroundStyle(Farbe.ink3).lineLimit(1) }
                                }
                                .font(Schrift.grotesk(13))
                            }
                        }
                        .padding(.leading, 40).padding(.trailing, 18).padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: 470, alignment: .leading)
                .background(Farbe.pilleLauf, in: RoundedRectangle(cornerRadius: offen ? 22 : 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: offen ? 22 : 30, style: .continuous).stroke(Farbe.kantePille, lineWidth: 1))
                .shadow(color: Farbe.schatten, radius: 17, y: 12)
                .erscheint(.laufrein)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(zeile)
                .accessibilityHint(alle.isEmpty ? "" : "Zeigt die Schritte")
                .accessibilityIdentifier("laufzeile")
                if schreibt { AntwortKarteView(text: w.rest, ts: nil, frisch: false, live: true, gross: true) }
            }
        }
    }
}

struct ZugView: View, Equatable {
    var zug: Zug
    var status: NachrichtStatus? = nil
    var zurAntwort: () -> Void = {}
    var lauf: LaufQuelle?
    var frisch: FrischArt?
    var zustand: ZustellZustand?
    var neu: Bool
    var name: String
    var gross = false
    var nurAntwort = false
    var quittungen: [Quittung] = []
    var erneut: () -> Void

    static func == (a: ZugView, b: ZugView) -> Bool {
        a.quittungen == b.quittungen && a.zug == b.zug && a.status == b.status && (a.lauf == nil) == (b.lauf == nil) && a.frisch == b.frisch && a.zustand == b.zustand
            && a.neu == b.neu && a.name == b.name && a.gross == b.gross && a.nurAntwort == b.nurAntwort
    }

    private var laeuft: Bool { zug.laeuft && lauf != nil }

    static func antwortId(_ zugId: String) -> String { "antwort-" + zugId }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let _ = Messung.markeEinmal("erster Zug berechnet")
            switch zug.start {
            case .user(_, let text, let ts, let pending)?:
                frage(text, pending: pending, ts: ts)
            case .ereignis(let e)?:
                if Unterhaltung.istAuftragsErgebnis(zug) {
                    Text(Unterhaltung.auftragsVermerk).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).padding(.leading, 2)
                        .accessibilityIdentifier("auftrags-vermerk")
                } else if e.art == .nachricht {
                    KanalNachrichtView(e: e)
                } else {
                    EreignisZeileView(e: e)
                }
            default: EmptyView()
            }
            if laeuft, let lauf {
                LiveZugView(quelle: lauf, zug: zug, name: name)
            } else {
                if !nurAntwort { SpurView(zug: zug, frisch: frisch != nil) }
                if let a = zug.antwort {
                    if let an = Unterhaltung.antwortAn(zug) {
                        Text(an).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).padding(.leading, 2)
                            .accessibilityIdentifier("antwort-an")
                    }
                    AntwortKarteView(text: a.text, ts: a.ts, frisch: frisch == .voll, gross: gross).id(Self.antwortId(zug.id))
                } else if !nurAntwort, !zug.schritte.isEmpty, zug.widgets.isEmpty {
                    Text("Ohne Abschlussmeldung beendet").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink4).padding(.leading, 2)
                }
            }
            if !laeuft {
                ForEach(zug.widgets, id: \.id) { w in
                    WidgetKarte(quelle: .ansicht(w.viewId), titel: w.titel.isEmpty ? "Ansicht" : w.titel)
                }
            }
            ForEach(zug.bilder, id: \.id) { b in
                Label(b.alt, systemImage: "photo").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2)
            }
            if !nurAntwort { ForEach(zug.hinweise, id: \.id) { h in EreignisZeileView(e: h, klein: true) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func frage(_ text: String, pending: Bool, ts: Double?) -> some View {
        let teile = ChatAnhang.zerlege(text)
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(teile.namen.enumerated()), id: \.offset) { _, n in SnAnhangChip(name: n) }
                if !teile.text.isEmpty || teile.namen.isEmpty {
                    Text(teile.text)
                        .font(Schrift.grotesk(17, .light)).foregroundStyle(Farbe.ink).lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color(hex: 0x142B4C), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .frame(maxWidth: 440, alignment: .trailing)
            .opacity(pending && zustand != .fehlgeschlagen ? 0.8 : 1)
            .erscheint(.steigt, wenn: neu)
            if zustand != .fehlgeschlagen, let status {
                HStack(spacing: 5) {
                    Text(status.text)
                    if status == .beantwortet, zug.antwort != nil {
                        Text("·")
                        Button("Antwort ansehen", action: zurAntwort).buttonStyle(.plain).foregroundStyle(Farbe.himmel)
                    }
                }
                .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                .accessibilityIdentifier("nachrichtstatus")
            }
            ForEach(quittungen) { SnQuittung(quittung: $0, mehrere: quittungen.count > 1) }
            if zustand == .fehlgeschlagen {
                HStack(spacing: 8) {
                    Text("Nicht gesendet").font(Schrift.grotesk(12)).foregroundStyle(Farbe.koralle)
                    Button("Erneut senden", action: erneut).buttonStyle(.plain)
                        .font(Schrift.grotesk(12, .medium)).foregroundStyle(Farbe.himmel)
                }
            } else if pending, status == nil, lauf != nil, let ts {
                TimelineView(.periodic(from: .now, by: 2)) { takt in
                    if takt.date.timeIntervalSince1970 * 1000 - ts > 8000 {
                        Text("In der Reihe. Kommt dran, sobald der laufende Schritt fertig ist.").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("frage")
    }
}

enum FrischArt { case voll, weich }

struct ZwischenView: View {
    var g: Zwischendurch
    @State private var offen = false
    @State private var voll: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { withAnimation(Kurve.ease(0.3)) { offen.toggle() } } label: {
                HStack(spacing: 8) {
                    Zeichen(symbol: "tray.full", farbe: Farbe.himmel)
                    Text(g.kopf)
                    Pfeil(offen: offen)
                }
                .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
                .lineLimit(1)
                .padding(.leading, 10).padding(.trailing, 13).padding(.vertical, 6)
                .background(Farbe.pille, in: Capsule())
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("zwischendurch")
            if offen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(g.eintraege) { e in zeile(e) }
                }
                .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Farbe.linie).frame(width: 1) }
                .padding(.leading, 10).frame(maxWidth: 560, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func zeile(_ e: ZwischenEintrag) -> some View {
        let ganz = voll.contains(e.id)
        let kannMehr = (e.voll ?? "") != (e.kurz ?? "")
        VStack(alignment: .leading, spacing: 3) {
            Button {
                guard kannMehr else { return }
                withAnimation(Kurve.ease(0.25)) { if ganz { voll.remove(e.id) } else { voll.insert(e.id) } }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let ts = e.ts, ts != 0 { Text(Formate.hhmm(ts)).foregroundStyle(Farbe.ink4).monospacedDigit() }
                    Text(e.quelle.bezeichnung()).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.ink2)
                    if let k = e.kurz { Text("· " + k).foregroundStyle(Farbe.ink3).lineLimit(ganz ? 0 : 1) }
                }
                .font(Schrift.grotesk(12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ganz, let v = e.voll {
                Text(v).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2).textSelection(.enabled)
            }
        }
    }
}
