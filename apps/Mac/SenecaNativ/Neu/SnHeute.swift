import SwiftUI

struct SnFluss: Layout {
    var abstand: CGFloat = 6
    var zeilenAbstand: CGFloat = 0

    private func rahmen(_ subviews: Subviews, breite: CGFloat) -> (frames: [CGRect], groesse: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHoehe: CGFloat = 0, maxX: CGFloat = 0
        var frames: [CGRect] = []
        for v in subviews {
            let s = v.sizeThatFits(.init(width: nil, height: nil))
            let w = min(s.width, breite)
            let h = v.sizeThatFits(.init(width: w, height: nil)).height
            if x > 0, x + w > breite { x = 0; y += zeilenHoehe + zeilenAbstand; zeilenHoehe = 0 }
            frames.append(CGRect(x: x, y: y, width: w, height: h))
            x += w + abstand; zeilenHoehe = max(zeilenHoehe, h); maxX = max(maxX, x - abstand)
        }
        var ergebnis = frames
        var i = 0
        while i < frames.count {
            var j = i
            while j < frames.count, frames[j].minY == frames[i].minY { j += 1 }
            let h = frames[i..<j].map(\.height).max() ?? 0
            for k in i..<j { ergebnis[k].origin.y += (h - frames[k].height) / 2 }
            i = j
        }
        return (ergebnis, CGSize(width: maxX, height: y + zeilenHoehe))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rahmen(subviews, breite: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? r.groesse.width, height: r.groesse.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rahmen(subviews, breite: bounds.width)
        for (v, f) in zip(subviews, r.frames) {
            v.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .init(width: f.width, height: f.height))
        }
    }
}

struct SnZeilenStil: ButtonStyle {
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Farbe.zeileHover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(configuration.isPressed ? Kurve.snFeder : Kurve.sn(0.25), value: configuration.isPressed)
            .animation(Kurve.sn(0.25), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnLeiserStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? Color.white : Farbe.ink2)
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnHeuteSeite: View {
    let quelle: any SenecaDatenQuelle
    @ObservedObject var notizen: NotizblockModell
    var aufgabenHeute: [SenecaTask]? = nil
    var neuesTodo: (String) -> Void = { _ in }
    var todoUmschalten: (String) -> Void = { _ in }
    var oeffneAufgabe: (SnAufgabe) -> Void = { _ in }
    var oeffneBriefing: (SnTermin) -> Void = { _ in }
    var liste: ArbeitsListe? = nil
    var gelesen: Set<String> = []
    var markiereGelesen: (String) -> Void = { _ in }
    var zuDenFragen: () -> Void = {}
    var tageslauf: Tageslauf? = nil
    var standWirdGelesen = false
    var tageslaufJetzt: Date? = nil
    var mitarbeiterName: (String) -> String? = { _ in nil }
    var nurMitarbeiterNennen = false
    var aufgaben: AufgabenListe? = nil
    var aufgabenLesbar = true
    var aufgabenWerdenGelesen = false
    var aufgabenVoll = false
    var zeigeAufgabenVoll: (Bool) -> Void = { _ in }
    var oeffneAufgabeId: (String) -> Void = { _ in }
    var agentenOffenZuBeginn = false
    var zuletztOffenZuBeginn = false

    var body: some View {
        GeometryReader { g in
            let rand = min(120, max(40, (g.size.width - 1000) * 0.2727))
            ScrollViewReader { leser in
                ScrollView(.vertical, showsIndicators: false) {
                    inhalt
                        .padding(.horizontal, rand).padding(.top, 96).padding(.bottom, 150)
                        .frame(width: g.size.width, alignment: .leading)
                }
                .scrollClipDisabled()
                .snSeitenBlende()
                #if DEBUG
                .task {
                    guard Hintergrund.aktiv, let ziel = ProcessInfo.processInfo.environment["SENECA_TEST_SCROLL"], !ziel.isEmpty else { return }
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    leser.scrollTo(ziel, anchor: .top)
                }
                #endif
            }
        }
        .accessibilityIdentifier("seite-heute")
    }

    private var inhalt: some View {
        let nun = tageslaufJetzt ?? Date()
        let sicht = tageslauf.map { t -> TageslaufSicht in
            var s = TageslaufSicht(t, jetzt: nun, name: { kennung in
                if let m = mitarbeiterName(kennung) { return m }
                let n = quelle.agent(kennung).name
                return n == kennung ? TageslaufSicht.schoenerName(kennung) : n
            })
            s.ergaenze(termine: quelle.termine.map { ($0.zeit, $0.titel, $0.nebenzeile) }, jetzt: nun)
            return s
        }.flatMap { $0.istLeer ? nil : $0 }
        let fuer = tageslauf?.fuerDich, lauf = tageslauf?.laeuft
        let imBlock = Set((aufgabenHeute ?? []).map(\.id))
        let ausQuelle = quelle.istEcht || fuer != nil || lauf != nil || aufgaben != nil
        let fragenSatz = (liste ?? tageslauf?.liste).map { BoardSicht.nurFragenSatz($0.fragen.count) }
        let satz: (String, String) = !ausQuelle
            ? SnHeute.satz(entscheidungen: quelle.aufgaben.filter { $0.status == .wartetAufDich }.count)
            : aufgaben.map { $0.heuteSatz } ?? (aufgabenWerdenGelesen ? ("Die Aufgaben ", "werden gelesen.") : ("Aufgaben ", "sind gerade nicht lesbar."))
        return VStack(alignment: .leading, spacing: 0) {
            datumsZeile.snRein()
            (Text(satz.0).font(Schrift.serif(56)).foregroundStyle(Color.white)
                + Text(satz.1).font(Schrift.serif(56, kursiv: true)).foregroundStyle(Farbe.kugelKern))
                .tracking(-0.5)
                .lineHeight(.exact(points: 58.24))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .snMaske(0.06)
                .accessibilityAddTraits(.isHeader)
            if let h = quelle.hinweis {
                Text(h).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).padding(.top, 10).snRein(0.1)
            }
            if let f = fragenSatz, !f.isEmpty {
                Button { zuDenFragen() } label: {
                    HStack(spacing: 7) {
                        Text(f + ".").font(Schrift.grotesk(15))
                        Text("Zu den Fragen").font(Schrift.grotesk(15, .medium))
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .padding(.top, 14).snRein(0.1)
                .accessibilityIdentifier("heute-zu-den-fragen")
            }
            Color.clear.frame(height: 0).id("board")
            if aufgabenVoll {
                Button { zeigeAufgabenVoll(false) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 11, weight: .semibold))
                        Text("Zurück zu Heute").font(Schrift.grotesk(14))
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .padding(.top, 14)
                .accessibilityIdentifier("aufgaben-zurueck")
                SnAufgabenVoll(liste: aufgaben, lesbar: aufgabenLesbar, wirdGelesen: aufgabenWerdenGelesen, jetzt: nun, oeffne: oeffneAufgabeId,
                               agentenOffenZuBeginn: agentenOffenZuBeginn, zuletztOffenZuBeginn: zuletztOffenZuBeginn)
                    .padding(.top, 28)
            } else if ausQuelle {
                SnAufgabenHeute(liste: aufgaben, lesbar: aufgabenLesbar, wirdGelesen: aufgabenWerdenGelesen, jetzt: nun, oeffne: oeffneAufgabeId,
                                zeigeVoll: { zeigeAufgabenVoll(true) })
                    .padding(.top, 44)
            }
            let menschen = sicht.map { s -> TageslaufSicht in var t = s; t.wartet = s.wartet.filter(\.mensch); return t }
            let links = menschen.map { !$0.wartet.isEmpty || !$0.zugesagt.isEmpty } ?? false
            if !aufgabenVoll { HStack(alignment: .top, spacing: links ? 80 : 48) {
                if links, let s = menschen {
                    VStack(alignment: .leading, spacing: 0) {
                        if !s.wartet.isEmpty { tageslaufWartet(s).padding(.bottom, 44) }
                        if !s.zugesagt.isEmpty { tageslaufZugesagt(s) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        if let s = sicht, !s.zeitleiste.isEmpty { tageslaufZeitleiste(s) } else { termine }
                        blatt.padding(.top, 30)
                    }
                    .frame(width: 400)
                } else {
                    Group { if let s = sicht, !s.zeitleiste.isEmpty { tageslaufZeitleiste(s) } else { termine } }.frame(width: 400)
                    blatt.frame(width: 400)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 56) }
            if !aufgabenVoll, let z = (liste ?? tageslauf?.liste).map({ ZusagenSicht($0, jetzt: nun) }), !z.istLeer {
                zusagenAbschnitt(z).padding(.top, 44)
            }
        }
    }

    private func zusagenAbschnitt(_ z: ZusagenSicht) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ZusagenSicht.titel).font(Schrift.serif(24)).foregroundStyle(Farbe.ink1)
                Text(z.zahl).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
            }
            .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.top, 12)
            ForEach(z.zeilen) { zeile in
                VStack(alignment: .leading, spacing: 5) {
                    Text(zeile.kopf).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
                    Text(zeile.wortlaut).font(Schrift.grotesk(15)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                    if !zeile.grund.isEmpty {
                        Text(zeile.grund).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("heute-zusagen")
        .snRein(0.12)
    }

    @ViewBuilder private var blatt: some View {
        if let echt = aufgabenHeute {
            let heute = DayLogic.dayKey(Date(), .current)
            SnNotizblockBlatt(zeilen: echt.map { SnBlattZeile.echt($0, heute: heute) }, anlegen: neuesTodo, umschalten: todoUmschalten)
        } else {
            SnNotizblockBlatt(zeilen: notizen.eintraege.map {
                SnBlattZeile(id: $0.id, titel: $0.titel, meta: $0.meta, seit: "", fertig: notizen.erledigt.contains($0.id), ueberfaellig: $0.ueberfaellig)
            }, anlegen: { notizen.anlegen($0) }, umschalten: { notizen.umschalten($0) })
        }
    }

    private var datumsZeile: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            Text(Self.datum(ctx.date))
                .font(Schrift.mono(13)).tracking(0.4).foregroundStyle(Farbe.ink2)
        }
    }

    static func datum(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM · HH:mm"
        return f.string(from: d)
    }

    private var termine: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Termine").font(Schrift.serif(26)).foregroundStyle(Color.white)
                .frame(height: 28.6, alignment: .leading)
                .padding(.bottom, 6)
                .snRein(0.26)
                .accessibilityAddTraits(.isHeader)
            if quelle.termine.isEmpty {
                Text("Heute stehen keine Termine mehr an.").font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink2)
                    .padding(.vertical, 10).snRein(0.3)
            }
            ForEach(Array(quelle.termine.enumerated()), id: \.element.id) { i, t in
                terminZeile(t, erster: i == 0).snRein(0.3 + Double(i) * 0.06)
            }
        }
        .padding(.top, 20).padding(.horizontal, 24).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .snGlas(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, -20)
        .snRein(0.22)
    }

    private func terminZeile(_ t: SnTermin, erster: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(t.zeit).font(Schrift.mono(13)).tracking(0.2).foregroundStyle(erster ? Farbe.himmel : Farbe.ink2)
                .frame(width: 52, height: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.titel).font(Schrift.grotesk(erster ? 18 : 16, erster ? .medium : .regular)).lineHeight(.exact(points: 24)).foregroundStyle(Color.white)
                Text(t.nebenzeile).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(Farbe.ink2)
            }
            Spacer(minLength: 0)
            if t.hatBriefing {
                Button { oeffneBriefing(t) } label: {
                    Text("Briefing").font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel).padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
