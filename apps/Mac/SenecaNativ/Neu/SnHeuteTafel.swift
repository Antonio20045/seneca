import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
    func rein(_ an: Bool, _ verzug: Double) -> some View {
        opacity(an ? 1 : 0).offset(y: an ? 0 : 14).animation(Kurve.sn(0.9).delay(verzug), value: an)
    }
}

struct SnHeuteTafel: View {
    var stand: SenecaStand
    var wartend: Set<String>
    var erledige: (String) -> Void
    var antworte: (String, String) -> Void = { _, _ in }
    var handle: (String, String, String?) -> Void = { _, _, _ in }
    var zumChat: (SenecaStand.Frage) -> Void = { _ in }
    var zurArbeit: () -> Void
    var neu: Set<String> = []
    var laeuft = true

    @State private var da = false
    @State private var beantwortet: [String: (wahl: String, um: Date)] = [:]
    @State private var alleTodos = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    private typealias L = HeuteTafelLogik
    private typealias S = SnTagesschiene
    static func kennung(_ m: SenecaStand.Mitglied) -> String { "team:\(m.name):\(m.satz ?? m.zuletzt?.satz ?? m.zustand)" }
    private let linie = Color.white.opacity(0.07)
    private var an: Bool { da || !laeuft || ruhig }
    private var bewegt: Bool { laeuft && !ruhig }

    var body: some View {
        TimelineView(.everyMinute) { t in
            let jetzt = laeuft ? max(stand.jetzt, t.date.timeIntervalSince1970 * 1000) : stand.jetzt
            GeometryReader { g in
                let abstand: CGFloat = g.size.width < 1308 ? 48 : 80
                let breite = min(860, g.size.width - 48 - abstand - 320)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: abstand) {
                        haupt(jetzt).frame(width: breite, alignment: .topLeading)
                        seite(jetzt).frame(width: 320, alignment: .topLeading).rein(an, 1.0)
                    }
                    .padding(.leading, max(24, (g.size.width - breite - abstand - 320) / 2 + 6))
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
            VStack(alignment: .leading, spacing: 0) {
                datumZeile(jetzt).padding(.bottom, 14)
                if let satz = L.satz(stand) {
                    (Text(satz.vor + " ").font(Schrift.serif(44)).foregroundColor(.white) + Text(satz.akzent).font(Schrift.serif(44, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                        .tracking(-0.5).hoehe(46.6).fixedSize(horizontal: false, vertical: true).offset(y: -4)
                }
            }
            .rein(an, 0.05)
            if let f = frage { frageKarte(f).padding(.top, 26).rein(an, 0.22) }
            mitte(jetzt)
            jedenTag
        }
    }

    private func datumZeile(_ jetzt: Double) -> some View {
        let termine = (stand.termine ?? []).filter { $0.ganztag != true && $0.art != "fokus" }.count
        let fokus = stand.ruhe.flatMap { r in r.grund == "fokus" ? r.bis : nil }
        let pille = fokus.map { "FOKUS · NOCH \(Int(max(0, $0 - jetzt) / 60_000)) MIN" } ?? (termine == 0 ? "KEINE TERMINE" : termine == 1 ? "1 TERMIN" : "\(termine) TERMINE")
        return HStack(spacing: 12) {
            Text("\(L.datumZeile(jetzt)) · \(L.uhr(jetzt))").font(Schrift.mono(13)).tracking(0.4).foregroundStyle(TafelFarbe.zweit)
            Text(pille).font(Schrift.mono(11)).tracking(1.2).foregroundStyle(TafelFarbe.akzent)
                .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(TafelFarbe.himmel.opacity(0.16)))
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
                SnPuls(farbe: TafelFarbe.bernstein, groesse: 8, weite: 12, takt: 2.2, deckkraft: 0.55, laeuft: bewegt)
                Text("\((f.von ?? "Seneca").uppercased()) FRAGT" + (n > 1 ? " · 1 VON \(n)" : "")).font(Schrift.mono(12)).tracking(1.4).foregroundStyle(TafelFarbe.bernstein)
                Spacer(minLength: 12)
                Text(herkunft(f)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
            }
            Text(f.text).font(Schrift.serif(38)).tracking(-0.4).hoehe(41).foregroundStyle(.white)
                .padding(.top, 8).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
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

    private func knoepfe(_ f: SenecaStand.Frage) -> some View {
        let optionen = (f.optionen ?? []).filter { $0.wert != nil }
        let spaeter = optionen.contains { $0.wert == "spaeter" }
        return HStack(spacing: 10) {
            ForEach(Array(optionen.enumerated()), id: \.offset) { i, o in
                Button(o.knopf ?? o.text ?? "") { senden(f, o.wert ?? "") }
                    .buttonStyle(SnHeuteKnopf(art: i == 0 ? .haupt : o.wert == "spaeter" ? .leise : .neben, glimmt: i == 0 && bewegt))
            }
            if !spaeter { Button("Später") { senden(f, "spaeter") }.buttonStyle(SnHeuteKnopf(art: .leise)) }
            Spacer(minLength: 12)
            Button("Einzeln im Chat →") { zumChat(f) }.buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.himmel).fixedSize()
        }
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
                    Text(text).font(Schrift.grotesk(16, .medium)).foregroundStyle(.white)
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
        L.todosHeute(stand).sorted { ($0.geplant_von ?? .infinity) < ($1.geplant_von ?? .infinity) }
    }

    private var getan: [SenecaStand.Mitglied] {
        let tag = stand.tag_beginn ?? 0
        let liste = (stand.team ?? []).filter { $0.zustand == "arbeitet" || $0.zustand == "hängt" || ($0.zuletzt?.um ?? 0) >= tag }
        return liste.filter { $0.zustand == "arbeitet" || $0.zustand == "hängt" } + liste.filter { $0.zustand != "arbeitet" && $0.zustand != "hängt" }
    }

    @ViewBuilder private func mitte(_ jetzt: Double) -> some View {
        let todos = offeneTodos, team = getan
        if !todos.isEmpty || !team.isEmpty {
            HStack(alignment: .top, spacing: 44) {
                if !todos.isEmpty { naechstes(todos, jetzt).frame(maxWidth: .infinity, alignment: .topLeading).rein(an, 0.42) }
                if !team.isEmpty { heuteGetan(team).frame(maxWidth: .infinity, alignment: .topLeading).rein(an, 0.62) }
            }
            .padding(.top, 26)
        }
    }

    private func naechstes(_ liste: [SenecaStand.Todo], _ jetzt: Double) -> some View {
        let zeigen = alleTodos || liste.count <= 3 ? liste : Array(liste.prefix(3))
        let bis = liste.compactMap(\.geplant_bis).max()
        return VStack(alignment: .leading, spacing: 0) {
            kopf("ALS NÄCHSTES · \(liste.count == 1 ? "1 TO-DO" : "\(liste.count) TO-DOS")", bis.map { "bis \(L.uhr($0))" } ?? "")
            ForEach(zeigen) { t in todoZeile(t, jetzt, erste: t.id == zeigen.first?.id) }
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

    private func todoZeile(_ t: SenecaStand.Todo, _ jetzt: Double, erste: Bool) -> some View {
        let w = wartend.contains(t.id)
        let anteil: Double? = t.geplant_von.flatMap { von in t.geplant_bis.flatMap { bis in von <= jetzt && jetzt < bis ? (jetzt - von) / (bis - von) : nil } }
        let frist = L.ueberfaellig(t, stand) ? t.bis_wann.map { L.fristWar($0, stand) } : nil
        let unter = w ? "wird übertragen" : ([t.bereich, frist ?? (t.geplant_von == nil ? nil : "von Seneca eingeplant")] as [String?]).compactMap { $0 }.joined(separator: " · ")
        return Button { if !w { erledige(t.id) } } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(t.geplant_von.map { L.uhr($0) } ?? "").font(Schrift.mono(12)).foregroundStyle(erste ? TafelFarbe.akzent : TafelFarbe.leise).padding(.top, 2).frame(width: 44, alignment: .leading)
                Circle().strokeBorder(w ? TafelFarbe.gruen : TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: w ? [3, 2.4] : []))
                    .frame(width: 18, height: 18).frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.titel).font(Schrift.grotesk(15)).hoehe(21).strikethrough(w).foregroundStyle(w ? TafelFarbe.aus : TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                    if !unter.isEmpty { Text(unter).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 2) }
                    if let anteil {
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.08)).overlay(alignment: .leading) {
                                Capsule().fill(TafelFarbe.himmel).frame(width: max(2, g.size.width * anteil)).shadow(color: TafelFarbe.himmel, radius: 4)
                            }
                        }
                        .frame(height: 2).padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { linie.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heuteGetan(_ liste: [SenecaStand.Mitglied]) -> some View {
        let alle = stand.team ?? []
        let fertig = liste.filter { $0.zustand != "arbeitet" && $0.zustand != "hängt" }.count
        return VStack(alignment: .leading, spacing: 0) {
            kopf("HEUTE GETAN", "\(fertig) von \(alle.count)")
            ForEach(liste.prefix(3), id: \.name) { m in
                let laeuftGerade = m.zustand == "arbeitet" || m.zustand == "hängt"
                Button(action: zurArbeit) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(m.name).font(Schrift.grotesk(15)).foregroundStyle(.white).frame(width: 86, alignment: .leading)
                        Text((laeuftGerade ? m.satz : m.zuletzt?.satz) ?? m.zustand).font(Schrift.grotesk(14)).hoehe(20).lineLimit(2).foregroundStyle(TafelFarbe.text)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Text(rechts(m)).font(Schrift.mono(12)).foregroundStyle(laeuftGerade ? TafelFarbe.gruen : TafelFarbe.leise).frame(minWidth: 40, alignment: .trailing).fixedSize()
                    }
                    .padding(.vertical, 11)
                    .modifier(SnNeuHell(an: neu.contains(Self.kennung(m))))
                    .overlay(alignment: .bottom) { linie.frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            buendel(alle).padding(.top, 12)
        }
    }

    private func rechts(_ m: SenecaStand.Mitglied) -> String {
        if m.zustand == "arbeitet" { return m.rest_min.map { "noch \(Int($0)) Min" } ?? m.seit.map { "seit \(L.uhr($0))" } ?? "" }
        if m.zustand == "hängt" { return "hängt" }
        return m.zuletzt?.um.map { L.uhr($0) } ?? ""
    }

    private func buendel(_ alle: [SenecaStand.Mitglied]) -> some View {
        let reihe = ["arbeitet", "hängt", "frei", "ruht"]
        let sortiert = alle.sorted { (reihe.firstIndex(of: $0.zustand) ?? 2) < (reihe.firstIndex(of: $1.zustand) ?? 2) }
        let teile: [String] = reihe.compactMap { z in
            let n = alle.filter { $0.zustand == z }.count
            guard n > 0 else { return nil }
            return "\(n) " + (z == "frei" ? "frei" : z == "arbeitet" ? (n == 1 ? "arbeitet" : "arbeiten") : z == "hängt" ? (n == 1 ? "hängt" : "hängen") : (n == 1 ? "ruht" : "ruhen"))
        }
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Array(sortiert.enumerated()), id: \.offset) { _, m in
                    if m.zustand == "arbeitet" {
                        SnPuls(farbe: TafelFarbe.gruen, groesse: 10, weite: 8, takt: 2.2, deckkraft: 0.5, laeuft: bewegt)
                    } else {
                        Circle().strokeBorder(m.zustand == "ruht" ? TafelFarbe.aus : m.zustand == "hängt" ? TafelFarbe.bernstein : TafelFarbe.himmel, lineWidth: 1.5).frame(width: 10, height: 10)
                    }
                }
            }
            Text(teile.joined(separator: " · ")).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise)
        }
    }

    @ViewBuilder private var jedenTag: some View {
        let liste = (stand.aufgaben?.jeden_tag ?? []).sorted { ($0.ab ?? "99") < ($1.ab ?? "99") }
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                kopf("JEDEN TAG", "\(liste.filter { $0.erledigt || wartend.contains($0.id) }.count) von \(liste.count)")
                SnFluss(abstand: 8, zeilenAbstand: 8) { ForEach(liste) { routine($0) } }.padding(.top, 12)
            }
            .padding(.top, 22).rein(an, 0.82)
        }
    }

    private func routine(_ j: SenecaStand.Aufgaben.Taeglich) -> some View {
        let fertig = j.erledigt || wartend.contains(j.id)
        return Button { if !fertig { erledige(j.id) } } label: {
            HStack(spacing: 6) {
                if fertig { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(j.titel).font(Schrift.grotesk(14)).lineLimit(1)
                if let ab = j.ab { Text(ab).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).padding(.leading, 4) }
            }
            .foregroundStyle(fertig ? TafelFarbe.hex(0xA8EBBE) : TafelFarbe.text)
            .padding(.horizontal, 14).frame(height: 34)
            .background(Capsule().fill(fertig ? TafelFarbe.gruen.opacity(0.14) : Color.white.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func seite(_ jetzt: Double) -> some View {
        let plan = S.plan(stand, jetzt: jetzt)
        return ZStack(alignment: .topLeading) {
            Text("DEIN TAG").font(Schrift.mono(12, .medium)).tracking(1.4).foregroundStyle(TafelFarbe.zweit)
            Rectangle().fill(LinearGradient(stops: [.init(color: .white.opacity(0.05), location: 0), .init(color: .white.opacity(0.14), location: 0.3), .init(color: .white.opacity(0.06), location: 1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: max(690, plan.hoehe - 70)).offset(x: 56, y: 46)
            Rectangle().fill(LinearGradient(colors: [TafelFarbe.himmel.opacity(0.1), TafelFarbe.himmel.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: an ? max(0, plan.jetztY - 46) : 0).offset(x: 56, y: 46)
                .animation(Kurve.sn(1.6).delay(0.9), value: an)
            ForEach(Array(plan.striche.enumerated()), id: \.offset) { _, y in
                RoundedRectangle(cornerRadius: 1).fill(TafelFarbe.hex(0xA8EBBE, 0.55)).frame(width: 8, height: 2).offset(x: 53, y: y)
            }
            ForEach(plan.eintraege) { e in eintrag(e) }
            Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.3), .init(color: TafelFarbe.himmel.opacity(0), location: 0.7)], center: .center, startRadius: 0, endRadius: 13))
                .frame(width: 26, height: 26)
                .overlay { SnPuls(farbe: .white, ring: TafelFarbe.himmel, groesse: 12, weite: 14, takt: 2.4, deckkraft: 0.6, laeuft: bewegt) }
                .offset(x: 44, y: plan.jetztY - 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.jetzt.titel).font(Schrift.grotesk(15)).foregroundStyle(.white).lineLimit(1)
                Text(plan.jetzt.unter).font(Schrift.grotesk(12.5)).foregroundStyle(TafelFarbe.zweit).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: 248, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TafelFarbe.himmel.opacity(0.13)))
            .offset(x: 84, y: plan.jetztY - 24)
        }
        .frame(width: 320, height: max(760, plan.hoehe), alignment: .topLeading)
    }

    private func eintrag(_ e: SnTagesschiene.Eintrag) -> some View {
        ZStack(alignment: .topLeading) {
            if e.punkt != .keiner {
                Circle().fill(TafelFarbe.hex(0x0B2148)).overlay(Circle().strokeBorder(e.punkt == .bern ? TafelFarbe.bernstein : TafelFarbe.himmel, lineWidth: 1.5))
                    .frame(width: 10, height: 10).offset(x: 52, y: 7)
            }
            HStack(alignment: .top, spacing: 24) {
                Text(e.uhr).font(Schrift.mono(12)).foregroundStyle(e.punkt == .bern ? TafelFarbe.bernstein : TafelFarbe.leise).padding(.top, 3).frame(width: 44, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    if let t = e.titel { Text(t).font(Schrift.grotesk(15)).hoehe(20).foregroundStyle(TafelFarbe.text).lineLimit(1) }
                    if let u = e.unter { Text(u).font(Schrift.grotesk(12.5)).hoehe(18).foregroundStyle(TafelFarbe.leise).lineLimit(1) }
                }
            }
            .opacity(e.blass ? 0.6 : 1)
        }
        .frame(width: 320, alignment: .topLeading)
        .offset(y: e.oben)
    }
}

enum SnTagesschiene {
    enum Punkt { case keiner, himmel, bern }
    struct Eintrag: Identifiable {
        var id: String; var zeit: Double; var uhr: String; var titel: String?; var unter: String?
        var punkt: Punkt = .himmel; var blass = false; var abstand: CGFloat = 24; var oben: CGFloat = 0
        var hoehe: CGFloat { (titel == nil ? 0 : 20) + (unter == nil ? 0 : 18) + (titel != nil && unter != nil ? 2 : 0) }
    }
    struct Plan { var eintraege: [Eintrag]; var striche: [CGFloat]; var jetzt: (titel: String, unter: String); var jetztY: CGFloat; var hoehe: CGFloat }

    private typealias L = HeuteTafelLogik
    static let von = 5.0, bis = 22.0, oben: CGFloat = 46, laenge: CGFloat = 690
    private static let minute = 60_000.0

    static func y(_ ms: Double, _ s: SenecaStand) -> CGFloat {
        let k = Calendar.current.dateComponents([.day, .hour, .minute], from: L.datum(ms))
        let tag = Calendar.current.isDate(L.datum(ms), inSameDayAs: L.datum(s.jetzt))
        let h = tag ? Double(k.hour ?? 0) + Double(k.minute ?? 0) / 60 : ms < s.jetzt ? von : bis
        return oben + laenge * CGFloat(min(1, max(0, (h - von) / (bis - von))))
    }

    static func uhrAb(_ ab: String, _ s: SenecaStand) -> Double? {
        let teile = ab.split(separator: ":").compactMap { Double($0) }
        guard teile.count == 2 else { return nil }
        return Calendar.current.startOfDay(for: L.datum(s.jetzt)).timeIntervalSince1970 * 1000 + (teile[0] * 60 + teile[1]) * minute
    }

    static func dauer(_ ms: Double) -> String {
        let min = Int((ms / minute).rounded())
        if min < 60 { return "\(min) Minuten" }
        let halbe = Int((Double(min) / 30).rounded()), h = halbe / 2
        let wort = h < VerlaufLogik.zahlwort.count ? VerlaufLogik.zahlwort[h] : "\(h)"
        if halbe % 2 == 1 { return h == 1 ? "anderthalb Stunden" : "\(wort)einhalb Stunden" }
        return h == 1 ? "eine Stunde" : "\(wort) Stunden"
    }

    private static func zahl(_ n: Int) -> String {
        let w = n < VerlaufLogik.zahlwort.count ? VerlaufLogik.zahlwort[n] : "\(n)"
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    static func plan(_ s: SenecaStand, jetzt: Double) -> Plan {
        var liste: [Eintrag] = []
        var striche: [CGFloat] = []
        var enden: [Double] = []
        let routinen = (s.aufgaben?.jeden_tag ?? []).compactMap { r in r.ab.flatMap { uhrAb($0, s) }.map { (r, $0) } }.sorted { $0.1 < $1.1 }
        if let erste = routinen.first, let letzte = routinen.last {
            striche = routinen.map { y($0.1, s) }
            let ende = letzte.1 + (letzte.0.dauer_min ?? 0) * minute
            enden.append(ende)
            let fertig = routinen.filter(\.0.erledigt).count
            let stand = fertig == 0 ? "noch keine abgehakt" : fertig == routinen.count ? "alle abgehakt" : "\(VerlaufLogik.zahlwort[min(fertig, 10)]) abgehakt"
            liste.append(Eintrag(id: "routinen", zeit: erste.1, uhr: L.uhr(erste.1), titel: "Routinen", unter: "\(VerlaufLogik.zahlwort[min(routinen.count, 10)]), bis \(L.uhr(ende)) · \(stand)", punkt: .keiner, blass: ende < jetzt))
        }
        let laeufe = (s.team ?? []).compactMap { m in m.zuletzt.flatMap { z in z.um.flatMap { $0 >= (s.tag_beginn ?? 0) ? (m.name, $0, z.art) : nil } } }.sorted { $0.1 < $1.1 }
        var gruppen: [[(String, Double, String?)]] = []
        for l in laeufe {
            if let g = gruppen.last?.last, l.1 - g.1 <= 90 * minute { gruppen[gruppen.count - 1].append(l) } else { gruppen.append([l]) }
        }
        for g in gruppen {
            let rund = g.allSatisfy { $0.2 == "rundgang" }
            let titel = g.count == 1 ? (rund ? "Rundgang" : "\(g[0].0) fertig") : "\(zahl(g.count)) \(rund ? "Rundgänge" : "Läufe")"
            let unter = (g.count == 1 ? g[0].0 : g.map(\.0).joined(separator: ", ")) + " · bis \(L.uhr(g.last?.1 ?? 0))"
            liste.append(Eintrag(id: "team\(g[0].1)", zeit: g[0].1, uhr: L.uhr(g[0].1), titel: titel, unter: unter, blass: (g.last?.1 ?? 0) < jetzt))
        }
        let termine = (s.termine ?? []).filter { $0.ganztag != true && $0.ende - $0.start >= 15 * minute && $0.art != "fokus" }
        for t in termine where !(t.start <= jetzt && t.ende > jetzt) {
            liste.append(Eintrag(id: t.uid, zeit: t.start, uhr: L.uhr(t.start), titel: t.titel, unter: t.weg ?? [t.ort, "\(Int((t.ende - t.start) / minute)) Min"].compactMap { $0 }.joined(separator: " · "), blass: t.ende <= jetzt))
        }
        let geplant = L.todosHeute(s).compactMap { t in t.geplant_von.flatMap { von in t.geplant_bis.map { (von, $0) } } }.sorted { $0.0 < $1.0 }
        var bloecke: [(von: Double, bis: Double, n: Int)] = []
        for p in geplant {
            if let b = bloecke.last, p.0 <= b.bis + minute { bloecke[bloecke.count - 1].bis = max(b.bis, p.1); bloecke[bloecke.count - 1].n += 1 } else { bloecke.append((p.0, p.1, 1)) }
        }
        for b in bloecke where b.von > jetzt {
            liste.append(Eintrag(id: "todos\(b.von)", zeit: b.von, uhr: L.uhr(b.von), titel: b.n == 1 ? "Ein To-do" : "To-dos", unter: b.n == 1 ? "bis \(L.uhr(b.bis))" : "\(VerlaufLogik.zahlwort[min(b.n, 10)]), bis \(L.uhr(b.bis))"))
        }
        let fenster = s.buendel?.kurz == nil ? nil : s.buendel?.fenster
        let fensterBis = s.entscheiden?.fenster_bis ?? (fenster ?? 0) + 30 * minute
        if let f = fenster, f > jetzt { liste.append(Eintrag(id: "fenster", zeit: f, uhr: L.uhr(f), titel: "Entscheiden", unter: s.buendel?.kurz, punkt: .bern)) }

        let jetztTermin = (s.termine ?? []).first { $0.ganztag != true && $0.start <= jetzt && $0.ende > jetzt }
        let jetztBlock = bloecke.first { $0.von <= jetzt && jetzt < $0.bis }
        let uhr = "jetzt \(L.uhr(jetzt))"
        var frei: Double?
        let karte: (titel: String, unter: String)
        let zukunft = liste.filter { $0.zeit > jetzt }.map(\.zeit).min()
        if let t = jetztTermin {
            karte = t.art == "fokus" ? ("Fokus bis \(L.uhr(t.ende))", "Seneca hält Meldungen zurück · \(uhr)") : (t.titel, "bis \(L.uhr(t.ende)) · \(uhr)")
            frei = t.ende
        } else if let b = jetztBlock {
            karte = (b.n == 1 ? "Ein To-do bis \(L.uhr(b.bis))" : "To-dos bis \(L.uhr(b.bis))", "von Seneca geblockt · \(uhr)")
            frei = b.bis
        } else if let f = fenster, f <= jetzt, jetzt < fensterBis {
            karte = ("Entscheiden bis \(L.uhr(fensterBis))", "\(s.buendel?.kurz ?? "") · \(uhr)")
            frei = fensterBis
        } else {
            karte = zukunft.map { ("Frei bis \(L.uhr($0))", "\(dauer($0 - jetzt)) · \(uhr)") } ?? ("Frei", "\((s.entscheiden?.danach ?? "Nichts mehr bis morgen.").split(separator: ".").first.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "") · \(uhr)")
        }
        if let ab = frei, let bis = zukunft, bis - ab >= 60 * minute {
            liste.append(Eintrag(id: "frei", zeit: ab, uhr: "", titel: nil, unter: "frei bis \(L.uhr(bis)) · \(dauer(bis - ab))", punkt: .keiner, abstand: 40))
        }
        if zukunft != nil {
            let ende = (enden + [fenster.map { _ in fensterBis } ?? 0] + termine.map(\.ende) + bloecke.map(\.bis)).max() ?? jetzt
            let danach = s.entscheiden?.danach ?? "Nichts mehr bis morgen."
            liste.append(Eintrag(id: "danach", zeit: ende, uhr: L.uhr(ende), titel: nil, unter: "Danach " + danach.prefix(1).lowercased() + danach.dropFirst(), punkt: .keiner, blass: true, abstand: 40))
        }

        liste.sort { $0.zeit < $1.zeit || $0.zeit == $1.zeit && $0.id == "frei" && $1.id == "danach" }
        var unten: CGFloat = 0
        var jetztY = y(jetzt, s)
        var gesetzt = false
        var fertig: [Eintrag] = []
        for var e in liste {
            if !gesetzt && e.zeit > jetzt {
                jetztY = max(jetztY, unten + 30 + 24)
                unten = jetztY - 24 + 64
                gesetzt = true
            }
            e.oben = max(y(e.zeit, s) - 12, unten + (unten == 0 ? 38 : e.abstand))
            unten = e.oben + e.hoehe
            fertig.append(e)
        }
        if !gesetzt { jetztY = max(jetztY, unten + 30 + 24); unten = jetztY + 40 }
        return Plan(eintraege: fertig, striche: striche, jetzt: karte, jetztY: jetztY, hoehe: unten + 24)
    }
}

struct SnPuls: View {
    var farbe: Color
    var ring: Color?
    var groesse: CGFloat
    var weite: CGFloat
    var takt: Double
    var deckkraft: Double
    var laeuft = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !laeuft)) { t in
            let p = laeuft ? t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: takt) / takt : 0.9
            let r = min(1, p / 0.7), w = 1 - pow(1 - r, 3)
            Circle().fill(farbe).frame(width: groesse, height: groesse)
                .background(Circle().fill((ring ?? farbe).opacity(p < 0.7 ? deckkraft * (1 - r) : 0)).frame(width: groesse + 2 * weite * w, height: groesse + 2 * weite * w))
        }
        .frame(width: groesse, height: groesse)
    }
}

struct SnHeuteKnopf: ButtonStyle {
    enum Art { case haupt, neben, leise }
    var art: Art
    var glimmt = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !glimmt)) { t in
            let p = glimmt ? t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 : 1
            let g = p < 0.3 ? sin(p / 0.3 * .pi / 2) : p < 0.6 ? cos((p - 0.3) / 0.3 * .pi / 2) : 0
            configuration.label
                .fixedSize()
                .font(Schrift.grotesk(15, .medium))
                .foregroundStyle(art == .haupt ? TafelFarbe.aufHimmel : art == .neben ? TafelFarbe.text : TafelFarbe.zweit)
                .padding(.horizontal, art == .leise ? 12 : 20).frame(height: 44)
                .background {
                    if art == .haupt {
                        Capsule().fill(TafelFarbe.himmel.opacity(0.18 * g)).padding(-6)
                        Capsule().fill(TafelFarbe.himmel.opacity(hover ? 0.9 : 1)).shadow(color: TafelFarbe.himmel.opacity(0.55 * g), radius: 15, y: 10)
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
