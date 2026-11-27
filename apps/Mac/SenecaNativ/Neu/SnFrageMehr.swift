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

struct SnFrageMehr: View {
    var frage: SenecaStand.Frage
    var stand: SenecaStand
    var antworte: (String) -> Void
    var zuruecknehmen: () -> Void
    var andereZeit: () -> Void
    @State private var gesendet: (wahl: String, um: Date)?

    var body: some View {
        let h = GL.haupt(frage)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
                Text(GL.mehrKopf(frage, stand)).font(Schrift.mono(11, .medium)).kerning(1.2).foregroundStyle(TafelFarbe.bernstein)
            }
            Text(frage.text).font(Schrift.serif(36)).lineHeight(.exact(points: 39)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 20)
            Grid(alignment: .topLeading, horizontalSpacing: 30, verticalSpacing: 18) {
                GridRow { feld("WORUM ES GEHT", frage.kontext?.worum, TafelFarbe.zweit); feld(GL.wennJa(frage), h?.folge) }
                GridRow { feld("WENN NICHT", frage.kontext?.wenn_nicht); feld("\((frage.von ?? "").uppercased()) EMPFIEHLT", GL.empfiehlt(frage), kopf: TafelFarbe.akzent) }
            }
            if let g = gesendet { quittung(g) } else { knoepfe(h) }
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 22)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.07)).shadow(color: .black.opacity(0.6), radius: 25, y: 24))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func feld(_ k: String, _ t: String?, _ farbe: Color = .white, kopf: Color = TafelFarbe.leise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            klein(k, kopf)
            Text(t ?? "").font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(farbe).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func knoepfe(_ h: SenecaStand.Option?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let h { Button(h.knopf ?? h.text ?? "Ja") { senden(h.wert ?? "ja") }.buttonStyle(SnTafelKnopf()) }
                ForEach((frage.optionen ?? []).filter { $0.wert != h?.wert && $0.wert != "spaeter" }, id: \.wert) { o in
                    Button(o.knopf ?? o.text ?? "") { senden(o.wert ?? "") }.buttonStyle(SnTafelKnopf(art: .rand))
                }
                Button("Später") { senden("spaeter") }.buttonStyle(SnTafelKnopf(art: .leise))
                randKnopf("Andere Zeit vorschlagen", groesse: 15, andereZeit)
            }
            Text(GL.wirktSatz(frage, stand)).font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.top, 22)
    }

    private func quittung(_ g: (wahl: String, um: Date)) -> some View {
        let o = frage.optionen?.first { $0.wert == g.wahl }
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        return TimelineView(.periodic(from: g.um, by: 0.5)) { t in
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                Text(o?.quittung ?? o?.text ?? g.wahl).font(Schrift.grotesk(15, .medium)).foregroundStyle(.white)
                Spacer()
                if t.date.timeIntervalSince(g.um) < frist {
                    Button("Zurücknehmen") { zuruecknehmen(); gesendet = nil }.buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.himmel)
                }
            }
        }
        .padding(.top, 22)
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
                Text(["Wartet auf deine Antwort.", frage.lage].compactMap { $0 }.joined(separator: " ")).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.zweit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            if let d = frage.davor, !d.isEmpty {
                liste("WAS DAVOR GESCHAH", d.map { (HeuteTafelLogik.uhr($0.um ?? 0), $0.satz ?? "", $0.frage_id == frage.id) }).padding(.top, 24)
            }
            if let h = frage.haengt, !h.isEmpty {
                liste("WAS DARAN HÄNGT", h.map { (GL.wann($0.um, stand), $0.text, false) }).padding(.top, 20)
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
                    Text(e.1).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(e.2 ? .white : TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 8) { ForEach(r, id: \.self) { t in randKnopf(t, groesse: 13) { frag(t) } } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
