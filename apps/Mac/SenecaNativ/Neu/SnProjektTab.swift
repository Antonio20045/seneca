import SwiftUI

struct SnProjektTabSeite: View {
    let liste: ArbeitsListe?
    var wirdGelesen = false
    var jetzt = Date()
    var startBereich: String? = nil
    var startProjekt: String? = nil
    var oeffne: (_ id: String, _ titel: String) -> Void = { _, _ in }
    var zuDenFragen: () -> Void = {}

    @AppStorage("seneca-nativ.projektTab.bereich", store: Hintergrund.defaults()) private var gemerkt = ""
    @State private var projekt: String?
    @State private var eingangOffen = Set<String>()

    private static let links: CGFloat = 270

    var body: some View {
        GeometryReader { g in
            let rand = min(120, max(40, (g.size.width - 1000) * 0.2727))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let liste {
                        let s = ProjektTabSicht(liste, bereich: startBereich ?? (gemerkt.isEmpty ? nil : gemerkt), jetzt: jetzt)
                        inhalt(s)
                    } else {
                        Text(wirdGelesen ? "Die Projekte werden gelesen." : "Zu den Projekten liegt gerade kein Stand vor.")
                            .font(Schrift.serif(40)).foregroundStyle(Farbe.ink2)
                    }
                }
                .padding(.horizontal, rand).padding(.top, 96).padding(.bottom, 150)
                .frame(width: g.size.width, alignment: .leading)
            }
            .scrollClipDisabled()
            .snSeitenBlende()
        }
        .onAppear { if projekt == nil { projekt = startProjekt } }
        .accessibilityIdentifier("seite-projekte")
    }

    @ViewBuilder private func inhalt(_ s: ProjektTabSicht) -> some View {
        Text(s.fristSatz).font(Schrift.serif(44)).lineHeight(.exact(points: 50)).foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 900, alignment: .leading)
            .snMaske()
            .accessibilityAddTraits(.isHeader)
        SnReiter(eintraege: s.reiter.map { ($0.id, $0.name + ($0.offen > 0 ? "  \($0.offen)" : "")) },
                 gewaehlt: Binding(get: { s.gewaehlt }, set: { neu in withAnimation(Kurve.sn(0.35)) { gemerkt = neu; projekt = nil } }))
            .padding(.top, 34)
            .snRein(0.08)
        graph(s).padding(.top, 30).snRein(0.14)
        if let p = s.projekte.first(where: { $0.id == projekt }) {
            einzeln(p, s).padding(.top, 44).snRein(0.05).id(p.id)
        } else {
            VStack(alignment: .leading, spacing: 0) { alle(s) }.padding(.top, 44).snRein(0.2)
        }
    }

    private func farbe(_ dringlich: Int) -> Color { dringlich == 2 ? Farbe.koralle : (dringlich == 1 ? Farbe.bernstein : Farbe.himmel) }

    private func graph(_ s: ProjektTabSicht) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.links, height: 1)
                GeometryReader { g in
                    ForEach(s.marken) { m in
                        Text(m.text).font(Schrift.mono(11)).foregroundStyle(Farbe.ink3).fixedSize().position(x: g.size.width * m.ort, y: 8)
                    }
                    Text("heute").font(Schrift.grotesk(11, .medium)).foregroundStyle(Color.white).fixedSize().position(x: g.size.width * s.heute, y: 8)
                        .background(Farbe.nacht.opacity(0.01))
                }
                .frame(height: 18)
            }
            if s.projekte.isEmpty {
                Text("In diesem Bereich gibt es kein Projekt. Seine Aufgaben stehen unten unter „Ohne Projekt“.")
                    .font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink3).padding(.vertical, 18)
            }
            ForEach(s.projekte) { p in projektZeile(p, s) }
        }
        .accessibilityIdentifier("projekt-graph")
    }

    private func projektZeile(_ p: ProjektTabSicht.Projekt, _ s: ProjektTabSicht) -> some View {
        let an = projekt == p.id
        return Button { withAnimation(Kurve.sn(0.4)) { projekt = an ? nil : p.id } } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(Schrift.grotesk(16, .medium)).foregroundStyle(Color.white).lineLimit(1)
                    Text(p.stand).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1)
                }
                .frame(width: Self.links - 16, alignment: .leading).padding(.trailing, 16)
                GeometryReader { g in
                    let w = g.size.width, y = g.size.height / 2, x0 = w * s.heute
                    ForEach(s.marken) { m in Rectangle().fill(Farbe.linie2).frame(width: 1, height: g.size.height).position(x: w * m.ort, y: y) }
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: g.size.height).position(x: x0, y: y)
                    if let o = p.ort {
                        let x1 = w * o
                        Capsule().fill(farbe(p.dringlich).opacity(0.55)).frame(width: max(3, abs(x1 - x0)), height: 5).position(x: (x0 + x1) / 2, y: y)
                        ForEach(p.meilensteine.filter { $0.ort != nil }) { m in
                            Rectangle().fill(m.erreicht ? Farbe.gruen : Farbe.nacht).frame(width: 7, height: 7)
                                .overlay(Rectangle().strokeBorder(m.erreicht ? Farbe.gruen : Color.white.opacity(0.8), lineWidth: 1.2))
                                .rotationEffect(.degrees(45)).position(x: w * (m.ort ?? 0), y: y)
                                .help(Self.meilensteinHilfe(m.name, m.datum, m.erreicht))
                        }
                        Circle().fill(farbe(p.dringlich)).frame(width: 11, height: 11).position(x: x1, y: y)
                        Text(p.fristTag + " · " + p.fristRest).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(farbe(p.dringlich)).fixedSize()
                            .position(x: x1, y: y).offset(x: x1 > w * 0.7 ? -86 : 86)
                    } else {
                        Path { pfad in pfad.move(to: CGPoint(x: x0, y: y)); pfad.addLine(to: CGPoint(x: w, y: y)) }
                            .stroke(Farbe.ink4, style: StrokeStyle(lineWidth: 1.2, dash: [2, 6]))
                        Text("ohne Frist").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).fixedSize().position(x: x0 + 48, y: y - 10)
                    }
                    ForEach(p.aufgaben.filter { $0.ort != nil }) { a in
                        Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5, height: 11).position(x: w * (a.ort ?? 0), y: y)
                            .help(a.titel + ", " + a.fristText)
                    }
                }
                .frame(height: 46)
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(an ? Farbe.auswahl : .clear))
        }
        .buttonStyle(SnZeilenStil())
        .padding(.horizontal, -12)
        .overlay(alignment: .top) { Rectangle().fill(Farbe.linie2).frame(height: 1) }
        .help(p.ziel.isEmpty ? "Aufgaben dieses Projekts zeigen" : "Ziel: " + p.ziel)
        .accessibilityLabel(p.name + (p.fristTag.isEmpty ? ", ohne Frist" : ", Frist " + p.fristTag + ", " + p.fristRest) + ", " + p.stand)
        .accessibilityAddTraits(an ? [.isSelected] : [])
        .accessibilityIdentifier("projekt-zeile")
    }

    @ViewBuilder private func alle(_ s: ProjektTabSicht) -> some View {
        let mit = s.projekte.filter { !$0.aufgaben.isEmpty || !$0.eingang.isEmpty }
        Text("Aufgaben").font(Schrift.serif(30)).foregroundStyle(Color.white).padding(.bottom, 14).accessibilityAddTraits(.isHeader)
        if mit.isEmpty, s.ohneProjekt.aufgaben.isEmpty, s.ohneProjekt.eingang.isEmpty {
            Text("In diesem Bereich ist keine Aufgabe offen.").font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink3)
        }
        ForEach(mit) { p in gruppe(p, kopf: "Gehört zu " + p.name) }
        if !s.ohneProjekt.aufgaben.isEmpty || !s.ohneProjekt.eingang.isEmpty { gruppe(s.ohneProjekt, kopf: "Ohne Projekt") }
    }

    private func gruppe(_ p: ProjektTabSicht.Projekt, kopf: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SnGruppenKopf(name: kopf, neben: p.stand)
            aufgaben(p)
        }
        .padding(.bottom, 26)
    }

    @ViewBuilder private func aufgaben(_ p: ProjektTabSicht.Projekt) -> some View {
        ForEach(Array(p.aufgaben.enumerated()), id: \.element.id) { i, a in
            aufgabe(a)
            if i < p.aufgaben.count - 1 { Rectangle().fill(Farbe.linie2).frame(height: 1) }
        }
        if !p.eingang.isEmpty {
            let offen = eingangOffen.contains(p.id)
            Button { withAnimation(Kurve.sn(0.35)) { if offen { eingangOffen.remove(p.id) } else { eingangOffen.insert(p.id) } } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(offen ? 90 : 0))
                    Text("Noch nicht angenommen").font(Schrift.grotesk(13, .medium))
                    Text("\(p.eingang.count)").font(Schrift.mono(12))
                }
                .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            if offen { ForEach(p.eingang) { aufgabe($0, knapp: true) } }
        }
    }

    @ViewBuilder private func punkt(_ zustand: String) -> some View {
        switch zustand {
        case "läuft": Circle().fill(Farbe.himmel)
        case "blockiert": Circle().fill(Farbe.koralle)
        case "wartet auf Antonio": Circle().fill(Farbe.bernstein)
        case "fertig": Circle().fill(Farbe.gruen)
        case "bereit": Circle().strokeBorder(Farbe.ink2, lineWidth: 1.5)
        default: Circle().strokeBorder(Farbe.ink4, lineWidth: 1.5)
        }
    }

    private func lageFarbe(_ zustand: String) -> Color {
        switch zustand { case "läuft": Farbe.himmel; case "blockiert": Farbe.koralle; case "wartet auf Antonio": Farbe.bernstein; case "fertig": Farbe.gruen; default: Farbe.ink3 }
    }

    private func aufgabe(_ a: ProjektTabSicht.Aufgabe, knapp: Bool = false) -> some View {
        Button { if a.zustand == "wartet auf Antonio" { zuDenFragen() } else { oeffne(a.id, a.titel) } } label: {
            HStack(alignment: .top, spacing: 14) {
                punkt(a.zustand).frame(width: 8, height: 8).padding(.top, 7)
                VStack(alignment: .leading, spacing: 5) {
                    Text(a.titel).font(Schrift.grotesk(knapp ? 14.5 : 16)).lineHeight(.exact(points: knapp ? 20 : 22)).foregroundStyle(knapp ? Farbe.ink2 : Color.white)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    SnFluss(abstand: 7, zeilenAbstand: 3) {
                        if !a.marke.isEmpty { SnMarke(text: a.marke) }
                        Text(a.lage).font(Schrift.grotesk(12.5, .medium)).foregroundStyle(lageFarbe(a.zustand))
                        if !a.wer.isEmpty { Text(a.wer).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2) }
                        if !a.fristText.isEmpty { Text(a.fristText).font(Schrift.grotesk(12.5)).foregroundStyle(a.dringlich == 2 ? Farbe.koralle : (a.dringlich == 1 ? Farbe.bernstein : Farbe.ink2)) }
                    }
                    if !a.halt.isEmpty {
                        Text(a.halt).font(Schrift.grotesk(12.5)).lineHeight(.exact(points: 17)).foregroundStyle(Farbe.warnText)
                            .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true).help(a.halt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !knapp { SnWegLinie(weg: a.weg).frame(width: 380).padding(.top, -4) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .buttonStyle(SnZeilenStil())
        .padding(.horizontal, -12)
        .help(a.zustand == "wartet auf Antonio" ? "Steht unter „Fragen“" : (a.wortlaut.isEmpty ? "" : "Wortlaut der Karte: " + a.wortlaut))
        .accessibilityIdentifier("projekt-aufgabe")
    }

    private func einzeln(_ p: ProjektTabSicht.Projekt, _ s: ProjektTabSicht) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(p.name).font(Schrift.serif(34)).foregroundStyle(Color.white).accessibilityAddTraits(.isHeader)
                if !p.fristTag.isEmpty {
                    (Text("bis " + p.fristTag).foregroundColor(.white) + Text(" · " + p.fristRest).foregroundColor(farbe(p.dringlich))).font(Schrift.grotesk(15, .medium))
                } else {
                    Text("ohne Frist").font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink3)
                }
                Spacer(minLength: 0)
                Button { withAnimation(Kurve.sn(0.4)) { projekt = nil } } label: {
                    Text("Alle Aufgaben des Bereichs").font(Schrift.grotesk(13, .medium)).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
            }
            if !p.ziel.isEmpty {
                (Text("Ziel: ").foregroundColor(Farbe.ink3) + Text(p.ziel).foregroundColor(Farbe.ink2)).font(Schrift.grotesk(15)).lineHeight(.exact(points: 22))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 820, alignment: .leading).padding(.top, 8)
            }
            Text("Stand: " + p.stand + (p.wer.isEmpty ? "" : " · zuständig " + p.wer)).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).padding(.top, 6)
            if !p.meilensteine.isEmpty {
                SnFluss(abstand: 18, zeilenAbstand: 4) {
                    ForEach(p.meilensteine) { m in
                        HStack(spacing: 7) {
                            Group { if m.erreicht { Circle().fill(Farbe.gruen) } else { Circle().strokeBorder(Farbe.ink3, lineWidth: 1.2) } }.frame(width: 8, height: 8)
                            Text(m.name + (m.datum.isEmpty ? "" : ", " + m.datum)).font(Schrift.grotesk(13.5)).foregroundStyle(m.erreicht ? Farbe.ink3 : Farbe.ink)
                        }
                    }
                }
                .padding(.top, 10)
            }
            let mitFrist = p.aufgaben.filter { $0.ort != nil }
            if !mitFrist.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(mitFrist) { a in
                        HStack(spacing: 0) {
                            Text(a.titel).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink).lineLimit(1)
                                .frame(width: Self.links - 16, alignment: .leading).padding(.trailing, 16)
                            GeometryReader { g in
                                let w = g.size.width, y = g.size.height / 2, x0 = w * s.heute, x1 = w * (a.ort ?? 0)
                                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: g.size.height).position(x: x0, y: y)
                                Capsule().fill(lageFarbe(a.zustand).opacity(0.45)).frame(width: max(3, abs(x1 - x0)), height: 3).position(x: (x0 + x1) / 2, y: y)
                                Circle().fill(a.dringlich == 2 ? Farbe.koralle : (a.dringlich == 1 ? Farbe.bernstein : Color.white)).frame(width: 8, height: 8).position(x: x1, y: y)
                                Text(a.fristText).font(Schrift.grotesk(12)).foregroundStyle(a.dringlich == 2 ? Farbe.koralle : (a.dringlich == 1 ? Farbe.bernstein : Farbe.ink2)).fixedSize()
                                    .position(x: max(x0, x1), y: y).offset(x: max(x0, x1) > w * 0.6 ? -110 - abs(x1 - x0) : 110)
                            }
                            .frame(height: 30)
                        }
                    }
                }
                .padding(.top, 22)
            }
            VStack(alignment: .leading, spacing: 0) {
                SnGruppenKopf(name: "Aufgaben", neben: mitFrist.isEmpty && !p.aufgaben.isEmpty ? "keine hat eine eigene Frist" + (p.fristTag.isEmpty ? "" : ", es gilt die des Projekts") : "")
                if p.aufgaben.isEmpty { Text("Keine offene Aufgabe.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3).padding(.vertical, 10) }
                aufgaben(p)
            }
            .padding(.top, 22)
        }
        .accessibilityIdentifier("projekt-einzeln")
    }

    static func meilensteinHilfe(_ name: String, _ datum: String, _ erreicht: Bool) -> String {
        let teil = datum.isEmpty ? "" : ", " + datum
        return name + teil + (erreicht ? " (erreicht)" : "")
    }
}

struct SnProjekteEcht: View {
    let modell: AppModell
    @ObservedObject private var liste = ListenModell.gemeinsam

    var body: some View {
        SnProjektTabSeite(liste: liste.liste, wirdGelesen: !liste.einmalGelesen,
                          oeffne: { id, titel in
                              modell.gehe(Route(.heute))
                              Task {
                                  try? await Task.sleep(for: .milliseconds(450))
                                  modell.snFenster.oeffne(SnAufgabe(id: "k:" + id, projekt: "", agentId: "", status: .laeuft, prio: 2, titel: titel, seit: "", frist: nil, heuteFertig: false), anker: nil)
                              }
                          },
                          zuDenFragen: { modell.gehe(Route(.entscheidungen)) })
            .task { await liste.beobachte() }
    }
}
