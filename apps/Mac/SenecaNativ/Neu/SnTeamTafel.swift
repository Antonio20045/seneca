import SwiftUI

struct SnTeamTafel: View {
    var stand: SenecaStand
    @State var name: String?
    var handle: (String, String, String?) -> Void
    var schreiben: (String) -> Void

    private typealias L = HeuteTafelLogik
    private var team: [SenecaStand.Mitglied] {
        (stand.team ?? []).filter { $0.id != Hauptagent.id && ($0.zustand != "frei" || $0.zuletzt != nil || fragen($0) > 0) }
    }
    private var m: SenecaStand.Mitglied? { team.first { $0.name == name } ?? team.first { $0.arbeit != nil } ?? team.first }

    var body: some View {
        ZStack(alignment: .topLeading) {
            seite.frame(width: 300, alignment: .leading).offset(x: 40, y: 104)
            if let m { haupt(m).frame(width: 1028, alignment: .leading).offset(x: 372, y: 104) }
        }
        .frame(width: 1440, height: 900, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(TafelFarbe.text)
    }

    private func fragen(_ m: SenecaStand.Mitglied) -> Int {
        ((stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? [])).filter { $0.von == m.name }.count
    }

    private func punkt(_ m: SenecaStand.Mitglied) -> some View {
        let arbeitet = m.zustand == "arbeitet", wartet = fragen(m) > 0
        return ZStack {
            if arbeitet || wartet || m.zustand == "hängt" {
                Circle().fill(arbeitet ? TafelFarbe.gruen : wartet ? TafelFarbe.bernstein : TafelFarbe.leise)
                    .background(Circle().fill(TafelFarbe.gruen.opacity(arbeitet ? 0.18 : 0)).padding(-4))
            } else {
                Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5)
            }
        }
        .frame(width: 8, height: 8)
    }

    private func zeile(_ m: SenecaStand.Mitglied) -> (String, Color) {
        let n = fragen(m)
        if m.zustand == "arbeitet" { return (m.satz ?? "arbeitet", TafelFarbe.zweit) }
        if n > 0 { return ("wartet auf dich · \(n == 1 ? "eine Frage" : "\(Self.wort(n)) Fragen")", TafelFarbe.bernstein) }
        if m.zustand == "ruht", let s = m.ruht_seit { return ("ruht seit \(s < (stand.tag_beginn ?? 0) ? "gestern " : "")\(L.uhr(s))", TafelFarbe.leise) }
        if let z = m.zuletzt { return ([z.um.map { "fertig \(L.uhr($0))" }, z.satz].compactMap { $0 }.joined(separator: " · "), TafelFarbe.leise) }
        return (m.zustand, TafelFarbe.leise)
    }

    static func wort(_ n: Int) -> String { n < 11 ? ["null", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn"][n] : "\(n)" }

    private var seite: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let k = stand.team_kopf, k.count == 2 {
                (Text(k[0] + " ").foregroundColor(.white) + Text(k[1]).font(Schrift.serif(28, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                    .font(Schrift.serif(28)).padding(.horizontal, 14).padding(.bottom, 16)
            }
            ForEach(team, id: \.name) { t in
                let (satz, farbe) = zeile(t)
                let an = t.name == m?.name
                Button { name = t.name } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        punkt(t).frame(width: 14)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.name).font(Schrift.grotesk(14, .medium)).foregroundStyle(.white).lineHeight(.exact(points: 20))
                            Text(satz).font(Schrift.grotesk(12)).foregroundStyle(farbe).lineHeight(.exact(points: 17))
                        }
                        Spacer(minLength: 0)
                        if let r = t.rest_min, t.zustand == "arbeitet" { Text("\(Int(r)) MIN").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(an ? 0.09 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("SO SEHEN ZUSTÄNDE AUS").font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise).padding(.bottom, 1)
                legende(Circle().fill(TafelFarbe.gruen).background(Circle().fill(TafelFarbe.gruen.opacity(0.18)).padding(-4)), "arbeitet, mit Restzeit")
                legende(Circle().fill(TafelFarbe.bernstein), "wartet auf dich")
                legende(Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5), "fertig oder ruht")
                legende(Circle().fill(TafelFarbe.leise), "kommt nicht weiter", "„kein Schritt seit zwölf Minuten“")
                legende(Circle().strokeBorder(TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])), "nicht erreichbar", "„Mac-Gateway aus seit 11:28“")
            }
            .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit).padding(.horizontal, 14).padding(.top, 26)
        }
    }

    private func legende(_ p: some View, _ t: String, _ u: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            p.frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(t)
                if let u { Text(u).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
            }
        }
    }

    private func haupt(_ m: SenecaStand.Mitglied) -> some View {
        let a = m.arbeit
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        punkt(m)
                        Text(([m.name, m.zustand, m.projekt] + [L.uhr(stand.jetzt)]).compactMap { $0 }.joined(separator: " · ").uppercased())
                    }
                    .font(Schrift.mono(11, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise)
                    let k = (a?.kopf ?? []).compactMap { $0 }
                    (Text((k.first ?? m.name) + " ").foregroundColor(.white) + Text(k.dropFirst().joined()).font(Schrift.serif(38, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                        .font(Schrift.serif(38)).lineHeight(.exact(points: 40.3)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let id = m.auftrag_id { Button("Anhalten") { handle("auftrag.anhalten", id, nil) }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 14)) }
                    Button("Schreiben") { schreiben(m.id ?? m.name) }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 14))
                }
                .padding(.top, 22)
            }
            if let a {
                HStack(spacing: 20) {
                    Text("Auftrag von \(a.von ?? "dir")\(a.erteilt.map { " · " + L.uhr($0) } ?? "")")
                    GeometryReader { g in
                        Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.gruen).frame(width: g.size.width * (a.anteil ?? 0)) }
                    }
                    .frame(height: 4)
                    Text(a.minuten ?? "")
                }
                .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 22)
                HStack(alignment: .top, spacing: 14) {
                    karte("JETZT", m.satz.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }, a.schritt)
                    karte("ALS NÄCHSTES", a.naechstes?.first ?? nil, a.naechstes?.last ?? nil)
                    karte("WARTET AUF", a.wartet?.first, a.wartet?.last, leise: a.wartet?.first?.hasPrefix("Nichts") == true)
                }
                .padding(.top, 26)
                HStack(alignment: .top, spacing: 50) {
                    heute(a).frame(width: 320, alignment: .leading)
                    protokoll(a)
                }
                .padding(.top, 30)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.top, 36)
            HStack(alignment: .top, spacing: 40) {
                fuss("WENN DU ANHÄLTST", "\(m.name) hört nach dem laufenden Schritt auf. Was fertig ist, bleibt liegen. Fünf Sekunden Rückgängig, dann „Fortsetzen“ an derselben Stelle.")
                fuss("WENN ER NICHT WEITERKOMMT", "Nach zehn Minuten ohne Schritt steht es hier still als Satz. Nach dreißig wird daraus eine Frage an dich, mit „Anstupsen“ und „Anhalten“.")
                fuss("WENN ER NICHT ERREICHBAR IST", "Aufträge warten in seiner Reihe und starten, sobald er zurück ist. Seneca sagt, seit wann und warum.")
            }
            .padding(.top, 24)
        }
    }

    private func karte(_ k: String, _ t: String?, _ u: String?, leise: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise).padding(.bottom, 10)
            Text(t ?? "").font(Schrift.grotesk(16)).lineHeight(.exact(points: 22)).foregroundStyle(leise ? TafelFarbe.zweit : .white).fixedSize(horizontal: false, vertical: true)
            if let u { Text(u).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 8) }
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func heute(_ a: SenecaStand.Arbeit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HEUTE, IN SÄTZEN").font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise)
            let h = a.heute ?? []
            ForEach(Array(h.enumerated()), id: \.offset) { i, z in
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(z.um.map { L.uhr($0) } ?? "").font(Schrift.mono(12)).foregroundStyle(i == h.count - 1 ? TafelFarbe.gruen : TafelFarbe.aus).frame(width: 54, alignment: .leading)
                    Text(z.satz ?? "").font(Schrift.grotesk(15)).lineHeight(.exact(points: 19)).foregroundStyle(i == h.count - 1 ? .white : TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func protokoll(_ a: SenecaStand.Arbeit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROHPROTOKOLL · DIESER AUFTRAG").font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise).padding(.bottom, 8)
            let p = a.protokoll ?? []
            ForEach(Array(p.enumerated()), id: \.offset) { i, w in
                let letzte = i == p.count - 1
                HStack(spacing: 0) {
                    Text(Formate.hhmmss(w.um)).font(Schrift.mono(13)).foregroundStyle(TafelFarbe.aus).frame(width: 84, alignment: .leading)
                    Text(w.werkzeug ?? "").font(Schrift.mono(13)).foregroundStyle(letzte ? TafelFarbe.gruen : TafelFarbe.zweit).frame(width: 140, alignment: .leading)
                    Text(w.satz ?? "").font(Schrift.grotesk(14)).foregroundStyle(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(letzte ? "…" : String(format: "%.1f s", (w.ms ?? 0) / 1000).replacingOccurrences(of: ".", with: ",")).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                }
                .frame(height: 32)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
            HStack(spacing: 22) {
                ForEach(a.zahlen ?? [], id: \.self) { z in
                    let n = String(z.prefix { "0123456789, €".contains($0) })
                    Text(n).foregroundColor(.white) + Text(String(z.dropFirst(n.count)).uppercased()).foregroundColor(TafelFarbe.leise)
                }
            }
            .font(Schrift.mono(11)).padding(.top, 14)
            if let d = a.dateien, !d.isEmpty {
                Text("Dateien: " + d.joined(separator: " · ")).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 12)
            }
        }
    }

    private func fuss(_ k: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(k).font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise)
            Text(t).font(Schrift.grotesk(14)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
