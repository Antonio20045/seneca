import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
}

struct SnHeuteTafel: View {
    var stand: SenecaStand
    var wartend: Set<String>
    var erledige: (String) -> Void
    var zuDenFragen: () -> Void
    var zurArbeit: () -> Void
    var neu: Set<String> = []

    private typealias L = HeuteTafelLogik
    static func kennung(_ m: SenecaStand.Mitglied) -> String { "team:\(m.name):\(m.satz ?? m.zuletzt?.satz ?? m.zustand)" }
    private let linie = Color.white.opacity(0.07)

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 80) {
                    haupt.frame(width: 860, alignment: .topLeading)
                    seite.frame(width: 320, alignment: .topLeading)
                }
                .padding(.leading, max(24, (g.size.width - 1260) / 2 + 6))
                .padding(.top, 108).padding(.bottom, 170)
                .frame(width: g.size.width, alignment: .topLeading)
            }
            .scrollClipDisabled()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - 150 / max(g.size.height, 300)), .init(color: .clear, location: 1 - 84 / max(g.size.height, 300))], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(TafelFarbe.text)
    }

    private var haupt: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(L.datumZeile(stand.jetzt)) · \(L.uhr(stand.jetzt))").font(Schrift.mono(13)).tracking(0.4).foregroundStyle(TafelFarbe.zweit)
                if let r = stand.ruhe, r.grund == "fokus", let bis = r.bis {
                    Text("FOKUS · NOCH \(Int(max(0, bis - stand.jetzt) / 60_000)) MIN").font(Schrift.mono(11)).tracking(1.2)
                        .foregroundStyle(TafelFarbe.akzent).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(TafelFarbe.himmel.opacity(0.16)))
                }
            }
            .padding(.bottom, 14)
            if let satz = L.satz(stand) {
                (Text(satz.vor + " ").font(Schrift.serif(44)).foregroundColor(.white) + Text(satz.akzent).font(Schrift.serif(44, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                    .tracking(-0.5).hoehe(46.6).fixedSize(horizontal: false, vertical: true)
            }
            fragen.padding(.top, 30)
            team.padding(.top, 30)
            todos.padding(.top, 30)
        }
    }

    private func kopf(_ titel: String, _ rechts: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titel).font(Schrift.mono(12, .medium)).tracking(1.4).foregroundStyle(TafelFarbe.zweit)
            Spacer()
            Text(rechts).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.bottom, 6)
    }

    private var wartende: [SenecaStand.Frage] {
        (stand.ruhe == nil ? [] : stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? [])
    }

    @ViewBuilder private var fragen: some View {
        let liste = stand.ruhe == nil ? stand.braucht_dich ?? [] : wartende
        if !liste.isEmpty || stand.eben_beantwortet?.isEmpty == false || stand.buendel?.satz != nil {
            VStack(alignment: .leading, spacing: 0) {
                let titel = stand.ruhe?.bis.map { "WARTET BIS \(L.uhr($0)) · " } ?? "BRAUCHT DICH · "
                if !liste.isEmpty { kopf(titel + (liste.count == 1 ? "1 FRAGE" : "\(liste.count) FRAGEN"), "nach Folge sortiert") } else if stand.buendel?.satz != nil { kopf("WARTET AUF DICH", "") }
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    ForEach(HeuteTafelLogik.ebenBeantwortet(stand, jetzt: t.date)) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.text).font(Schrift.grotesk(16)).hoehe(22).foregroundStyle(TafelFarbe.text)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(TafelFarbe.gruen)
                                Text(f.antwort.map { HeuteTafelLogik.antwortZeile(f, $0) } ?? "").font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.gruen)
                            }
                        }
                        .padding(.leading, 40).padding(.vertical, 10)
                        .overlay(alignment: .top) { linie.frame(height: 1) }
                        .transition(.opacity)
                    }
                }
                ForEach(Array(liste.enumerated()), id: \.element.id) { i, f in
                    Button(action: zuDenFragen) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(i + 1)").font(Schrift.grotesk(14, .medium)).monospacedDigit().foregroundStyle(TafelFarbe.leise).frame(width: 26, alignment: .leading)
                            Text(f.text).font(Schrift.grotesk(16)).hoehe(22).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                            if neu.contains(f.id) { Text("NEU").font(Schrift.mono(10)).kerning(1).foregroundStyle(TafelFarbe.leise) }
                            herkunft(f)
                        }
                        .padding(.vertical, 10)
                        .modifier(SnNeuHell(an: neu.contains(f.id)))
                        .overlay(alignment: .top) { linie.frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let satz = stand.buendel?.satz, let f = stand.buendel?.fenster {
                    HStack {
                        Text("Gebündelt für \(L.uhr(f)): \(satz)")
                        Spacer()
                        Button("Jetzt schon ansehen", action: zuDenFragen).buttonStyle(.plain).font(Schrift.grotesk(14, .medium)).foregroundStyle(TafelFarbe.himmel)
                    }
                    .font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.zweit)
                    .padding(.leading, 40).padding(.top, 12)
                    .overlay(alignment: .top) { linie.frame(height: 1) }
                }
            }
        }
    }

    private func herkunft(_ f: SenecaStand.Frage) -> some View {
        let von = [f.von ?? "Seneca", f.projekt].compactMap { $0 }.joined(separator: " · ")
        let frist = f.frist.map { L.frist($0, jetzt: stand.jetzt) }
        let seit = f.seit.map { $0 < (stand.tag_beginn ?? 0) ? "seit gestern" : "seit \(L.uhr($0))" } ?? ""
        return (Text(von + " · ").foregroundColor(TafelFarbe.leise) + Text(frist ?? seit).foregroundColor(frist == nil ? TafelFarbe.leise : TafelFarbe.bernstein))
            .font(Schrift.mono(12))
    }

    @ViewBuilder private var team: some View {
        let mitglieder = stand.team ?? []
        if !mitglieder.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                let arbeiten = mitglieder.filter { $0.zustand == "arbeitet" }.count
                kopf("LÄUFT GERADE", "\(arbeiten) von \(mitglieder.filter { $0.zustand != "ruht" }.count) arbeitet")
                ForEach(mitglieder, id: \.name) { m in
                    let fragen = (stand.braucht_dich ?? []).filter { $0.von == m.name }.count + (stand.buendel?.fragen ?? []).filter { $0.von == m.name }.count
                    Button(action: zurArbeit) {
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            HStack(spacing: 10) {
                                punkt(m.zustand, wartet: fragen > 0)
                                Text(m.name).font(Schrift.grotesk(15)).foregroundStyle(.white)
                            }
                            .frame(width: 132, alignment: .leading)
                            Group {
                                if fragen > 0 && m.zustand != "arbeitet" {
                                    Text("wartet auf dich ") + Text("· \(fragen == 1 ? "1 Frage" : "\(fragen) Fragen")").foregroundColor(TafelFarbe.leise)
                                } else if let satz = m.satz {
                                    Text(satz + " ") + Text(m.projekt.map { "· \($0)" } ?? "").foregroundColor(TafelFarbe.leise)
                                } else {
                                    Text(m.zustand == "ruht" ? m.ruht_seit.map { VerlaufLogik.ruhtSeit($0, jetzt: stand.jetzt) } ?? "ruht" : m.zuletzt?.satz ?? "frei")
                                }
                            }
                            .font(Schrift.grotesk(15)).hoehe(22).lineLimit(1).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                            Text((neu.contains(Self.kennung(m)) ? "NEU · " : "") + rechts(m)).font(Schrift.mono(12))
                                .foregroundStyle(m.zustand == "arbeitet" ? TafelFarbe.gruen : TafelFarbe.zweit)
                        }
                        .padding(.vertical, 10)
                        .modifier(SnNeuHell(an: neu.contains(Self.kennung(m))))
                        .overlay(alignment: .top) { linie.frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rechts(_ m: SenecaStand.Mitglied) -> String {
        if m.zustand == "arbeitet" { return m.rest_min.map { "noch \(Int($0)) Min" } ?? m.seit.map { "seit \(L.uhr($0))" } ?? "" }
        return m.zuletzt?.um.map { L.uhr($0) } ?? ""
    }

    @ViewBuilder private func punkt(_ zustand: String, wartet: Bool) -> some View {
        if zustand == "arbeitet" {
            Circle().fill(TafelFarbe.gruen).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.gruen.opacity(0.16)).frame(width: 16, height: 16))
        } else if wartet {
            Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
        } else {
            Circle().strokeBorder(TafelFarbe.himmel, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private var todos: some View {
        let liste = L.todosHeute(stand)
        let jeden = stand.aufgaben?.jeden_tag ?? []
        let summe = liste.compactMap(\.dauer_min).reduce(0, +)
        return VStack(alignment: .leading, spacing: 0) {
            if !liste.isEmpty { kopf(stand.ruhe?.grund == "fokus" ? "DEINE TO-DOS · NACH DEM FOKUS" : "DEINE TO-DOS", summe > 0 ? "\(Int(summe)) Min" : "") }
            ForEach(liste) { t in
                let w = wartend.contains(t.id)
                Button { if !w { erledige(t.id) } } label: {
                    HStack(spacing: 14) {
                        Circle().strokeBorder(w ? TafelFarbe.gruen : TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: w ? [3, 2.4] : []))
                            .frame(width: 18, height: 18).frame(width: 26, alignment: .leading)
                        (Text(t.titel).foregroundColor(w ? TafelFarbe.aus : TafelFarbe.text).strikethrough(w)
                            + Text(t.bereich.map { " · \($0)" } ?? "").foregroundColor(TafelFarbe.leise))
                            .font(Schrift.grotesk(15)).hoehe(21).frame(maxWidth: .infinity, alignment: .leading)
                        Text(w ? "WIRD ÜBERTRAGEN" : t.dauer_min.map { "\(Int($0)) MIN" } ?? "").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { linie.frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !jeden.isEmpty {
                kopf("JEDEN TAG", "\(jeden.filter { $0.erledigt || wartend.contains($0.id) }.count) von \(jeden.count)").padding(.top, liste.isEmpty ? 0 : 24)
                HStack(spacing: 8) { ForEach(jeden) { routine($0) } }.padding(.top, 6)
            }
        }
    }

    private func routine(_ j: SenecaStand.Aufgaben.Taeglich) -> some View {
        let fertig = j.erledigt || wartend.contains(j.id)
        return Button { if !fertig { erledige(j.id) } } label: {
            HStack(spacing: 6) {
                if fertig { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(j.titel).font(Schrift.grotesk(14)).lineLimit(1)
            }
            .foregroundStyle(fertig ? TafelFarbe.hex(0xA8EBBE) : TafelFarbe.text)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(fertig ? TafelFarbe.gruen.opacity(0.14) : Color.white.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var seite: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DEIN TAG").font(Schrift.mono(12)).tracking(1.4).foregroundStyle(TafelFarbe.zweit).padding(.bottom, 14)
            if let k = stand.koerper, let bb = k.body_battery { koerper(k, bb).padding(.bottom, 14) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tagesPunkte, id: \.id) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(p.jetzt ? "jetzt" : L.uhr(p.start)).font(Schrift.mono(13)).foregroundStyle(p.farbe).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.titel).font(Schrift.grotesk(16)).hoehe(22).foregroundStyle(p.jetzt ? .white : TafelFarbe.text)
                            if let u = p.unter { Text(u).font(Schrift.grotesk(13)).hoehe(19).foregroundStyle(p.jetzt ? TafelFarbe.zweit : TafelFarbe.leise) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, p.jetzt ? 12 : 0)
                    .background(RoundedRectangle(cornerRadius: 14).fill(p.jetzt ? TafelFarbe.himmel.opacity(0.12) : .clear))
                    .padding(.horizontal, p.jetzt ? -12 : 0)
                    .opacity(p.vorbei ? 0.55 : 1)
                }
            }
            .padding(.top, 16)
            if let e = stand.heute_erledigt, !e.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                    Text("Heute erledigt: " + e.map(\.titel).joined(separator: ", ")).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.top, 22)
            }
        }
    }

    private func koerper(_ k: SenecaStand.Koerper, _ bb: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                Text("\(Int(bb))").font(Schrift.grotesk(56, .medium)).tracking(-1).monospacedDigit().foregroundStyle(.white).hoehe(50.4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(k.titel ?? "Body Battery").font(Schrift.grotesk(15)).hoehe(20).foregroundStyle(TafelFarbe.text)
                    Text((["Garmin", k.zeit.map { L.uhr($0) }, k.morgens.map { "morgens \(Int($0))" }] as [String?]).compactMap { $0 }.joined(separator: " · "))
                        .font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.bottom, 4)
            }
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1) }
            if let h = k.hinweis { Text(h).font(Schrift.grotesk(14)).hoehe(21).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private struct Punkt { var id: String; var start: Double; var titel: String; var unter: String?; var farbe: Color; var jetzt: Bool; var vorbei: Bool }

    private var tagesPunkte: [Punkt] {
        let j = stand.jetzt
        var p: [Punkt] = (stand.termine ?? []).filter { $0.ganztag != true && $0.ende - $0.start >= 15 * 60_000 && ($0.art != "fokus" || $0.start <= j && $0.ende > j) }.map { t in
            let jetzt = t.start <= j && t.ende > j, vorbei = t.ende <= j
            let titel = t.art == "fokus" ? "Fokus bis \(L.uhr(t.ende))" : t.titel
            let unter: String? = switch t.art {
            case "fokus": "Seneca hält Meldungen zurück"
            case "bewegung": vorbei ? nil : "Seneca schweigt, solange du läufst"
            default: t.weg ?? [t.ort, "\(Int((t.ende - t.start) / 60_000)) Min"].compactMap { $0 }.joined(separator: " · ")
            }
            let farbe = t.art == "bewegung" && vorbei ? TafelFarbe.gruen : jetzt ? TafelFarbe.himmel : TafelFarbe.zweit
            return Punkt(id: t.uid, start: t.start, titel: titel, unter: unter, farbe: farbe, jetzt: jetzt, vorbei: vorbei)
        }
        if let f = stand.buendel?.fenster {
            p.append(Punkt(id: "fenster", start: f, titel: "Entscheidungsfenster", unter: stand.buendel?.kurz, farbe: TafelFarbe.bernstein, jetzt: false, vorbei: f < j))
        }
        return p.sorted { $0.start < $1.start }.filter { !$0.titel.isEmpty && !($0.vorbei && $0.farbe != TafelFarbe.gruen) || $0.jetzt }
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
