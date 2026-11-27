import SwiftUI

typealias GL = GespraecheTafelLogik

private func etikett(_ t: String) -> some View {
    Text(t).font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
}

struct SnGespraechLeiste: View {
    var stand: SenecaStand?
    var aktiv: String
    var waehle: (String) -> Void
    var neu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eintrag(id: Hauptagent.id, name: "Seneca", zeilen: [GL.Zeile(text: stand.flatMap(GL.seneca) ?? "Frag Seneca etwas.")], punkt: nil).padding(.vertical, 2)
            etikett("DEIN TEAM").padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 8)
            ForEach(stand.map(GL.leiste) ?? [], id: \.m.name) { e in
                eintrag(id: e.m.id ?? e.m.name.lowercased(), name: e.m.name, zeilen: e.zeilen, punkt: e.punkt)
            }
            Spacer(minLength: 20)
            Button(action: neu) {
                HStack { Text("Neues Gespräch").font(Schrift.grotesk(13)); Spacer(); Text("⌘N").font(Schrift.mono(12)) }
                    .foregroundStyle(TafelFarbe.leise).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, 14).keyboardShortcut("n", modifiers: .command)
        }
        .frame(width: 268, alignment: .topLeading)
    }

    private func eintrag(id: String, name: String, zeilen: [GL.Zeile], punkt: GL.Punkt?) -> some View {
        let gewaehlt = id == aktiv
        return Button { waehle(id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let punkt { SnLeistePunkt(punkt: punkt).padding(.top, 7).padding(.leading, 5) } else { SnKugel(groesse: 18, atmet: false).padding(.top, 3) }
                }
                .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Schrift.grotesk(15, .medium)).lineHeight(.exact(points: 21))
                        .foregroundStyle(punkt == .ruht ? TafelFarbe.zweit : punkt == .fertig ? TafelFarbe.text : Color.white)
                    zeilen.reduce(Text("")) { $0 + Text($1.text).foregroundColor($1.hervor ? TafelFarbe.bernstein : punkt == .fertig || punkt == .ruht ? TafelFarbe.leise : TafelFarbe.zweit) }
                        .font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, punkt == nil ? 12 : 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(gewaehlt ? 0.09 : 0)))
            .overlay(alignment: .top) { if gewaehlt { RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.12), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SnLeistePunkt: View {
    var punkt: GL.Punkt
    var body: some View {
        switch punkt {
        case .arbeitet: Circle().fill(TafelFarbe.gruen).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.gruen.opacity(0.18)).frame(width: 16, height: 16))
        case .wartet: Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
        case .fertig: Circle().strokeBorder(TafelFarbe.himmel, lineWidth: 1.5).frame(width: 8, height: 8)
        case .ruht: Circle().fill(Color.white.opacity(0.18)).frame(width: 8, height: 8)
        }
    }
}

struct SnGespraechRand: View {
    var stand: SenecaStand?
    var agent: String
    var zuProjekten: () -> Void

    private var mitglied: SenecaStand.Mitglied? { stand?.team?.first { $0.id == agent } }
    private var projekt: SenecaStand.Projekt? { mitglied?.projekt.flatMap { p in stand?.projekte?.liste?.first { $0.name == p } } }

    var body: some View {
        if agent == Hauptagent.id { heute } else if let s = stand, let p = projekt { projektRand(s, p) }
    }

    private var heute: some View {
        VStack(alignment: .leading, spacing: 6) {
            etikett("HEUTE MIT SENECA").padding(.bottom, 4)
            ForEach(Array((stand.map(GL.heuteMitSeneca) ?? []).enumerated()), id: \.offset) { _, z in
                Text(z.text).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(z.hervor ? TafelFarbe.text : TafelFarbe.leise)
            }
        }
        .frame(width: 200, alignment: .topLeading)
    }

    private func projektRand(_ s: SenecaStand, _ p: SenecaStand.Projekt) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                etikett("WORUM ES GEHT")
                Text(p.worum ?? p.untertitel ?? p.name).font(Schrift.serif(24)).lineHeight(.exact(points: 27)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
            }
            if let ph = p.phasen, !ph.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    etikett("STAND")
                    HStack(spacing: 4) {
                        ForEach(Array(ph.enumerated()), id: \.offset) { _, x in
                            RoundedRectangle(cornerRadius: 2).fill(x.zustand == "fertig" ? TafelFarbe.himmel : x.zustand == "jetzt" ? TafelFarbe.bernstein : Color.white.opacity(0.14)).frame(height: 4)
                        }
                    }
                    Text(GL.standSatz(ph)).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                etikett("WER MITMACHT").padding(.bottom, 2)
                ForEach(Array(GL.mitmachen(s, projekt: p.name).enumerated()), id: \.offset) { _, m in
                    (Text(m.name + " ").foregroundColor(TafelFarbe.text) + Text(m.was).foregroundColor(m.hervor ? TafelFarbe.bernstein : TafelFarbe.leise))
                        .font(Schrift.grotesk(13)).lineHeight(.exact(points: 19))
                }
            }
            Button("In Projekte öffnen →", action: zuProjekten).buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel)
        }
        .frame(width: 252, alignment: .topLeading)
    }
}

struct SnGespraechFrage: View {
    var frage: SenecaStand.Frage
    var fokus: Bool
    var antworte: (String) -> Void
    @State private var mehr = false
    @State private var bericht = false

    var body: some View {
        let haupt = frage.optionen?.first { $0.wert == frage.empfehlung } ?? frage.optionen?.first
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(fokus ? "BRAUCHT DICH · NACH DEINEM FOKUS" : "BRAUCHT DICH").foregroundStyle(TafelFarbe.bernstein)
                Spacer()
                Text("\((frage.von ?? "").uppercased()) · \(frage.seit.map { HeuteTafelLogik.uhr($0) } ?? "")").foregroundStyle(TafelFarbe.leise)
            }
            .font(Schrift.mono(11)).kerning(1)
            Text(frage.text).font(Schrift.serif(30)).lineHeight(.exact(points: 34)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
            if let k = frage.kontext?.worum, !k.isEmpty {
                Text(k).font(Schrift.grotesk(15)).lineHeight(.exact(points: 23)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let h = haupt { Button(h.knopf ?? h.text ?? "Ja") { antworte(h.wert ?? "ja") }.buttonStyle(SnTafelKnopf(groesse: 14)) }
                Button("Später") { antworte("spaeter") }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 14))
                Button("Mehr") { mehr.toggle() }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 14))
            }
            .padding(.top, 2)
            if mehr, let w = frage.kontext?.wenn_nicht {
                Text(w).font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
            }
            if let l = frage.checkliste, !l.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(l, id: \.text) { p in
                        HStack(spacing: 10) {
                            Text(p.fertig ? "✓" : "○").foregroundStyle(p.fertig ? TafelFarbe.gruen : TafelFarbe.leise)
                            Text(p.text).foregroundStyle(p.fertig ? TafelFarbe.text : TafelFarbe.zweit)
                        }
                    }
                }
                .font(Schrift.grotesk(14)).lineHeight(.exact(points: 21))
                .padding(.top, 14).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }.padding(.top, 6)
            }
            if let b = frage.bericht {
                Button { withAnimation(Kurve.sn(0.25)) { bericht.toggle() } } label: {
                    HStack(spacing: 22) {
                        Text((bericht ? "▾ " : "▸ ") + "Ganzer Bericht").font(Schrift.grotesk(13))
                        Text(b.satz).font(Schrift.mono(12))
                    }
                    .foregroundStyle(TafelFarbe.leise).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if bericht {
                    Text(b.text).font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let l = b.beleg, let u = URL(string: l) { Link(l, destination: u).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.himmel) }
                }
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(TafelFarbe.bernstein.opacity(0.28), lineWidth: 1))
    }
}

struct SnGespraechLauf: View {
    var mitglied: SenecaStand.Mitglied
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(TafelFarbe.gruen).frame(width: 8, height: 8)
            Text(GL.laufSatz(mitglied))
                .font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(TafelFarbe.zweit)
            Spacer()
            Text("⌘. stoppt").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
        }
    }
}

struct SnGespraecheBild: View {
    var stand: SenecaStand
    var agent: String

    private func ms(_ h: Int, _ m: Int) -> Double { KalenderLogik.cal().startOfDay(for: HeuteTafelLogik.datum(stand.jetzt)).timeIntervalSince1970 * 1000 + Double(h * 60 + m) * 60_000 }

    private var zuege: [Zug] {
        if agent != Hauptagent.id {
            return [Zug(id: "t1", start: .user(id: "u1", text: "Bereite den Testanruf auf Staging vor. Ich will den Ablauf einmal mit echter Nummer hören.", ts: ms(9, 14), pending: false)),
                    Zug(id: "t2", start: .ereignis(ZugEreignis(id: "e1", art: .system, titel: "Engineer hat angefangen · Prüfer schaut mit", ts: ms(9, 15))))]
        }
        let gelesen = ["Kalender", "Hermes", "Nachricht", "Nachricht"].map { Schritt(art: .lesen, text: "gelesen", detail: $0) }
        return [Zug(id: "z1", start: .user(id: "u1", text: "Plan mir den Vormittag.", ts: ms(8, 52), pending: false), schritte: gelesen,
                    antwort: ZugAntwort(id: "a1", text: "Bis elf hast du Fokus. Danach eine Freigabe für Hermes, dann Mittag mit Nora.\n\nFragen aus dem Team halte ich bis dahin zurück. Hermes bleibt auf Kurs für den 1. Dezember.", ts: ms(8, 53)), von: ms(8, 53) - 14_000),
                Zug(id: "z2", start: .ereignis(ZugEreignis(id: "e1", art: .system, titel: "Prüfer hat Hermes getestet, keine Fehler", ts: ms(9, 40)))),
                Zug(id: "z3", start: .user(id: "u2", text: "Verschieb den Zahnarzt auf nächste Woche und sag Nora, dass ich zehn Minuten später komme.", ts: ms(10, 4), pending: false),
                    antwort: ZugAntwort(id: "a2", text: "Erledigt. Der Zahnarzt ist jetzt am Dienstag früh, und Nora weiß, dass du zehn Minuten später kommst.", ts: ms(10, 5)))]
    }

    var body: some View {
        GeometryReader { g in
            let sp = SnChatSeite.spalte(g.size.width, seneca: agent == Hauptagent.id)
            let m = stand.team?.first { $0.id == agent }
            ZStack(alignment: .topLeading) {
                SnGespraechLeiste(stand: stand, aktiv: agent, waehle: { _ in }, neu: {}).padding(.leading, 40).padding(.top, 108).padding(.bottom, 40).frame(height: g.size.height, alignment: .top)
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(zuege) { z in
                        ZugView(zug: z, lauf: nil, frisch: nil, zustand: nil, neu: false, name: "Seneca", gross: true,
                                quittung: VerlaufLogik.quittung(stand, sitzung: "agent:\(agent):main", von: z.startTs, bis: zuege.last(where: { $0.startTs != nil && $0.id != z.id && ($0.startTs ?? 0) > (z.startTs ?? 0) })?.startTs),
                                alt: z.startTs != nil && z.id != zuege.last(where: { $0.startTs != nil })?.id, erneut: {}).fixedSize(horizontal: false, vertical: true)
                    }
                    if let m, agent != Hauptagent.id {
                        ForEach(GL.fragen(stand, von: m.name)) { f in SnGespraechFrage(frage: f, fokus: stand.ruhe?.grund == "fokus", antworte: { _ in }) }
                        if m.zustand == "arbeitet" { SnGespraechLauf(mitglied: m) }
                    }
                }
                .frame(width: sp.breite, height: max(0, g.size.height - 220), alignment: .bottom).clipped().environment(\.festeZeit, stand.jetzt).padding(.leading, sp.links).padding(.top, 92)
                SnGespraechRand(stand: stand, agent: agent, zuProjekten: {}).padding(.leading, g.size.width - 40 - sp.rand).padding(.top, 108)
                HStack(spacing: 14) {
                    SnAnZeile(name: m?.name ?? "Seneca", seneca: agent == Hauptagent.id)
                    SnAnZeile.platzhalter(seneca: agent == Hauptagent.id)
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white).frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
                }
                .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 14).frame(width: sp.breite)
                .snGlas(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.leading, sp.links).padding(.top, g.size.height - 40 - 62)
            }
        }
    }
}
