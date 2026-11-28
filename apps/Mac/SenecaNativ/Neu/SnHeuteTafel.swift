import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
    func rein(_ an: Bool, _ verzug: Double) -> some View {
        opacity(an ? 1 : 0).offset(y: an ? 0 : 14).animation(Kurve.sn(0.9).delay(verzug), value: an)
    }
}

enum SnHeuteMass {
    static var kalender: CGRect = .zero
    static var notiert: [String] = []
}

struct SnHeuteTafel: View {
    var stand: SenecaStand
    var wartend: Set<String>
    var erledige: (String) -> Void
    var notiere: (String) -> Void = { _ in }
    var antworte: (String, String) -> Void = { _, _ in }
    var handle: (String, String, String?) -> Void = { _, _, _ in }
    var zumChat: (SenecaStand.Frage) -> Void = { _ in }
    var zumMeeting: (SenecaStand.Termin) -> Void = { _ in }
    var neu: Set<String> = []
    var laeuft = true

    @State private var da = false
    @State private var beantwortet: [String: (wahl: String, um: Date)] = [:]
    @State private var alleTodos = false
    @State private var gewaehlt: [String: String] = [:]
    @State private var notiz = ""
    @State private var notiert: [String] = []
    @FocusState private var notizFokus: Bool
    @Environment(\.accessibilityReduceMotion) private var ruhig

    private typealias L = HeuteTafelLogik
    private typealias K = SnTageskalender
    static func kennung(_ m: SenecaStand.Mitglied) -> String { "team:\(m.name):\(m.satz ?? m.zuletzt?.satz ?? m.zustand)" }
    private let linie = Color.white.opacity(0.07)
    private var an: Bool { da || !laeuft || ruhig }

    var body: some View {
        TimelineView(.everyMinute) { t in
            let jetzt = laeuft ? max(stand.jetzt, t.date.timeIntervalSince1970 * 1000) : stand.jetzt
            GeometryReader { g in
                let abstand: CGFloat = g.size.width < 1308 ? 48 : 80
                let breite = min(820, g.size.width - 48 - abstand - K.breite)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: abstand) {
                        haupt(jetzt).frame(width: breite, alignment: .topLeading)
                        kalender(jetzt, hoehe: max(420, g.size.height - 104 - 150)).rein(an, 0.3)
                    }
                    .padding(.leading, max(24, (g.size.width - breite - abstand - K.breite) / 2))
                    .padding(.top, 104).padding(.bottom, 170)
                    .frame(width: g.size.width, alignment: .topLeading)
                }
                .scrollClipDisabled()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - 150 / max(g.size.height, 300)), .init(color: .clear, location: 1 - 84 / max(g.size.height, 300))], startPoint: .top, endPoint: .bottom))
            }
        }
        .foregroundStyle(TafelFarbe.text)
        .onAppear { da = true }
    }

    private func haupt(_ jetzt: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(L.datumZeile(jetzt)) · \(L.uhr(jetzt))").font(Schrift.mono(13)).tracking(0.4).foregroundStyle(TafelFarbe.zweit).rein(an, 0.05)
            lage(jetzt).padding(.top, 18).rein(an, 0.12)
            if let f = frage { frageKarte(f).padding(.top, 30).rein(an, 0.22) }
            todos(jetzt).padding(.top, 34).rein(an, 0.36)
        }
    }

    private func lage(_ jetzt: Double) -> some View {
        let termine = K.heute(stand, jetzt).filter { $0.ende > jetzt && $0.art != "fokus" }
        let marken: [(Int, String, Color)] = [
            (offeneFragen.filter { $0.antwort == nil }.count, "FRAGEN", TafelFarbe.bernstein),
            (offeneTodos.count, "TO-DOS", TafelFarbe.himmel),
            (termine.count, "TERMINE", TafelFarbe.text),
            (termine.filter(K.istMeeting).count, "MEETINGS", TafelFarbe.koralle),
            ((stand.team ?? []).filter { $0.zustand == "arbeitet" }.count, "ARBEITEN", TafelFarbe.gruen),
        ]
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(marken.enumerated()), id: \.offset) { i, m in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(m.0)").font(Schrift.serif(46)).tracking(-0.5).hoehe(46).foregroundStyle(m.0 == 0 ? TafelFarbe.aus : m.2)
                    Text(m.1).font(Schrift.mono(11)).tracking(1.3).foregroundStyle(m.0 == 0 ? TafelFarbe.aus : TafelFarbe.leise)
                }
                .padding(.trailing, 30).padding(.leading, i == 0 ? 0 : 30)
                .overlay(alignment: .leading) { if i > 0 { linie.frame(width: 1).padding(.vertical, 4) } }
            }
        }
    }

    private func kopf(_ titel: String, _ rechts: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titel).font(Schrift.mono(12, .medium)).tracking(1.4).foregroundStyle(TafelFarbe.zweit)
            Spacer(minLength: 8)
            Text(rechts).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { linie.frame(height: 1) }
    }

    private var offeneFragen: [SenecaStand.Frage] { (stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? []) }

    private var frage: SenecaStand.Frage? {
        if let id = beantwortet.keys.first, let f = (offeneFragen + (stand.eben_beantwortet ?? [])).first(where: { $0.id == id }) { return f }
        return offeneFragen.first { $0.antwort == nil }
    }

    private func frageKarte(_ f: SenecaStand.Frage) -> some View {
        let form = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let wer = Self.wer(f, (stand.team ?? []).map(\.name))
        let n = offeneFragen.filter { $0.antwort == nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
                Text("\((f.von ?? "Seneca").uppercased()) FRAGT" + (n > 1 ? " · 1 VON \(n)" : "")).font(Schrift.mono(12)).tracking(1.4).foregroundStyle(TafelFarbe.bernstein)
                Spacer(minLength: 12)
                Text(herkunft(f)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
            }
            let gross = f.text.count <= 80
            Text(f.text).font(Schrift.serif(gross ? 38 : f.text.count <= 130 ? 30 : 25)).tracking(-0.4).hoehe(gross ? 41 : f.text.count <= 130 ? 34 : 29).foregroundStyle(.white)
                .lineLimit(5).padding(.top, 8).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
            if let a = absatz(f) {
                a.font(Schrift.grotesk(15)).hoehe(22).foregroundStyle(TafelFarbe.zweit).frame(maxWidth: 720, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if !wer.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(wer.enumerated()), id: \.offset) { _, w in
                        HStack(spacing: 6) {
                            Text(w.0).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                            Text("\(w.1)").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.text)
                        }
                        .padding(.horizontal, 14).frame(height: 28).background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.top, 14)
            }
            Group {
                if let b = beantwortet[f.id] { quittung(f, b.wahl, seit: b.um) } else { knoepfe(f) }
            }
            .padding(.top, 20)
        }
        .padding(.top, 24).padding(.bottom, 24).padding(.leading, 34).padding(.trailing, 30)
        .background {
            form.fill(Color(hex: 0x020816)).padding(30).offset(y: 30).shadow(color: Color(hex: 0x020816, deckkraft: 0.8), radius: 30)
                .mask { ZStack { Rectangle().padding(-120); form.blendMode(.destinationOut) }.compositingGroup() }
            form.fill(LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(form.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient(colors: [TafelFarbe.bernstein, TafelFarbe.bernstein.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3).padding(.vertical, 24)
        }
        .modifier(SnNeuHell(an: neu.contains(f.id)))
    }

    private func herkunft(_ f: SenecaStand.Frage) -> String {
        let cal = Calendar.current
        let seit = f.seit.map { cal.isDate(L.datum($0), inSameDayAs: L.datum(stand.jetzt)) ? "seit \(L.uhr($0))" : "seit gestern" }
        let fenster = stand.buendel?.fragen?.contains { $0.id == f.id } == true ? stand.buendel?.fenster.map { "sonst um \(L.uhr($0))" } : nil
        return [seit, f.frist.map { L.frist($0, jetzt: stand.jetzt) } ?? fenster].compactMap { $0 }.joined(separator: " · ")
    }

    private func absatz(_ f: SenecaStand.Frage) -> Text? {
        let worum = (f.kontext?.worum ?? "").split(separator: "\n").first.map { z in z.range(of: ". ").map { String(z[..<$0.lowerBound]) + "." } ?? String(z) }
        let rat = f.empfehlung.map { e in f.optionen?.first { $0.wert == e }?.text ?? e }.map { r in r.first?.isUppercase == true && r.dropFirst().first?.isLowercase == true ? r.prefix(1).lowercased() + r.dropFirst() : r }
        guard worum != nil || rat != nil else { return nil }
        let vorn = Text(worum.map { $0 + (rat == nil ? "" : " ") } ?? "")
        guard let rat else { return vorn }
        return vorn + Text("\(f.von ?? "Seneca") rät:").font(Schrift.grotesk(15, .medium)).foregroundColor(TafelFarbe.text) + Text(" " + rat)
    }

    static func wer(_ f: SenecaStand.Frage, _ namen: [String]) -> [(String, Int)] {
        let liste: [(String, Int)] = (f.kontext?.worum ?? "").split(separator: "\n").dropFirst().compactMap { z in
            guard let i = z.firstIndex(of: ":"), namen.contains(String(z[..<i])) else { return nil }
            return (String(z[..<i]), z[z.index(after: i)...].components(separatedBy: " · ").count)
        }
        guard liste.count > 3 else { return liste }
        let rest = liste.dropFirst(2)
        return Array(liste.prefix(2)) + [("\(rest.count) weitere", rest.map(\.1).reduce(0, +))]
    }

    static func langesEtikett(_ s: String) -> Bool { s.count > 28 || s.split(separator: " ").count > 3 }

    private func knoepfe(_ f: SenecaStand.Frage) -> some View {
        let optionen = (f.optionen ?? []).filter { $0.wert != nil }
        let auswahl = optionen.filter { $0.wert != "spaeter" }
        let lang = auswahl.contains { Self.langesEtikett($0.knopf ?? $0.text ?? "") }
        let wahl = gewaehlt[f.id] ?? auswahl.first { $0.wert == f.empfehlung }?.wert ?? auswahl.first?.wert ?? ""
        let chat = Button("Einzeln im Chat →") { zumChat(f) }.buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.himmel).fixedSize()
        let spaeterKnopf = Button("Später") { senden(f, "spaeter") }.buttonStyle(SnHeuteKnopf(art: .leise))
        return VStack(alignment: .leading, spacing: 14) {
            if lang {
                VStack(spacing: 8) { ForEach(Array(auswahl.enumerated()), id: \.offset) { _, o in zeile(o, gewaehlt: o.wert == wahl) { gewaehlt[f.id] = o.wert } } }
                HStack(spacing: 10) {
                    Button("Wählen") { senden(f, wahl) }.buttonStyle(SnHeuteKnopf(art: .haupt))
                    spaeterKnopf
                    Spacer(minLength: 12)
                    chat
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(auswahl.enumerated()), id: \.offset) { i, o in Button(o.knopf ?? o.text ?? "") { senden(f, o.wert ?? "") }.buttonStyle(SnHeuteKnopf(art: i == 0 ? .haupt : .neben)) }
                        spaeterKnopf
                        Spacer(minLength: 12)
                        chat
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(auswahl.enumerated()), id: \.offset) { i, o in Button(o.knopf ?? o.text ?? "") { senden(f, o.wert ?? "") }.buttonStyle(SnHeuteKnopf(art: i == 0 ? .haupt : .neben)) }
                        HStack(spacing: 10) { spaeterKnopf; chat }
                    }
                }
            }
        }
    }

    private func zeile(_ o: SenecaStand.Option, gewaehlt: Bool, tippe: @escaping () -> Void) -> some View {
        Button(action: tippe) {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(gewaehlt ? TafelFarbe.himmel : Color.white.opacity(0.3), lineWidth: 1.5).frame(width: 18, height: 18)
                    .overlay { if gewaehlt { Circle().fill(TafelFarbe.himmel).padding(4) } }.padding(.top, 2)
                Text(o.knopf ?? o.text ?? "").font(Schrift.grotesk(15)).hoehe(21).foregroundStyle(gewaehlt ? .white : TafelFarbe.zweit)
                    .lineLimit(3).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(gewaehlt ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(gewaehlt ? TafelFarbe.himmel.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func senden(_ f: SenecaStand.Frage, _ wahl: String) {
        if wahl != "spaeter" { antworte(f.id, wahl) }
        withAnimation(Kurve.sn(0.3)) { beantwortet[f.id] = (wahl, Date()) }
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(frist))
            guard beantwortet[f.id] != nil else { return }
            if wahl == "spaeter" { antworte(f.id, wahl) }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Kurve.sn(0.5)) { beantwortet[f.id] = nil }
        }
    }

    private func quittung(_ f: SenecaStand.Frage, _ wahl: String, seit: Date) -> some View {
        let o = f.optionen?.first { $0.wert == wahl }
        let frist = stand.regeln?["rueckgaengig_s"] ?? 5
        let text = wahl == "spaeter" ? "Kommt um \(L.uhr(f.spaeter_bis ?? stand.buendel?.fenster ?? stand.jetzt)) wieder" : o?.quittung ?? o?.text ?? wahl
        return TimelineView(.periodic(from: seit, by: 0.1)) { t in
            let rest = max(0, frist - t.date.timeIntervalSince(seit))
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                    Text(text).font(Schrift.grotesk(16, .medium)).foregroundStyle(.white).lineLimit(2)
                    Spacer()
                    if rest > 0 {
                        Button("Rückgängig") {
                            if wahl != "spaeter" { handle("rueckgaengig", f.id, nil) }
                            withAnimation(Kurve.sn(0.3)) { beantwortet[f.id] = nil }
                        }
                        .buttonStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.himmel)
                    }
                }
                .frame(height: 31)
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.zweit).frame(width: g.size.width * rest / frist) }
                }
                .frame(height: 3).opacity(rest > 0 ? 1 : 0)
            }
        }
    }

    private var offeneTodos: [SenecaStand.Todo] {
        let liste = L.todosHeute(stand)
        return liste.filter { $0.wichtig == true } + liste.filter { $0.wichtig != true }
    }

    private func todos(_ jetzt: Double) -> some View {
        let liste = offeneTodos
        let eigene = notiert.filter { n in !liste.contains { $0.titel == n } }
        let zeigen = alleTodos || liste.count <= 6 ? liste : Array(liste.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            kopf("TO-DOS", liste.isEmpty ? "" : "\(liste.count)")
            notizFeld
            ForEach(eigene, id: \.self) { n in zeile(n, unter: "wird übertragen", kreis: TafelFarbe.gruen, gestrichelt: true) }
            ForEach(zeigen) { t in todoZeile(t) }
            if liste.count > zeigen.count {
                Button { withAnimation(Kurve.sn(0.4)) { alleTodos = true } } label: {
                    HStack {
                        Text("\(liste.count - zeigen.count) weitere").foregroundStyle(TafelFarbe.leise)
                        Spacer()
                        Text("alle zeigen").foregroundStyle(TafelFarbe.himmel)
                    }
                    .font(Schrift.grotesk(14)).padding(.top, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notizFeld: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(TafelFarbe.leise).frame(width: 18, height: 18).frame(width: 22, alignment: .leading)
            TextField("", text: $notiz, prompt: Text("Für mich notieren …").foregroundColor(TafelFarbe.leise))
                .textFieldStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(.white).focused($notizFokus)
                .onSubmit {
                    let t = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    notiere(t)
                    notiert.append(t)
                    notiz = ""
                    notizFokus = true
                }
            if notizFokus && !notiz.isEmpty { Text("⏎").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise) }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { linie.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { notizFokus = true }
    }

    private func todoZeile(_ t: SenecaStand.Todo) -> some View {
        let w = wartend.contains(t.id)
        let frist = t.bis_wann.map { L.ueberfaellig(t, stand) ? L.fristWar($0, stand) : L.frist($0, jetzt: stand.jetzt) }
        let unter = w ? "wird übertragen" : ([TafelFarbe.bereichWort(t.bereich), frist] as [String?]).compactMap { $0 }.joined(separator: " · ")
        return Button { if !w { erledige(t.id) } } label: {
            zeile(t.titel, unter: unter, kreis: w ? TafelFarbe.gruen : TafelFarbe.bereich(t.bereich).opacity(0.75), gestrichelt: w, durch: w, wichtig: t.wichtig == true)
        }
        .buttonStyle(.plain)
    }

    private func zeile(_ titel: String, unter: String, kreis: Color, gestrichelt: Bool, durch: Bool = false, wichtig: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().strokeBorder(kreis, style: StrokeStyle(lineWidth: 1.5, dash: gestrichelt ? [3, 2.4] : []))
                .frame(width: 18, height: 18).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(titel).font(Schrift.grotesk(15)).hoehe(21).strikethrough(durch).foregroundStyle(durch ? TafelFarbe.aus : TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                    if wichtig { Text("WICHTIG").font(Schrift.mono(10)).tracking(1.2).foregroundStyle(TafelFarbe.bernstein) }
                }
                if !unter.isEmpty { Text(unter).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { linie.frame(height: 1) }
        .contentShape(Rectangle())
    }

    private func kalender(_ jetzt: Double, hoehe: CGFloat) -> some View {
        let p = K.plan(stand, jetzt: jetzt, hoehe: hoehe - 40)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("DEIN TAG").font(Schrift.mono(12, .medium)).tracking(1.4).foregroundStyle(TafelFarbe.zweit)
                Spacer()
                if !p.ganztag.isEmpty { Text(p.ganztag.joined(separator: " · ")).font(Schrift.grotesk(12.5)).foregroundStyle(TafelFarbe.leise).lineLimit(1) }
            }
            .frame(height: 40, alignment: .top)
            ZStack(alignment: .topLeading) {
                ForEach(p.stunden, id: \.self) { h in
                    let y = p.y(Double(h))
                    Rectangle().fill(linie).frame(height: 1).offset(x: 40, y: y).frame(width: K.breite - 40)
                    if h % 2 == 0 && (p.jetztY.map { abs($0 - y) > 12 } ?? true) {
                        Text(String(format: "%02d", h)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).offset(y: y - 7)
                    }
                }
                ForEach(p.bloecke) { b in block(b, jetzt) }
                if let y = p.jetztY {
                    Text(L.uhr(jetzt)).font(Schrift.mono(11, .medium)).foregroundStyle(TafelFarbe.jetzt).offset(y: y - 7)
                    Rectangle().fill(TafelFarbe.jetzt).frame(width: K.breite - 40, height: 1.5).offset(x: 40, y: y - 0.75)
                    Circle().fill(TafelFarbe.jetzt).frame(width: 7, height: 7).offset(x: 37, y: y - 3.5)
                }
            }
            .frame(width: K.breite, height: hoehe - 40, alignment: .topLeading)
        }
        .frame(width: K.breite, height: hoehe, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { SnHeuteMass.kalender = $0 }
    }

    @ViewBuilder private func block(_ b: SnTageskalender.Block, _ jetzt: Double) -> some View {
        let t = b.termin
        let vorbei = t.ende <= jetzt
        let farbe = t.art == "fokus" ? TafelFarbe.zweit : TafelFarbe.bereich(t.bereich)
        let meeting = K.istMeeting(t)
        let form = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let inhalt = HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(t.titel).font(Schrift.grotesk(13, .medium)).foregroundStyle(vorbei ? TafelFarbe.leise : .white).lineLimit(b.hoehe >= 44 ? 2 : 1)
                if b.hoehe >= 34 {
                    Text("\(L.uhr(t.start)) · \(K.dauer(t.ende - t.start))").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if b.hoehe < 34 { Text(L.uhr(t.start)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise) }
            if meeting {
                Text("MEETING").font(Schrift.mono(9.5)).tracking(1.1).foregroundStyle(TafelFarbe.koralle)
                    .padding(.horizontal, 6).frame(height: 16).overlay(Capsule().strokeBorder(TafelFarbe.koralle.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.top, b.hoehe >= 34 ? 5 : 2)
        .frame(width: b.breite, height: b.hoehe, alignment: .topLeading)
        .background(form.fill(farbe.opacity(vorbei ? 0.06 : t.art == "fokus" ? 0.08 : 0.16)))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1.5).fill(farbe.opacity(vorbei ? 0.4 : 1)).frame(width: 3).padding(.vertical, 2) }
        .clipShape(form)
        .offset(x: b.x, y: b.y)
        if meeting {
            Button { zumMeeting(t) } label: { inhalt.contentShape(form) }.buttonStyle(.plain)
        } else {
            inhalt
        }
    }

}

enum SnTageskalender {
    static let breite: CGFloat = 360
    private static let minute = 60_000.0
    struct Block: Identifiable { var termin: SenecaStand.Termin; var x: CGFloat; var y: CGFloat; var breite: CGFloat; var hoehe: CGFloat; var id: String { termin.uid } }
    struct Plan {
        var von: Double; var bis: Double; var proStunde: CGFloat; var bloecke: [Block]; var ganztag: [String]; var jetztY: CGFloat?
        var stunden: [Int] { Array(Int(von)...Int(bis)) }
        func y(_ h: Double) -> CGFloat { CGFloat(h - von) * proStunde }
    }

    static func heute(_ s: SenecaStand, _ jetzt: Double) -> [SenecaStand.Termin] {
        (s.termine ?? []).filter { $0.ganztag != true && Calendar.current.isDate(HeuteTafelLogik.datum($0.start), inSameDayAs: HeuteTafelLogik.datum(jetzt)) }.sorted { $0.start < $1.start }
    }

    static func istMeeting(_ t: SenecaStand.Termin) -> Bool { t.meeting != nil }

    static func stunde(_ ms: Double) -> Double {
        let k = Calendar.current.dateComponents([.hour, .minute], from: HeuteTafelLogik.datum(ms))
        return Double(k.hour ?? 0) + Double(k.minute ?? 0) / 60
    }

    static func dauer(_ ms: Double) -> String {
        let min = Int((ms / minute).rounded())
        if min < 60 { return "\(min) Min" }
        return min % 60 == 0 ? "\(min / 60) Std" : String(format: "%d:%02d Std", min / 60, min % 60)
    }

    static func plan(_ s: SenecaStand, jetzt: Double, hoehe: CGFloat) -> Plan {
        let liste = heute(s, jetzt)
        let von = min(7, (liste.map { stunde($0.start) }.min() ?? 7).rounded(.down))
        let bis = max(21, min(24, (liste.map { stunde($0.ende) + ($0.ende - $0.start > 20 * 3_600_000 ? 24 : 0) }.max() ?? 21).rounded(.up)))
        let pro = hoehe / CGFloat(bis - von)
        var spuren: [Double] = [], gruppe: [(SenecaStand.Termin, Int)] = [], bloecke: [Block] = []
        func schliesse() {
            let n = CGFloat(max(1, spuren.count)), w = (breite - 44) / n
            bloecke += gruppe.map { t, i in
                let a = stunde(t.start), e = max(a + 0.25, Calendar.current.isDate(HeuteTafelLogik.datum(t.ende), inSameDayAs: HeuteTafelLogik.datum(t.start)) ? stunde(t.ende) : 24)
                return Block(termin: t, x: 44 + CGFloat(i) * w, y: CGFloat(a - von) * pro + 1, breite: w - 3, hoehe: max(18, CGFloat(e - a) * pro - 2))
            }
            spuren = []; gruppe = []
        }
        for t in liste {
            if !spuren.isEmpty && spuren.allSatisfy({ $0 <= t.start }) { schliesse() }
            let i = spuren.firstIndex { $0 <= t.start } ?? spuren.count
            if i == spuren.count { spuren.append(t.ende) } else { spuren[i] = t.ende }
            gruppe.append((t, i))
        }
        schliesse()
        let h = stunde(jetzt)
        let ganztag = (s.termine ?? []).filter { $0.ganztag == true && Calendar.current.isDate(HeuteTafelLogik.datum($0.start), inSameDayAs: HeuteTafelLogik.datum(jetzt)) }.map(\.titel)
        return Plan(von: von, bis: bis, proStunde: pro, bloecke: bloecke, ganztag: ganztag, jetztY: h >= von && h <= bis ? CGFloat(h - von) * pro : nil)
    }
}

struct SnHeuteKnopf: ButtonStyle {
    enum Art { case haupt, neben, leise }
    var art: Art
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
                .fixedSize()
                .font(Schrift.grotesk(15, .medium))
                .foregroundStyle(art == .haupt ? TafelFarbe.aufHimmel : art == .neben ? TafelFarbe.text : TafelFarbe.zweit)
                .padding(.horizontal, art == .leise ? 12 : 20).frame(height: 44)
                .background {
                    if art == .haupt {
                        Capsule().fill(TafelFarbe.himmel.opacity(hover ? 0.9 : 1))
                    } else if art == .neben {
                        Capsule().fill(Color.white.opacity(hover ? 0.12 : 0.08)).overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    } else {
                        Capsule().fill(Color.white.opacity(hover ? 0.05 : 0))
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
        .animation(Kurve.snFeder, value: configuration.isPressed)
        .animation(Kurve.sn(0.2), value: hover)
        .onHover { hover = $0 }
    }
}

struct SnHeuteSkelett: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach([0.4, 0.8, 0.6, 0.9, 0.7], id: \.self) { a in
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)).frame(width: 860 * a, height: 14).frame(width: 860, alignment: .leading)
            }
            Text("Seneca holt deinen Tag. Nur beim ersten Mal.").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise).padding(.top, 30)
        }
        .padding(.top, 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct SnNeuHell: ViewModifier {
    var an: Bool
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(an ? 0.08 : 0)).padding(.horizontal, -10))
            .animation(Kurve.sn(0.6), value: an)
    }
}
