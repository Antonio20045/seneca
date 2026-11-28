import SwiftUI

private func klein(_ t: String, _ farbe: Color = TafelFarbe.leise) -> some View {
    Text(t).font(Schrift.mono(10, .medium)).kerning(1.3).foregroundStyle(farbe)
}

private func randKnopf(_ t: String, groesse: CGFloat, _ tun: @escaping () -> Void) -> some View {
    Button(action: tun) {
        Text(t).font(Schrift.grotesk(groesse, .medium)).foregroundStyle(TafelFarbe.akzent).fixedSize()
            .padding(.horizontal, groesse > 14 ? 18 : 14).padding(.vertical, groesse > 14 ? 10 : 6)
            .overlay(Capsule(style: .circular).strokeBorder(TafelFarbe.himmel.opacity(0.5), lineWidth: 1)).contentShape(Capsule())
    }
    .buttonStyle(.plain)
}

struct SnAuswahlZeile: View {
    var text: String
    var gewaehlt: Bool
    var tippe: () -> Void
    var body: some View {
        Button(action: tippe) {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(gewaehlt ? TafelFarbe.himmel : Color.white.opacity(0.3), lineWidth: 1.5).frame(width: 18, height: 18)
                    .overlay { if gewaehlt { Circle().fill(TafelFarbe.himmel).padding(4) } }.padding(.top, 2)
                Text(GL.ohneNummern(text)).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).foregroundStyle(gewaehlt ? .white : TafelFarbe.zweit)
                    .lineLimit(3).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(gewaehlt ? 0.09 : 0.04) as Color))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(gewaehlt ? TafelFarbe.himmel.opacity(0.55) as Color : Color.white.opacity(0.06), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SnFrageMehr: View, Equatable {
    var frage: SenecaStand.Frage
    var kopf: String
    var namen: [String]

    init(frage: SenecaStand.Frage, stand: SenecaStand) {
        self.frage = frage
        kopf = GL.mehrKopf(frage, stand)
        namen = (stand.team ?? []).map(\.name)
    }

    var body: some View {
        let h = GL.haupt(frage)
        let w = GL.worum(frage.kontext?.worum, namen: namen)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
                Text(kopf).font(Schrift.mono(11, .medium)).kerning(1.2).foregroundStyle(TafelFarbe.bernstein)
            }
            let u = GL.ueberschrift(frage.text, gross: 36)
            Text(GL.ohneNummern(frage.text)).font(Schrift.serif(u.groesse)).lineHeight(.exact(points: u.zeile)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).padding(.top, 12).padding(.bottom, 20)
            if [w.satz, h?.folge ?? "", frage.kontext?.wenn_nicht ?? ""].allSatisfy({ $0.isEmpty }), let l = frage.lage ?? frage.grund {
                Text(GL.ohneNummern(l)).font(Schrift.grotesk(15)).lineHeight(.exact(points: 23)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 30, verticalSpacing: 18) {
                GridRow { feld("WORUM ES GEHT", w.satz, TafelFarbe.zweit); feld(GL.wennJa(frage), h?.folge) }
                if !w.gruppen.isEmpty { GridRow { gruppen(w.gruppen).gridCellColumns(2) } }
                GridRow { feld("WENN NICHT", frage.kontext?.wenn_nicht); feld("\((frage.von ?? "").uppercased()) EMPFIEHLT", GL.empfiehlt(frage), kopf: TafelFarbe.akzent) }
            }
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .accessibilityIdentifier("frage-karte")
    }

    private func gruppen(_ g: [GL.Gruppe]) -> some View {
        HStack(alignment: .top, spacing: 30) {
            ForEach(Array(GL.spalten(g).enumerated()), id: \.offset) { _, spalte in
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(spalte, id: \.name) { x in
                        VStack(alignment: .leading, spacing: 6) {
                            klein("\(x.name.uppercased()) · \(x.punkte.count)")
                            ForEach(Array(x.punkte.enumerated()), id: \.offset) { i, t in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(i + 1)").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.himmel).frame(width: 16, alignment: .trailing)
                                    Text(t).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.vertical, 4)
    }

    private func feld(_ k: String, _ t: String?, _ farbe: Color = .white, kopf: Color = TafelFarbe.leise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t, !t.isEmpty { klein(k, kopf) }
            Text(GL.ohneNummern(t ?? "")).font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(farbe).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SnFrageMehrKnoepfe: View {
    var frage: SenecaStand.Frage
    var stand: SenecaStand
    var antworte: (String) -> Void
    var zuruecknehmen: () -> Void
    var andereZeit: () -> Void
    @State private var gesendet: (wahl: String, um: Date)?
    @State private var gewaehlt: String?

    var body: some View {
        Group { if let g = gesendet { quittung(g) } else { knoepfe(GL.haupt(frage)) } }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .snProbeWahl)) { n in
                guard let i = n.object as? Int, auswahl.indices.contains(i) else { return }
                if (n.userInfo?["senden"] as? Bool) == true { senden(auswahl[i].wert ?? "") } else { withAnimation(Kurve.sn(0.2)) { gewaehlt = auswahl[i].wert } }
            }
            #endif
            .accessibilityIdentifier("frage-knoepfe")
    }

    private var auswahl: [SenecaStand.Option] { (frage.optionen ?? []).filter { $0.wert != "spaeter" } }
    private var lang: Bool { auswahl.contains { GL.langesEtikett($0.knopf ?? $0.text ?? "") } }

    private func knoepfe(_ h: SenecaStand.Option?) -> some View {
        let wahl = gewaehlt ?? h?.wert ?? auswahl.first?.wert ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            if lang {
                VStack(spacing: 8) { ForEach(Array(auswahl.enumerated()), id: \.offset) { _, o in SnAuswahlZeile(text: o.knopf ?? o.text ?? "", gewaehlt: o.wert == wahl) { gewaehlt = o.wert } } }
                HStack(spacing: 6) {
                    Button("Wählen") { senden(wahl) }.buttonStyle(SnTafelKnopf())
                    Button("Später") { senden("spaeter") }.buttonStyle(SnTafelKnopf(art: .leise))
                    randKnopf("Andere Zeit vorschlagen", groesse: 15, andereZeit)
                }
                .padding(.top, 4)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { knopfReihe(h) }
                    VStack(alignment: .leading, spacing: 8) { knopfReihe(h) }
                }
            }
            Text(GL.wirktSatz(frage, stand)).font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.leise)
        }
    }

    @ViewBuilder private func knopfReihe(_ h: SenecaStand.Option?) -> some View {
        if let h { Button(h.knopf ?? h.text ?? "Ja") { senden(h.wert ?? "ja") }.buttonStyle(SnTafelKnopf()) }
        ForEach((frage.optionen ?? []).filter { $0.wert != h?.wert && $0.wert != "spaeter" }, id: \.wert) { o in
            Button(o.knopf ?? o.text ?? "") { senden(o.wert ?? "") }.buttonStyle(SnTafelKnopf(art: .rand))
        }
        Button("Später") { senden("spaeter") }.buttonStyle(SnTafelKnopf(art: .leise))
        randKnopf("Andere Zeit vorschlagen", groesse: 15, andereZeit)
    }

    private func quittung(_ g: (wahl: String, um: Date)) -> some View {
        let o = frage.optionen?.first { $0.wert == g.wahl }
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        return TimelineView(.periodic(from: g.um, by: 0.5)) { t in
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                Text(GL.ohneNummern(o?.quittung ?? o?.text ?? g.wahl)).font(Schrift.grotesk(15, .medium)).foregroundStyle(.white).lineLimit(2)
                Spacer()
                if t.date.timeIntervalSince(g.um) < frist {
                    Button("Zurücknehmen") { zuruecknehmen(); gesendet = nil }.buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.himmel)
                }
            }
        }
    }

    private func senden(_ w: String) {
        antworte(w)
        gesendet = (w, Date())
    }
}

struct SnFrageMehrRand: View {
    var frage: SenecaStand.Frage
    var stand: SenecaStand
    @State private var roh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            klein("WER FRAGT").padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
                    Text(frage.von ?? "").font(Schrift.grotesk(16, .medium)).foregroundStyle(.white)
                }
                Text(["Wartet auf deine Antwort.", frage.lage.map(GL.ersterSatz)].compactMap { $0 }.joined(separator: " ")).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.zweit)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            if let d = frage.davor, !d.isEmpty {
                liste("WAS DAVOR GESCHAH", d.suffix(4).map { (HeuteTafelLogik.uhr($0.um ?? 0), GL.ersterSatz($0.satz ?? ""), $0.frage_id == frage.id) }).padding(.top, 24)
            }
            if let h = frage.haengt, !h.isEmpty {
                liste("WAS DARAN HÄNGT", h.prefix(3).map { (GL.wann($0.um, stand), GL.ersterSatz($0.text), false) }).padding(.top, 20)
            }
            Button { withAnimation(Kurve.sn(0.25)) { roh.toggle() } } label: {
                Text("Rohdaten der Frage " + (roh ? "⌄" : "›")).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel)
            }
            .buttonStyle(.plain).padding(.top, 22)
            Text("Optionen, Empfehlung und Folge, so wie \(frage.von ?? "") sie angelegt hat.").font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.leise)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            if roh {
                Text(rohText).font(Schrift.mono(11)).lineHeight(.exact(points: 17)).foregroundStyle(TafelFarbe.zweit).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
        .frame(width: 312, alignment: .topLeading)
    }

    private var rohText: String {
        ((frage.optionen ?? []).map { "\($0.wert ?? ""): \($0.text ?? "") → \($0.folge ?? "")" } + ["empfehlung: \(frage.empfehlung ?? "")", "wenn_nichts: \(frage.kontext?.wenn_nicht ?? "")"]).joined(separator: "\n")
    }

    private func liste(_ kopf: String, _ z: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            klein(kopf).padding(.bottom, 6)
            ForEach(Array(z.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(e.0).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).frame(width: 44, alignment: .leading)
                    Text(e.1).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(e.2 ? .white : TafelFarbe.zweit).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

struct SnFrageMehrFuss: View {
    var frage: SenecaStand.Frage
    var frag: (String) -> Void

    var body: some View {
        if let r = frage.rueckfragen, !r.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                klein("FRAG \((frage.von ?? "").uppercased()) ZURÜCK")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ForEach(r, id: \.self) { t in randKnopf(t, groesse: 13) { frag(t) } } }
                    HStack(spacing: 8) { ForEach(r.prefix(2), id: \.self) { t in randKnopf(t, groesse: 13) { frag(t) } } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
extension Notification.Name { static let snProbeWahl = Notification.Name("snProbeWahl") }
#endif
