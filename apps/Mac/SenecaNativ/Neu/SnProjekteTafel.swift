import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
}

struct SnProjekteTafel: View {
    var stand: SenecaStand
    var zuDenFragen: () -> Void

    private let linie = Color.white.opacity(0.10)

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                inhalt
                    .padding(.horizontal, max(24, (g.size.width - 1248) / 2))
                    .padding(.top, 108).padding(.bottom, 140)
                    .frame(width: g.size.width, alignment: .topLeading)
            }
            .scrollClipDisabled()
        }
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.26, 0), (0.11, 0.14), (0, 0.30)]))
        .foregroundStyle(TafelFarbe.text)
        .accessibilityIdentifier("seite-projekte")
    }

    private var inhalt: some View {
        let p = stand.projekte
        let liste = p?.liste ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text(p?.kopf ?? "").font(Schrift.mono(13)).tracking(0.4).foregroundStyle(TafelFarbe.zweit).padding(.bottom, 14)
            if let s = p?.satz, s.count == 2 {
                (Text(s[0] + " ").font(Schrift.serif(44)).foregroundColor(.white) + Text(s[1]).font(Schrift.serif(44, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                    .tracking(-0.5).hoehe(46.6).frame(maxWidth: 1060, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, pr in zeile(pr, offen: i == 0) }
            }
            .overlay(alignment: .top) { linie.frame(height: 1) }
            .padding(.top, 36)
            if let r = p?.ruhen { Text(r).font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.leise).padding(.top, 18) }
        }
    }

    private func zeile(_ p: SenecaStand.Projekt, offen: Bool) -> some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 6) {
                Text(p.name).font(Schrift.serif(30)).hoehe(31.5).foregroundStyle(.white)
                if let u = p.untertitel { Text(u).font(Schrift.grotesk(13)).hoehe(18).foregroundStyle(TafelFarbe.leise) }
            }
            .frame(width: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if let s = p.satz { Text(s).font(Schrift.grotesk(16)).hoehe(24).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true) }
                phasen(p).padding(.top, 16)
                if offen, let z = p.zeilen, !z.isEmpty {
                    VStack(alignment: .leading, spacing: 2) { ForEach(z, id: \.id) { aufgabe($0) } }.padding(.top, 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rechts(p).frame(width: 180, alignment: .trailing)
        }
        .padding(.top, offen ? 24 : 22).padding(.bottom, offen ? 20 : 22)
        .overlay(alignment: .bottom) { linie.frame(height: 1) }
    }

    private func phasen(_ p: SenecaStand.Projekt) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array((p.phasen ?? []).enumerated()), id: \.offset) { _, ph in
                let farbe = ph.zustand == "fertig" ? TafelFarbe.gruen : ph.zustand == "jetzt" ? (p.zustand == "braucht" ? TafelFarbe.bernstein : TafelFarbe.himmel) : Color.white.opacity(0.12)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(farbe).frame(height: 3).padding(.trailing, 4)
                    Text(ph.name).font(Schrift.mono(11)).tracking(0.4).foregroundStyle(ph.zustand == "jetzt" ? farbe : TafelFarbe.leise)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func aufgabe(_ z: SenecaStand.ProjektZeile) -> some View {
        HStack(spacing: 10) {
            Group {
                switch z.art {
                case "frage": Circle().fill(TafelFarbe.bernstein)
                case "laeuft": Circle().fill(TafelFarbe.gruen)
                default: Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8).frame(width: 16, alignment: .leading)
            (Text(z.text).foregroundColor(z.art == "frage" ? .white : TafelFarbe.text) + Text(z.wer.map { " · \($0)" } ?? "").foregroundColor(TafelFarbe.leise))
                .font(Schrift.grotesk(14)).hoehe(20).frame(maxWidth: .infinity, alignment: .leading)
            if let r = z.rechts {
                if z.art == "frage" {
                    Button(r, action: zuDenFragen).buttonStyle(.plain).font(Schrift.grotesk(14, .medium)).foregroundStyle(TafelFarbe.himmel)
                } else {
                    Text(r).font(Schrift.mono(12)).foregroundStyle(z.art == "laeuft" ? TafelFarbe.zweit : TafelFarbe.leise)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func rechts(_ p: SenecaStand.Projekt) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            switch p.zustand {
            case "braucht":
                Text("braucht dich").font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.bernstein)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(TafelFarbe.bernstein.opacity(0.16)))
            case "laeuft":
                HStack(spacing: 8) { Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7); Text("läuft") }
                    .font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.gruen)
            default:
                HStack(spacing: 8) { Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5).frame(width: 7, height: 7); Text("wartet") }
                    .font(Schrift.grotesk(13, .medium)).foregroundStyle(TafelFarbe.zweit)
            }
            if let f = p.frist, p.zustand == "braucht" {
                Text(HeuteTafelLogik.frist(f, jetzt: stand.jetzt)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.bernstein)
            }
            let r = p.rechts ?? []
            ForEach(Array(r.enumerated()), id: \.offset) { i, t in
                Text(t).font(Schrift.mono(12)).foregroundStyle(r.count > 1 && i == 0 ? TafelFarbe.zweit : TafelFarbe.leise)
            }
        }
    }
}

struct SnProjekteEcht: View {
    let modell: AppModell
    @ObservedObject var store: SenecaStore

    var body: some View {
        if let s = store.stand {
            SnProjekteTafel(stand: s, zuDenFragen: { modell.gehe(Route(.entscheidungen)) })
        } else {
            SnHeuteSkelett()
        }
    }
}
