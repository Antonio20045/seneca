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
    if id == Hauptagent.id { return "Seneca" }
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
    var anfangsOffen = false
    @State private var offen = false
    @State private var ueber = false
    @State private var roh = false

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
            let k = VerlaufLogik.spur(zug.schritte, dauerMs: dauer, antwort: zug.antwort != nil)
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(Kurve.ease(0.4)) { offen.toggle() } } label: {
                    HStack(spacing: 22) {
                        Text((offen ? "▾ " : "▸ ") + k.titel).font(k.zeile.isEmpty ? Schrift.mono(12) : Schrift.grotesk(13))
                        if !k.zeile.isEmpty { Text(k.zeile).font(Schrift.mono(12)) }
                    }
                    .foregroundStyle(ueber ? TafelFarbe.zweit : TafelFarbe.leise).lineLimit(1).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { ueber = $0 }
                .spurLandet(frisch)
                .accessibilityLabel(offen ? "Arbeitsweg zuklappen" : "Ansehen, wie die Antwort entstanden ist")
                .accessibilityValue(z.teile.map(\.text).joined(separator: ", "))
                .accessibilityIdentifier("spurzeile")
                if offen { liste }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { if anfangsOffen { offen = true } }
        }
    }

    private var liste: some View {
        let reihe = buendeln(zug.schritte.filter { $0.art != .gedanke })
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(reihe) { r in Self.zeile(r.schritt.ts, r.schritt.text + (r.n > 1 ? " ×\(r.n)" : ""), roh: roh ? r.schritt.tech ?? r.schritt.titel : nil, farbe: TafelFarbe.gruen) }
                if let a = zug.antwort { Self.zeile(a.ts, "Antwort geschrieben", roh: nil, farbe: TafelFarbe.himmel) }
            }
            .padding(.leading, 4)
            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1) }
            Button(roh ? "Rohprotokoll schließen" : "Rohprotokoll öffnen") { withAnimation(Kurve.ease(0.25)) { roh.toggle() } }
                .buttonStyle(.plain).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.himmel)
        }
        .padding(.top, 6)
        .erscheint(.auf)
        .accessibilityIdentifier("spurliste")
    }

    static func zeile(_ ts: Double?, _ text: String, roh: String?, farbe: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(ts.map { Formate.hhmmss($0) } ?? "").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).monospacedDigit().frame(width: 76, alignment: .leading)
            Circle().fill(farbe).frame(width: 7, height: 7).frame(width: 14, alignment: .leading).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
            if let roh, !roh.isEmpty { Text("  " + roh).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).lineLimit(1) }
        }
        .frame(minHeight: 26)
    }
}

struct QuittungErgebnis: View {
    var quittung: SenecaStand.Quittung
    var zuruecklegen: (SenecaStand.Zuruecklegen) -> Void
    @Environment(\.festeZeit) private var festeZeit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !quittung.ergebnis.isEmpty { Text(quittung.ergebnis.joined(separator: "   ")).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.zweit) }
            HStack(spacing: 14) {
                if let z = quittung.zuruecklegen {
                    TimelineView(.periodic(from: .now, by: 1)) { t in
                        Button("Termin zurücklegen") { zuruecklegen(z) }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                            .overlay(alignment: .bottomLeading) {
                                GeometryReader { g in Rectangle().fill(TafelFarbe.himmel).frame(width: g.size.width * VerlaufLogik.anteil(z, jetzt: festeZeit ?? t.date.timeIntervalSince1970 * 1000), height: 2).frame(maxHeight: .infinity, alignment: .bottom) }
                            }
                            .clipShape(Capsule())
                    }
                }
                if let r = quittung.raus { Text(r).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise) }
            }
            .padding(.top, 2)
        }
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
        if e.art == .system, !kannAuf, !e.warnung {
            Text([e.ts.map { Formate.hhmm($0) }, titel].compactMap { $0 }.joined(separator: " · "))
                .font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).frame(maxWidth: .infinity)
        } else {
            zeile
        }
    }

    private var zeile: some View {
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
            }
        }
        .overlay(alignment: .bottomTrailing) { if !live { kopierKnopf.offset(y: 30) } }
        .frame(maxWidth: 760, alignment: .leading)
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
            Group {
            switch teil {
            case .text(let t): textTeil(t, platz: i)
            case .karte(let k):
                KarteAnsicht(karte: k)
                    .padding(.vertical, 6)
            case .baut: BautKarte().padding(.vertical, 6)
            }
            }
            .environment(\.bildZeit, ts)
        }
    }

    @ViewBuilder private func textTeil(_ t: String, platz: Int) -> some View {
        if erster, platz == 0 {
            let (kern, rest) = Antwortform.kernUndRest(t, folgtMehr: folgtMehr)
            if let kern {
                Text(MDInline.attributed(kern)).font(Schrift.serif(30)).foregroundStyle(Color.white).lineHeight(.exact(points: 34))
                    .padding(.bottom, rest.isEmpty ? (folgtMehr ? 1 : 0) : 14)
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

    init(quelle: LaufQuelle, zug: Zug?, name: String) {
        _chat = ObservedObject(wrappedValue: quelle.chat)
        key = quelle.key
        frisch = quelle.frisch
        self.zug = zug
        self.name = name
    }

    final class Merker { var text = ""; var w = Werkzeugtext.Ergebnis(rest: "", schritte: [], bereinigt: false); var gefuellt = false; var zuletzt = Date(); var gezeigt = false; var satz: String?; var satzZeit = Date.distantPast }
    @State private var merker = Merker()

    private func bereinigt(_ live: ChatLive) -> Werkzeugtext.Ergebnis {
        if merker.gefuellt, merker.text == live.text { return merker.w }
        let w = Werkzeugtext.bereinige(live.text)
        merker.text = live.text; merker.w = w; merker.gefuellt = true; merker.zuletzt = Date()
        return w
    }

    private func satz(_ neu: String?, _ nun: Date) -> String? {
        if neu != merker.satz, nun.timeIntervalSince(merker.satzZeit) >= Laufzeile.satzTakt { merker.satz = neu; merker.satzZeit = nun }
        return merker.satz
    }

    var body: some View {
        if let live = chat.lives[key] { laufZeile(live) }
    }

    private func laufZeile(_ live: ChatLive) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let nun = ctx.date
            let w = bereinigt(live)
            let alle = (zug?.schritte ?? []).filter { $0.art != .gedanke } + w.schritte
            let ruhigMs = nun.timeIntervalSince(merker.zuletzt) * 1000
            let sofort = alle.isEmpty && !w.rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let schreibt = merker.gezeigt || sofort || Antwortform.antwortartig(w.rest, ruhigMs: ruhigMs)
            let _ = (merker.gezeigt = schreibt && !w.rest.isEmpty)
            let _ = (frisch.schrieb = schreibt)
            let z = Laufzeile.teile(name: name, phase: live.phase, taetigkeit: satz(live.activity, nun), schritte: alle.count,
                                    seit: max(0, nun.timeIntervalSince(live.startedAt)), ruhig: nun.timeIntervalSince(merker.zuletzt), letzterSchritt: alle.last?.ts)
            VStack(alignment: .leading, spacing: 10) {
                if schreibt {
                    Text("\(name.uppercased()) · SCHREIBT").font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.leise)
                    SnStromText(takt: SnStromTakt.takt(key, lauf: live.schluessel), text: w.rest, final: false)
                } else if live.phase != .sending, chat.store?.isConnected ?? true {
                    SnLaufPille(z: z, schritte: alle)
                    if z.haengt {
                        HStack(spacing: 8) {
                            Button("Nachfragen") { Task { _ = try? await chat.send("Wie weit bist du?", sessionKey: key) } }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                            Button("Anhalten") { Task { await chat.stop() } }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                        }
                    }
                }
            }
            .task(id: z.haengt) {
                guard z.haengt else { return }
                try? await Task.sleep(for: .seconds(Laufzeile.anhaltenNach - Laufzeile.haengtNach))
                if !Task.isCancelled { await chat.stop() }
            }
        }
    }
}

@MainActor
enum SnStromTakt {
    private static var takte: [String: (lauf: String, takt: WortTakt)] = [:]

    static func takt(_ key: String, lauf: String) -> WortTakt {
        if let t = takte[key], t.lauf == lauf { return t.takt }
        let t = WortTakt()
        takte[key] = (lauf, t)
        return t
    }

    static func nachlauf(_ key: String, text: String) -> WortTakt? {
        guard let t = takte[key]?.takt, !t.beendet, !t.sichtbar.isEmpty, text.hasPrefix(t.sichtbar) else { return nil }
        return t
    }
}

struct SnStromText: View {
    @ObservedObject var takt: WortTakt
    var text: String
    var final: Bool

    var body: some View {
        AntwortKarteView(text: takt.sichtbar, ts: nil, frisch: false, live: true, gross: true)
            .onAppear { takt.setzeText(text, final: final) }
            .onChange(of: text) { _, neu in takt.setzeText(neu, final: final) }
    }
}

struct SnAntwortNachlauf: View {
    @ObservedObject var takt: WortTakt
    var text: String
    var ts: Double?
    var gross: Bool

    var body: some View {
        if takt.beendet {
            AntwortKarteView(text: text, ts: ts, frisch: false, gross: gross)
        } else {
            AntwortKarteView(text: takt.sichtbar, ts: nil, frisch: false, live: true, gross: true)
                .onAppear { takt.setzeText(text, final: true) }
        }
    }
}

struct SnLaufPille: View {
    var z: Laufzeile.Teile
    var schritte: [Schritt]
    @State private var offen = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(ruhig ? .easeOut(duration: 0.15) : Kurve.ease(0.3)) { offen.toggle() } } label: {
                HStack(spacing: 12) {
                    SnAtemPunkt(an: !z.haengt)
                    (Text(z.haupt).foregroundColor(.white) + Text(z.neben).foregroundColor(TafelFarbe.leise))
                        .font(Schrift.grotesk(14)).monospacedDigit().lineLimit(1)
                    Spacer(minLength: 8)
                    if z.anhalten { Text("⌘. anhalten").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise) }
                }
                .padding(.horizontal, 16).frame(minHeight: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!schritte.isEmpty)
            if offen && !schritte.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(schritte.suffix(12).enumerated()), id: \.offset) { _, s in SpurView.zeile(s.ts, s.text, roh: nil, farbe: TafelFarbe.gruen) }
                }
                .padding(.leading, 20).padding(.bottom, 10).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snFlaeche(14)
        .erscheint(.laufrein)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(z.haupt + z.neben)
        .accessibilityIdentifier("laufzeile")
    }
}

struct SnAtemPunkt: View {
    var an: Bool
    var body: some View {
        if an {
            Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
        } else {
            Circle().strokeBorder(TafelFarbe.zweit, lineWidth: 1.5).frame(width: 7, height: 7)
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
    var quittung: SenecaStand.Quittung?
    var alt = false
    var zuruecklegen: (SenecaStand.Zuruecklegen) -> Void = { _ in }
    var erneut: () -> Void
    var angehalten: Double? = nil
    var weiter: () -> Void = {}
    var zuruecknehmen: (() -> Void)? = nil
    var vorziehen: () -> Void = {}
    var bearbeiten: () -> Void = {}
    var offline: Bool? = nil
    var sitzung = ""
    @State private var spurOffen = false
    @State private var zeigt = false

    static func == (a: ZugView, b: ZugView) -> Bool {
        a.angehalten == b.angehalten && a.quittung == b.quittung && a.alt == b.alt && a.zug == b.zug && a.status == b.status && (a.lauf == nil) == (b.lauf == nil) && a.frisch == b.frisch && a.zustand == b.zustand
            && a.neu == b.neu && a.name == b.name && a.gross == b.gross
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
                if let a = zug.antwort, let n = angehalten {
                    Text(a.text).font(Schrift.serif(26)).lineHeight(.exact(points: 30)).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack(spacing: 12) {
                        Text("angehalten nach " + VerlaufLogik.uhrDauer(n)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                        Button("Weitermachen", action: weiter).buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                        Button("Neu fragen", action: erneut).buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                    }
                } else if let a = zug.antwort {
                    if let an = Unterhaltung.antwortAn(zug) {
                        Text(an).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).padding(.leading, 2)
                            .accessibilityIdentifier("antwort-an")
                    }
                    Text("\(name.uppercased()) · \(a.ts.map { Formate.hhmm($0) } ?? "")").font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.leise)
                    let text = HierStelle.teile(a.text).text
                    Group {
                        if let t = SnStromTakt.nachlauf(sitzung, text: text) {
                            SnAntwortNachlauf(takt: t, text: text, ts: a.ts, gross: gross)
                        } else {
                            AntwortKarteView(text: text, ts: a.ts, frisch: frisch == .voll, gross: gross)
                        }
                    }
                    .id(Self.antwortId(zug.id))
                    SpurView(zug: zug, frisch: frisch != nil).padding(.top, 2)
                    if let q = quittung { QuittungErgebnis(quittung: q, zuruecklegen: zuruecklegen) }
                } else if !zug.schritte.isEmpty, zug.widgets.isEmpty {
                    HStack(spacing: 8) {
                        Text(VerlaufLogik.abbruch(zug.schritte.filter { $0.art != .gedanke }.count)).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.text).padding(.trailing, 8)
                        Button("Nochmal fragen", action: erneut).buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                        Button("Spur ansehen") { withAnimation(Kurve.ease(0.3)) { spurOffen.toggle() } }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                    }
                    if spurOffen { SpurView(zug: zug, frisch: false, anfangsOffen: true) }
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
            ForEach(zug.hinweise, id: \.id) { h in EreignisZeileView(e: h, klein: true) }
        }
        .opacity(alt ? 0.8 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func frage(_ text: String, pending: Bool, ts: Double?) -> some View {
        let teile = ChatAnhang.zerlege(text)
        let wartet = pending && (offline ?? (lauf?.chat.store?.isConnected == false))
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(teile.namen.enumerated()), id: \.offset) { _, n in SnAnhangChip(name: n) }
                if !teile.text.isEmpty || teile.namen.isEmpty {
                    Text(teile.text)
                        .font(Schrift.grotesk(15)).foregroundStyle(Color.white).lineHeight(.exact(points: 22))
                        .textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(hex: 0x142B4C).opacity(wartet ? 0 : 1), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                        .overlay { if wartet { UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])) } }
                }
            }
            .frame(maxWidth: 520, alignment: .trailing)
            .opacity((pending && zustand != .fehlgeschlagen ? 0.8 : 1) * (alt ? 0.55 / 0.8 : 1))
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
            if let q = quittung { SnQuittungZeile(teile: q.teile).padding(.top, 4) }
            if zustand == .fehlgeschlagen {
                HStack(spacing: 8) {
                    Text("Nicht gesendet").font(Schrift.grotesk(12)).foregroundStyle(Farbe.koralle)
                    Button("Erneut senden", action: erneut).buttonStyle(.plain)
                        .font(Schrift.grotesk(12, .medium)).foregroundStyle(Farbe.himmel)
                }
            } else if pending, status == nil, let lauf, let ts {
                TimelineView(.periodic(from: .now, by: 1)) { takt in
                    if let z = VerlaufLogik.zustand(zustand, phase: lauf.chat.lives[lauf.key]?.phase, verbunden: lauf.chat.store?.isConnected ?? true, ts: ts, jetzt: takt.date.timeIntervalSince1970 * 1000) {
                        HStack(spacing: 12) {
                            if zeigt, let zuruecknehmen, z.text.hasPrefix("in der Reihe") || z.text.hasPrefix("angekommen") {
                                if z.text.hasPrefix("in der Reihe") { Button("Vorziehen", action: vorziehen).buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel) }
                                Button("Zurücknehmen", action: zuruecknehmen).buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel)
                            }
                            SnZustandZeile(zeichen: z.zeichen, text: z.text)
                        }
                        .font(Schrift.grotesk(12.5)).onHover { zeigt = $0 }
                    }
                }
                if wartet, let zuruecknehmen { SnWartetKnoepfe(bearbeiten: bearbeiten, zuruecknehmen: zuruecknehmen) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("frage")
    }
}

enum FrischArt { case voll, weich }

struct SnWartetKnoepfe: View {
    var bearbeiten: () -> Void
    var zuruecknehmen: () -> Void
    var body: some View {
        HStack(spacing: 28) {
            Button("Bearbeiten", action: bearbeiten)
            Button("Zurücknehmen", action: zuruecknehmen)
        }
        .buttonStyle(.plain).font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.text).padding(.top, 8).padding(.trailing, 14)
    }
}

struct SnZustandZeile: View {
    var zeichen: String
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: zeichen).font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
    }
}

struct SnQuittungZeile: View {
    var teile: [String]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            Text(teile.joined(separator: " · "))
        }
        .font(Schrift.mono(12)).foregroundStyle(TafelFarbe.gruen)
    }
}

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
