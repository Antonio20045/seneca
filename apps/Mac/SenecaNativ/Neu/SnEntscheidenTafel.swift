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
    @State private var mehr: Set<String> = []
    @State private var beantwortet: [String: (wahl: String, um: Date)] = [:]
    @State private var nachbessern: String?
    @State private var notiz = ""

    private typealias L = HeuteTafelLogik

    private var fragen: [SenecaStand.Frage] {
        ((stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? [])).filter { $0.antwort == nil || beantwortet[$0.id] != nil }
    }

    var body: some View {
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
            if mehr.contains(f.id) {
                Text([f.kontext?.worum, f.kontext?.wenn_nicht.map { "Wenn nichts passiert: \($0)" }].compactMap { $0 }.joined(separator: "\n"))
                    .font(Schrift.grotesk(14)).hoehe(21).foregroundStyle(TafelFarbe.zweit).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if optionen.contains(where: { $0.titel != nil }) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(optionen, id: \.wert) { o in fassung(o, an: o.wert == gewaehlt, empfohlen: o.wert == f.empfehlung) { wahl[f.id] = o.wert } }
                }
                .padding(.top, 16)
            }
            if let b = beantwortet[f.id] {
                quittung(f, b.wahl, seit: b.um).padding(.top, 18)
            } else {
                HStack(spacing: 10) {
                    if optionen.contains(where: { $0.titel != nil }) || optionen.count == 1 {
                        Button(option?.knopf ?? option?.text ?? "Ja") { senden(f, gewaehlt) }.buttonStyle(SnTafelKnopf())
                    } else {
                        ForEach(Array(optionen.enumerated()), id: \.element.wert) { i, o in
                            Button(o.knopf ?? o.text ?? "") { senden(f, o.wert) }.buttonStyle(SnTafelKnopf(art: i == 0 ? .voll : .rand))
                        }
                    }
                    Button("Später") { antworte(f.id, "spaeter") }.buttonStyle(SnTafelKnopf(art: .rand))
                    Button("Mehr") { withAnimation(Kurve.sn(0.3)) { if mehr.contains(f.id) { mehr.remove(f.id) } else { mehr.insert(f.id) } } }
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
        return HStack(spacing: 14) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
            Text(o?.titel?.components(separatedBy: " · ").first ?? o?.text ?? w).font(Schrift.grotesk(15, .medium)).foregroundStyle(.white)
            TimelineView(.periodic(from: seit, by: 0.1)) { t in
                let rest = max(0, frist - t.date.timeIntervalSince(seit))
                if rest > 0 {
                    Button("Rückgängig") { handle("rueckgaengig", f.id, nil); beantwortet[f.id] = nil }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 14))
                    Capsule().fill(TafelFarbe.himmel.opacity(0.5)).frame(width: 60 * rest / frist, height: 3).frame(width: 60, alignment: .leading)
                }
            }
            Spacer()
        }
    }

    private func senden(_ f: SenecaStand.Frage, _ w: String?) {
        guard let w else { return }
        antworte(f.id, w)
        beantwortet[f.id] = (w, Date())
    }

    @ViewBuilder private var buendel: some View {
        if let b = stand.buendel, let p = b.fortschritt, p.gesamt > 0 {
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
                        if let s = a.hoerprobe_s, let beleg = a.beleg.flatMap(URL.init(string:)) {
                            Button("▶ anhören, \(Int(s)) s") { NSWorkspace.shared.open(beleg) }.buttonStyle(.plain)
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
