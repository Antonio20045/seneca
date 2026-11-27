import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
}

struct SnTafelKnopf: ButtonStyle {
    var art: Art = .voll
    var groesse: CGFloat = 15
    enum Art { case voll, rand, leise }
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize()
            .font(Schrift.grotesk(groesse, .medium))
            .foregroundStyle(art == .voll ? TafelFarbe.aufHimmel : art == .rand ? TafelFarbe.text : TafelFarbe.zweit)
            .padding(.horizontal, art == .leise ? 12 : groesse <= 14 ? 16 : art == .rand ? 18 : 20).padding(.vertical, groesse > 14 ? 10 : 8)
            .background(Capsule().fill(art == .voll ? TafelFarbe.himmel.opacity(hover ? 0.9 : 1) : Color.white.opacity(hover ? 0.05 : 0)))
            .overlay { if art == .rand { Capsule(style: .circular).strokeBorder(Color.white.opacity(0.22), lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Kurve.snFeder, value: configuration.isPressed)
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnTafelGrund: View {
    var glanz: Color
    var stufen: [(deckkraft: Double, ort: Double)]

    var body: some View {
        GeometryReader { g in
            let ende = stufen.last?.ort ?? 0.3
            ZStack {
                LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
                RadialGradient(stops: stufen.map { .init(color: glanz.opacity($0.deckkraft), location: $0.ort / ende) },
                               center: UnitPoint(x: 0.76, y: 0.10), startRadius: 0, endRadius: hypot(g.size.width, g.size.height) / 2.squareRoot() * ende)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SnEntscheidenTafel: View {
    var stand: SenecaStand
    var antworte: (String, String) -> Void
    var handle: (String, String, String?) -> Void

    @State private var wahl: [String: String] = [:]
    @Environment(\.mehrZu) private var mehrZu
    @State var beantwortet: [String: (wahl: String, um: Date)] = [:]
    @State var spaeter: [String: Date] = [:]
    @State var zurueck: Set<String> = []
    @State private var nachbessern: String?
    @State private var notiz = ""
    @State var imBuendel = false
    @State var pausiert: Date?

    private typealias L = HeuteTafelLogik

    private var fragen: [SenecaStand.Frage] {
        ((stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? [])).filter { $0.antwort == nil || beantwortet[$0.id] != nil }
    }

    var body: some View {
        if imBuendel {
            SnBuendelTafel(stand: stand, handle: handle, pause: { withAnimation(Kurve.sn(0.3)) { imBuendel = false; pausiert = Date() } })
                .transition(.opacity)
        } else {
            seiteFragen
        }
    }

    private var seiteFragen: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 84) {
                    haupt.frame(width: 880, alignment: .topLeading)
                    seite.frame(width: 300, alignment: .topLeading)
                }
                .padding(.leading, max(24, (g.size.width - 1248) / 2))
                .padding(.top, 108).padding(.bottom, 140)
                .frame(width: g.size.width, alignment: .topLeading)
            }
            .scrollClipDisabled()
        }
        .background(SnTafelGrund(glanz: TafelFarbe.bernstein, stufen: [(0.10, 0), (0, 0.26)]))
        .foregroundStyle(TafelFarbe.text)
        .accessibilityIdentifier("seite-fragen")
    }

    private var haupt: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(L.wochentag(stand.jetzt)) · \(L.uhr(stand.jetzt))").font(Schrift.mono(13)).foregroundStyle(TafelFarbe.zweit)
                if let k = kapsel {
                    Text(k).font(Schrift.mono(11)).tracking(1.2).foregroundStyle(TafelFarbe.hex(0xF3D58E))
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(TafelFarbe.bernstein.opacity(0.16)))
                }
            }
            .padding(.bottom, 14)
            if let s = stand.entscheiden?.satz, s.count == 2 {
                (Text(s[0] + " ").font(Schrift.serif(44)).foregroundColor(.white) + Text(s[1]).font(Schrift.serif(44, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                    .tracking(-0.5).hoehe(46.6).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(fragen) { f in karte(f).padding(.top, 28) }
            ForEach(stand.vorbei ?? []) { v in vorbei(v).padding(.top, 14) }
            buendel.padding(.top, 26)
        }
    }

    private var kapsel: String? {
        guard let e = stand.entscheiden, let von = e.fenster, let bis = e.fenster_bis else { return nil }
        if stand.jetzt >= von && stand.jetzt < bis { return "ENTSCHEIDUNGSFENSTER BIS \(L.uhr(bis))" }
        return stand.jetzt < von && von - stand.jetzt < 86_400_000 ? "ENTSCHEIDUNGSFENSTER UM \(L.uhr(von))" : nil
    }

    @ViewBuilder private func karte(_ f: SenecaStand.Frage) -> some View {
        let form = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let optionen = (f.optionen ?? []).filter { $0.wert != "spaeter" }
        let gewaehlt = wahl[f.id] ?? f.empfehlung ?? optionen.first?.wert
        let option = optionen.first { $0.wert == gewaehlt }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(([(f.von ?? "Seneca") + " fragt", f.frist.map { L.frist($0, jetzt: stand.jetzt) }] as [String?]).compactMap { $0 }.joined(separator: " · ").uppercased())
                    .foregroundStyle(TafelFarbe.bernstein)
                Spacer()
                Text((f.projekt ?? "").uppercased()).foregroundStyle(TafelFarbe.leise)
            }
            .font(Schrift.mono(11)).tracking(1)
            Text(f.text).font(Schrift.grotesk(22, .medium)).hoehe(30).foregroundStyle(.white).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            if f.antwort == nil, let g = f.zustellung?.first(where: { $0.was == "gesehen" && $0.geraet != "mac" }), let z = g.zeit {
                HStack(spacing: 7) {
                    Circle().fill(TafelFarbe.leise).frame(width: 5, height: 5)
                    Text("\(g.geraet == "uhr" ? "an der Uhr" : "am iPhone") gesehen · \(L.uhr(z))")
                }
                .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 6)
            }
            if zurueck.contains(f.id) {
                Text("Zurückgenommen. Die Frage ist wieder offen.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit).padding(.top, 10).transition(.opacity)
            }
            if optionen.contains(where: { $0.titel != nil }) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(optionen, id: \.wert) { o in fassung(o, an: o.wert == gewaehlt, empfohlen: o.wert == f.empfehlung) { wahl[f.id] = o.wert } }
                }
                .padding(.top, 16)
            }
            if let b = beantwortet[f.id] {
                quittung(f, b.wahl, seit: b.um).padding(.top, 18)
            } else if let seit = spaeter[f.id] {
                spaeterQuittung(f, seit: seit).padding(.top, 18)
            } else {
                HStack(spacing: 10) {
                    if optionen.contains(where: { $0.titel != nil }) || optionen.count == 1 {
                        Button(option?.knopf ?? option?.text ?? "Ja") { senden(f, gewaehlt) }.buttonStyle(SnTafelKnopf())
                    } else {
                        ForEach(Array(optionen.enumerated()), id: \.element.wert) { i, o in
                            Button(o.knopf ?? o.text ?? "") { senden(f, o.wert) }.buttonStyle(SnTafelKnopf(art: i == 0 ? .voll : .rand))
                        }
                    }
                    Button("Später") { zurueck.remove(f.id); spaeter[f.id] = Date() }.buttonStyle(SnTafelKnopf(art: .rand))
                    Button("Mehr") { mehrZu(f) }
                        .buttonStyle(SnTafelKnopf(art: .leise))
                    Spacer(minLength: 12)
                    if let folge = f.folge ?? option?.folge {
                        Text(folge).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).lineLimit(2).multilineTextAlignment(.trailing)
                    }
                }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 24)
        .background(form.fill(Color.white.opacity(0.06)))
        .overlay(form.strokeBorder(TafelFarbe.bernstein.opacity(0.26), lineWidth: 1))
        .overlay(form.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .clear, location: 0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func fassung(_ o: SenecaStand.Option, an: Bool, empfohlen: Bool, waehle: @escaping () -> Void) -> some View {
        let form = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: waehle) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text((o.titel ?? "").uppercased())
                    Spacer()
                    if empfohlen { Text("EMPFOHLEN") }
                }
                .font(Schrift.mono(11)).tracking(1).foregroundStyle(an ? TafelFarbe.akzent : TafelFarbe.leise)
                if let p = o.preis {
                    (Text(p).font(Schrift.grotesk(26, .medium)).foregroundColor(.white) + Text(o.einheit.map { " \($0)" } ?? "").font(Schrift.grotesk(14)).foregroundColor(TafelFarbe.leise))
                        .monospacedDigit().padding(.top, 10)
                }
                Text(o.text ?? "").font(Schrift.grotesk(13)).hoehe(19).foregroundStyle(TafelFarbe.zweit).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(form.fill(an ? TafelFarbe.himmel.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(form.strokeBorder(an ? TafelFarbe.himmel : Color.white.opacity(0.1), lineWidth: an ? 1.5 : 1))
            .contentShape(form)
        }
        .buttonStyle(.plain)
        .animation(Kurve.sn(0.25), value: an)
    }

    private func quittung(_ f: SenecaStand.Frage, _ w: String, seit: Date) -> some View {
        let o = f.optionen?.first { $0.wert == w }
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        return TimelineView(.periodic(from: seit, by: 0.1)) { t in
            let rest = max(0, frist - t.date.timeIntervalSince(seit))
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                    Text(o?.quittung ?? o?.text ?? w).font(Schrift.grotesk(16, .medium)).foregroundStyle(.white)
                    Spacer()
                    if rest > 0 {
                        Button("Rückgängig") { handle("rueckgaengig", f.id, nil); beantwortet[f.id] = nil; zurueck.insert(f.id) }
                            .buttonStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.himmel)
                    }
                }
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.zweit).frame(width: g.size.width * rest / frist) }
                }
                .frame(height: 3).opacity(rest > 0 ? 1 : 0)
            }
        }
    }

    private func spaeterQuittung(_ f: SenecaStand.Frage, seit: Date) -> some View {
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        let um = f.spaeter_bis ?? stand.jetzt
        let fenster = stand.entscheiden?.fenster.map { L.uhr($0) == L.uhr(um) } ?? false
        let morgen = Calendar.current.startOfDay(for: L.datum(um)) > Calendar.current.startOfDay(for: L.datum(stand.jetzt))
        return TimelineView(.periodic(from: seit, by: 0.1)) { t in
            let rest = max(0, frist - t.date.timeIntervalSince(seit))
            VStack(alignment: .leading, spacing: 4) {
                Text("Kommt \(morgen ? "morgen " : "")um \(L.uhr(um)) wieder").font(Schrift.grotesk(15, .medium)).foregroundStyle(.white)
                HStack(spacing: 0) {
                    Text(fenster ? "im Entscheidungsfenster · " : "vor der Frist · ")
                    Button("Rückgängig") { spaeter[f.id] = nil }.buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel)
                }
                .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.zweit).frame(width: g.size.width * rest / frist) }
                }
                .frame(height: 3).padding(.top, 6)
            }
            .onChange(of: rest == 0) { _, aus in if aus { antworte(f.id, "spaeter"); spaeter[f.id] = nil } }
        }
    }

    private func vorbei(_ v: SenecaStand.Vorbei) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if v.zustand == "abgelaufen" {
                Text((["ABGELAUFEN", v.frist.map { L.frist($0, jetzt: stand.jetzt) }] as [String?]).compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(Schrift.mono(11, .medium)).tracking(1).foregroundStyle(TafelFarbe.leise)
            }
            Text(v.text).font(Schrift.grotesk(17)).strikethrough().foregroundStyle(TafelFarbe.leise)
            if let s = v.satz { Text(s).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit) }
        }
        .padding(.horizontal, 26).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func senden(_ f: SenecaStand.Frage, _ w: String?) {
        guard let w else { return }
        antworte(f.id, w)
        beantwortet[f.id] = (w, Date())
    }

    @ViewBuilder private var buendel: some View {
        if let b = stand.buendel, let p = b.fortschritt, p.gesamt > 0 {
            if let z = p.abschluss {
                Self.ablaufKarte(L.uhr(stand.jetzt), z) {
                    HStack(spacing: 22) {
                        ForEach([((p.passt ?? []).count, "PASST"), ((p.zurueck ?? []).count, "NACHBESSERN")], id: \.1) { n, t in
                            VStack(alignment: .leading, spacing: 0) { Text("\(n)").font(Schrift.grotesk(26, .medium)).foregroundStyle(.white); Text(t).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise) }
                        }
                    }
                    Text(stand.entscheiden?.danach_kurz ?? "").font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.zweit).padding(.top, 10)
                }
            } else if let seit = pausiert, let z = p.pause {
                Self.ablaufKarte("PAUSIERT · " + L.uhr(seit.timeIntervalSince1970 * 1000), z) {
                    Text(p.pause_satz ?? "").font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 16)
                    HStack(spacing: 6) {
                        Button("Weiter ↩") { withAnimation(Kurve.sn(0.3)) { imBuendel = true } }.buttonStyle(SnTafelKnopf(groesse: 12)).keyboardShortcut(.return, modifiers: [])
                        Button("Rest auf morgen") { pausiert = nil }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 12))
                    }
                }
            } else if p.fertig == 0, let z = p.start {
                Self.ablaufKarte([stand.entscheiden?.fenster.map { L.uhr($0) }, "ENTSCHEIDUNGSFENSTER"].compactMap { $0 }.joined(separator: " · "), z) {
                    Text([p.zaehlung, p.arten].compactMap { $0 }.joined(separator: "\n")).font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.zweit)
                    Spacer(minLength: 16)
                    HStack(spacing: 6) {
                        Button("Anfangen ↩") { withAnimation(Kurve.sn(0.3)) { imBuendel = true } }.buttonStyle(SnTafelKnopf(groesse: 12)).keyboardShortcut(.return, modifiers: [])
                        Button("Nach dem Angebot") { pausiert = nil }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 12)).disabled(fragen.isEmpty)
                    }
                }
            } else {
                laufend(b, p)
            }
        }
    }

    var kartenBild: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(fragen) { f in karte(f) }
            ForEach(stand.vorbei ?? []) { v in vorbei(v) }
        }
        .frame(width: 880)
    }

    var buendelBild: some View { buendel.frame(width: 424, height: 250, alignment: .topLeading) }

    static func ablaufKarte<Inhalt: View>(_ kicker: String, _ satz: [String], @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker.uppercased()).font(Schrift.mono(10, .medium)).tracking(1.1).foregroundStyle(TafelFarbe.leise).padding(.bottom, 8)
            (Text((satz.first ?? "") + " ").foregroundColor(.white) + Text(satz.dropFirst().joined(separator: " ")).font(Schrift.serif(22, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                .font(Schrift.serif(22)).lineHeight(.exact(points: 24.2)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            inhalt()
        }
        .padding(18).frame(width: 424, height: 250, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func laufend(_ b: SenecaStand.Buendel, _ p: SenecaStand.Fortschritt) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BÜNDEL · " + (p.titel ?? "").uppercased()).font(Schrift.mono(12, .medium)).tracking(1.4).foregroundStyle(TafelFarbe.zweit)
                    Spacer()
                    Text("\(p.fertig) von \(p.gesamt) · noch etwa \(Int(p.rest_min ?? 0)) Min").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.bottom, 6)
                if !(p.passt ?? []).isEmpty || !(p.zurueck ?? []).isEmpty {
                    HStack(spacing: 22) {
                        if let ok = p.passt, !ok.isEmpty { Text("✓").foregroundColor(TafelFarbe.gruen) + Text(" " + ok.joined(separator: ", ")) }
                        if let z = p.zurueck, !z.isEmpty { Text("↺ " + z.joined(separator: ", ")) }
                    }
                    .font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.leise).padding(.top, 4).padding(.bottom, 6)
                }
                if let a = b.abnahmen?.first { abnahme(a) }
                if let d = p.danach {
                    HStack(spacing: 10) {
                        Text(d).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise)
                        Text("↩ passt · N nachbessern · → überspringen").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.aus)
                    }
                    .padding(.leading, 32).padding(.top, 10)
                }
            }
    }

    private func abnahme(_ a: SenecaStand.Abnahme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(.white).frame(width: 8, height: 8).frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(a.titel).font(Schrift.grotesk(15)).hoehe(21).foregroundStyle(.white)
                if let s = a.satz { Text(s).font(Schrift.grotesk(13)).hoehe(19).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true) }
                if nachbessern == a.id {
                    HStack(spacing: 10) {
                        TextField("Was soll anders werden?", text: $notiz).textFieldStyle(.plain).font(Schrift.grotesk(14))
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Color.white.opacity(0.08))).frame(maxWidth: 420)
                            .onSubmit { bessern(a) }
                        Button("Senden") { bessern(a) }.buttonStyle(SnTafelKnopf(groesse: 14)).disabled(notiz.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Abbrechen") { nachbessern = nil }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 14)).keyboardShortcut(.cancelAction)
                    }
                    .padding(.top, 12)
                } else {
                    HStack(spacing: 10) {
                        Button("Passt") { handle("abnahme.passt", a.id, nil) }.buttonStyle(SnTafelKnopf(groesse: 14)).keyboardShortcut(.return, modifiers: [])
                        Button("Nachbessern") { notiz = ""; nachbessern = a.id }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 14)).keyboardShortcut("n", modifiers: [])
                        if let s = a.hoerprobe_s {
                            Button("▶ anhören, \(Int(s)) s") { withAnimation(Kurve.sn(0.3)) { imBuendel = true } }.buttonStyle(.plain)
                                .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel).padding(.leading, 6)
                        }
                    }
                    .padding(.top, 12)
                    .background { Button("") { handle("abnahme.ueberspringen", a.id, nil) }.keyboardShortcut(.rightArrow, modifiers: []).opacity(0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .padding(.horizontal, -16).padding(.vertical, 4)
    }

    private func bessern(_ a: SenecaStand.Abnahme) {
        let t = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        handle("abnahme.nachbessern", a.id, t)
        nachbessern = nil
    }

    private var seite: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let h = stand.entscheiden?.heute, !h.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    kopf("HEUTE SCHON ENTSCHIEDEN")
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(Array(h.enumerated()), id: \.offset) { _, e in
                            GridRow {
                                Text(e.zeit.map { L.uhr($0) } ?? "").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).frame(width: 52, alignment: .leading).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(e.titel).font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.text)
                                    if let u = e.unter { Text(u).font(Schrift.grotesk(13)).hoehe(20).foregroundStyle(TafelFarbe.leise) }
                                }
                            }
                        }
                    }
                }
            }
            if let d = stand.entscheiden?.danach {
                VStack(alignment: .leading, spacing: 0) {
                    kopf("DANACH")
                    Text(d).font(Schrift.grotesk(14)).hoehe(21).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func kopf(_ t: String) -> some View {
        Text(t).font(Schrift.mono(12)).tracking(1.4).foregroundStyle(TafelFarbe.zweit).padding(.bottom, 10)
    }
}

struct SnEntscheidenEcht: View {
    @ObservedObject var store: SenecaStore

    var body: some View {
        if let s = store.stand {
            SnEntscheidenTafel(stand: s, antworte: { store.antworte(frage: $0, wahl: $1) }, handle: { store.handle($0, ziel: $1, text: $2) })
        } else {
            SnHeuteSkelett()
        }
    }
}
