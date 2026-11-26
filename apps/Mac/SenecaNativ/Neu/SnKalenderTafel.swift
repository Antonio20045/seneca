import SwiftUI

private extension View {
    func hoehe(_ punkte: CGFloat) -> some View { lineHeight(.exact(points: punkte)) }
}

@MainActor
final class SnKalZustand: ObservableObject {
    static let gemeinsam = SnKalZustand()
    @Published var ansicht = KalAnsicht.woche
    @Published var woche: Int?
    @Published var tag: Double?
    @Published var auswahl: String?
    @Published var entwurf: KalEntwurf?
    @Published var verschoben: [String: (Double, Double)] = [:]
    var blaettere: ((Int) -> Void)?
}

private enum KF {
    static let stunde: CGFloat = 49, links: CGFloat = 52, breite: CGFloat = 908
    static let mono = { (g: CGFloat) in Schrift.mono(g) }
    static let gutText = TafelFarbe.hex(0xF3D58E)
}

struct SnKalenderTafel: View {
    var stand: SenecaStand
    var handeln: (String, String?, [String: JSONWert]) -> Void
    var antworte: (String, String) -> Void
    var zumChat: (String?) -> Void
    var rechneWeg: (String) async -> KalWeg?
    @ObservedObject var z = SnKalZustand.gemeinsam
    @FocusState private var titelFokus: Bool

    private typealias L = KalenderLogik
    private var k: SenecaStand.Kalender? { stand.kalender }
    private func regel(_ n: String, _ s: Double) -> Double { stand.regeln?[n] ?? s }

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                if let k {
                    HStack(alignment: .top, spacing: 40) {
                        VStack(alignment: .leading, spacing: 24) {
                            kopf(k)
                            if z.ansicht == .monat { monat(k) } else { raster(k) }
                        }
                        .frame(width: KF.breite, alignment: .topLeading)
                        seite(k).frame(width: 316, alignment: .topLeading)
                            .padding(.top, z.entwurf == nil && auswahlBlock == nil ? 64 : 0)
                    }
                    .padding(.leading, max(24, (g.size.width - 1248) / 2)).padding(.top, 104).padding(.bottom, 120)
                    .frame(width: g.size.width, alignment: .topLeading)
                }
            }
            .scrollClipDisabled()
        }
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.22, 0), (0.09, 0.14), (0, 0.30)]))
        .foregroundStyle(TafelFarbe.text)
        .accessibilityIdentifier("seite-kalender")
        .onAppear { z.blaettere = { blaettere($0) } }
    }

    private var wocheIndex: Int { z.woche ?? k.map { L.wocheVon($0, jetzt: stand.jetzt) } ?? 0 }
    private var tagMs: Double { z.tag ?? stand.kalender?.tage.first { L.gleicherTag($0.tag, stand.jetzt) }?.tag ?? stand.jetzt }
    private var sichtbar: [SenecaStand.KalTag] {
        guard let k else { return [] }
        return z.ansicht == .tag ? k.tage.filter { L.gleicherTag($0.tag, tagMs) } : Array(L.tage(k, woche: wocheIndex))
    }
    private var auswahlBlock: SenecaStand.KalBlock? { z.auswahl.flatMap { id in k?.tage.lazy.flatMap(\.bloecke).first { $0.id == id } } }

    private func kopf(_ k: SenecaStand.Kalender) -> some View {
        let t = L.kopf(k, ansicht: z.ansicht, woche: wocheIndex, tag: tagMs, jetzt: stand.jetzt)
        return HStack(alignment: .bottom) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(t.titel).font(Schrift.serif(40)).hoehe(40).foregroundStyle(Color.white)
                Text(t.unter).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
            }
            Spacer()
            HStack(spacing: 6) {
                pfeil("chevron.left", "Zurück") { blaettere(-1) }
                pfeil("chevron.right", "Weiter") { blaettere(1) }
                HStack(spacing: 2) {
                    ForEach(KalAnsicht.allCases, id: \.self) { a in
                        Button { z.ansicht = a } label: {
                            Text(a.name).font(Schrift.grotesk(13, .medium)).padding(.horizontal, 12).padding(.vertical, 5)
                                .foregroundStyle(a == z.ansicht ? Color.white : TafelFarbe.zweit)
                                .background(Capsule().fill(Color.white.opacity(a == z.ansicht ? 0.14 : 0)))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(3).background(Capsule().fill(Color.white.opacity(0.06))).padding(.leading, 8)
            }
        }
    }

    private func pfeil(_ symbol: String, _ name: String, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular)).foregroundStyle(TafelFarbe.zweit).frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(name)
    }

    func blaettere(_ n: Int) {
        guard let k else { return }
        switch z.ansicht {
        case .tag: z.tag = min(max(tagMs + Double(n) * 86_400_000, k.tage.first?.tag ?? 0), k.tage.last?.tag ?? 0)
        case .woche: z.woche = min(max(wocheIndex + n, 0), k.wochen.count - 1)
        case .monat: z.woche = min(max(wocheIndex + 4 * n, 0), k.wochen.count - 1)
        }
    }

    private func spalte(_ n: Int) -> CGFloat { (KF.breite - KF.links) / CGFloat(n) }
    private var von: Double { k?.tag_von ?? 8 }
    private var hoehe: CGFloat { CGFloat((k?.tag_bis ?? 20) - von) * KF.stunde }

    private func raster(_ k: SenecaStand.Kalender) -> some View {
        let tage = sichtbar, w = spalte(tage.count)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                Color.clear.frame(width: KF.links, height: 1)
                ForEach(tage, id: \.tag) { t in tagKopf(t).frame(width: w, alignment: .leading) }
            }
            .padding(.bottom, 10)
            HStack(spacing: 0) {
                Text("BODY BATTERY").font(Schrift.mono(11)).kerning(0.6).foregroundStyle(TafelFarbe.leise).frame(width: KF.links, alignment: .leading)
                ForEach(tage, id: \.tag) { t in bb(t).frame(width: w, alignment: .leading) }
            }
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            if tage.contains(where: { !$0.ganztag.isEmpty }) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: KF.links, height: 1)
                    ForEach(tage, id: \.tag) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(t.ganztag, id: \.self) { g in
                                Text(g).font(Schrift.grotesk(11)).foregroundStyle(Color.white).lineLimit(1).padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(TafelFarbe.himmel.opacity(0.16)))
                            }
                        }
                        .padding(.horizontal, 4).frame(width: w, alignment: .topLeading)
                    }
                }
                .padding(.top, 6)
            }
            HStack(alignment: .top, spacing: 0) {
                zeiten(tage).frame(width: KF.links, height: hoehe, alignment: .topLeading)
                ForEach(tage, id: \.tag) { t in tagSpalte(t, breite: w) }
            }
            .padding(.top, 4)
        }
    }

    private func tagKopf(_ t: SenecaStand.KalTag) -> some View {
        let heute = L.gleicherTag(t.tag, stand.jetzt), vorbei = t.tag < stand.jetzt && !heute
        return HStack(alignment: heute ? .center : .firstTextBaseline, spacing: heute ? 6 : 4) {
            Text(L.format(t.tag, "EE").replacingOccurrences(of: ".", with: "")).font(Schrift.grotesk(13)).foregroundStyle(heute ? Color.white : TafelFarbe.leise)
            if heute {
                Text(L.format(t.tag, "d")).font(Schrift.grotesk(14, .medium)).foregroundStyle(TafelFarbe.aufHimmel).frame(width: 26, height: 26).background(Circle().fill(TafelFarbe.himmel))
            } else {
                Text(L.format(t.tag, "d")).font(Schrift.grotesk(16, .medium)).foregroundStyle(vorbei ? TafelFarbe.zweit : TafelFarbe.text)
            }
        }
        .padding(.leading, 8)
        .contentShape(Rectangle())
        .onTapGesture { z.tag = t.tag; z.ansicht = .tag }
    }

    @ViewBuilder private func bb(_ t: SenecaStand.KalTag) -> some View {
        let heute = L.gleicherTag(t.tag, stand.jetzt)
        if let v = t.bb {
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.10)).frame(width: 24, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(v >= regel("kal_bb_gut_ab", 60) ? TafelFarbe.gruen : TafelFarbe.zweit).frame(width: 24 * min(1, v / 100), height: 3)
                }
                Text("\(Int(v))").foregroundStyle(heute ? Color.white : TafelFarbe.zweit)
                if heute { Text("jetzt").foregroundStyle(TafelFarbe.leise) }
            }
            .font(Schrift.mono(11)).padding(.leading, 8)
        } else {
            Text("–").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).padding(.leading, 8)
        }
    }

    private var jetztSichtbar: Bool { sichtbar.contains { L.gleicherTag($0.tag, stand.jetzt) } }

    private func zeiten(_ tage: [SenecaStand.KalTag]) -> some View {
        let tag0 = tage.first?.tag ?? 0
        let jetztY = L.y(stand.jetzt, tag: tagBeginn(stand.jetzt), von: von, stunde: KF.stunde)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: von, through: k?.tag_bis ?? 20, by: 2)), id: \.self) { h in
                let y = (h - von) * KF.stunde
                if !(jetztSichtbar && abs(y - jetztY) < KF.stunde / 2) {
                    Text(String(format: "%02d:00", Int(h))).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).fixedSize().offset(y: y - 7)
                }
            }
            if jetztSichtbar, jetztY >= 0, jetztY <= hoehe {
                Text(L.uhr(stand.jetzt)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.jetzt).padding(.trailing, 4)
                    .background(TafelFarbe.hex(0x0E2650)).fixedSize().offset(y: jetztY - 7)
            }
        }
        .id(tag0)
    }

    private func tagBeginn(_ ms: Double) -> Double { L.cal().startOfDay(for: HeuteTafelLogik.datum(ms)).timeIntervalSince1970 * 1000 }

    private func yPos(_ ms: Double, _ tag: Double) -> CGFloat { L.y(ms, tag: tag, von: von, stunde: KF.stunde) }
    private func msAus(_ y: CGFloat, _ tag: Double) -> Double { tag + (Double(y) / KF.stunde + von) * 3_600_000 }

    private func tagSpalte(_ t: SenecaStand.KalTag, breite: CGFloat) -> some View {
        let heute = L.gleicherTag(t.tag, stand.jetzt)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white.opacity(heute ? 0.035 : 0)).contentShape(Rectangle())
                .gesture(neuZiehen(t.tag))
            ForEach(t.bloecke) { b in
                let (s, e) = z.verschoben[b.id] ?? (b.start, b.ende)
                let y = max(0, yPos(s, t.tag)), h = max(18, min(hoehe, yPos(e, t.tag)) - y - 4)
                if y < hoehe, h > 0 {
                    SnKalBlock(b: b, hoehe: h, gewaehlt: z.auswahl == b.id)
                        .frame(width: breite - 8, height: h)
                        .offset(x: 4, y: y)
                        .onTapGesture { z.entwurf = nil; z.auswahl = z.auswahl == b.id ? nil : b.id }
                        .gesture(verschieben(b, tag: t.tag))
                }
            }
            ForEach(Array(t.marken.enumerated()), id: \.offset) { _, m in
                HStack(spacing: 4) {
                    Rectangle().fill(TafelFarbe.gruen).frame(width: 6, height: 6).rotationEffect(.degrees(45))
                    Text("\(m.titel) \(L.uhr(m.zeit))").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.gruen)
                }
                .fixedSize().frame(width: breite - 6, alignment: .trailing).offset(y: yPos(m.zeit, t.tag) - 6)
            }
            if let e = z.entwurf, L.gleicherTag(e.start, t.tag) { entwurfBlock(e, tag: t.tag, breite: breite) }
            if heute {
                let y = yPos(stand.jetzt, t.tag)
                if y >= 0, y <= hoehe {
                    Rectangle().fill(TafelFarbe.jetzt).frame(width: breite + 1, height: 2).offset(x: -1, y: y)
                    Circle().fill(TafelFarbe.jetzt).frame(width: 8, height: 8).offset(x: -4, y: y - 3)
                }
            }
        }
        .frame(width: breite, height: hoehe, alignment: .topLeading)
        .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }

    private var raster: Double { NSEvent.modifierFlags.contains(.option) ? regel("kal_raster_fein_min", 5) : regel("kal_raster_min", 15) }

    private func neuZiehen(_ tag: Double) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in
            let a = L.raste(msAus(v.startLocation.y, tag), tag: tag, minuten: raster)
            let b = max(a + raster * 60_000, L.raste(msAus(v.location.y, tag), tag: tag, minuten: raster))
            z.auswahl = nil
            z.entwurf = KalEntwurf(titel: z.entwurf?.uid == nil ? z.entwurf?.titel ?? "" : "", start: a, ende: b, ort: z.entwurf?.ort ?? "", kalender: k?.standard ?? "Privat", weg: z.entwurf?.weg)
        }
        .onEnded { v in
            if abs(v.translation.height) < 4, var e = z.entwurf { e.ende = e.start + 3_600_000; z.entwurf = e }
            titelFokus = true
        }
    }

    private func verschieben(_ b: SenecaStand.KalBlock, tag: Double) -> some Gesture {
        DragGesture(minimumDistance: 6).onChanged { v in
            guard b.uid != nil, ["termin", "seneca", "bewegung"].contains(b.art) else { return }
            let s = L.raste(b.start + Double(v.translation.height / KF.stunde) * 3_600_000, tag: tag, minuten: raster)
            z.verschoben[b.id] = (s, s + b.ende - b.start)
        }
        .onEnded { _ in
            guard let uid = b.uid, let (s, e) = z.verschoben[b.id], s != b.start else { z.verschoben[b.id] = nil; return }
            handeln("termin.verschieben", uid, ["start": .zahl(s), "ende": .zahl(e)])
        }
    }

    private func entwurfBlock(_ e: KalEntwurf, tag: Double, breite: CGFloat) -> some View {
        let y = yPos(e.start, tag), h = max(20, yPos(e.ende, tag) - y - 4)
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(e.titel.isEmpty ? "Neuer Termin" : e.titel).font(Schrift.grotesk(12)).hoehe(16).foregroundStyle(Color.white)
                if h >= 40 { Text("\(L.uhr(e.start)) bis \(L.uhr(e.ende))").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.akzent).frame(height: 20, alignment: .bottom).padding(.top, -1) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(width: breite - 8, height: h, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
            Circle().fill(Color.white).frame(width: 10, height: 10).background(Circle().fill(Color.white.opacity(0.25)).frame(width: 16, height: 16))
                .offset(x: breite - 8 - 3, y: h - 3)
                .gesture(DragGesture().onChanged { v in
                    guard var neu = z.entwurf else { return }
                    neu.ende = max(neu.start + raster * 60_000, L.raste(msAus(y + h + v.translation.height, tag), tag: tag, minuten: raster))
                    z.entwurf = neu
                })
        }
        .offset(x: 4, y: y)
    }

    private func monat(_ k: SenecaStand.Kalender) -> some View {
        let tage = L.monat(k, woche: wocheIndex), w = KF.breite / 7
        let reihen = stride(from: 0, to: tage.count, by: 7).map { Array(tage[$0..<min(tage.count, $0 + 7)]) }
        return VStack(spacing: 0) {
            ForEach(reihen, id: \.first?.tag) { r in
                HStack(spacing: 0) {
                    ForEach(r, id: \.tag) { t in
                        let heute = L.gleicherTag(t.tag, stand.jetzt)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.format(t.tag, "d")).font(Schrift.grotesk(13, .medium)).foregroundStyle(heute ? TafelFarbe.aufHimmel : TafelFarbe.text)
                                .frame(width: 22, height: 22).background(Circle().fill(heute ? TafelFarbe.himmel : .clear))
                            ForEach(t.bloecke.prefix(3)) { b in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 1).fill(SnKalBlock.farbe(b.art)).frame(width: 2, height: 10)
                                    Text(b.titel).font(Schrift.grotesk(11)).foregroundStyle(TafelFarbe.zweit).lineLimit(1)
                                }
                            }
                            if t.bloecke.count > 3 { Text("+\(t.bloecke.count - 3)").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise) }
                        }
                        .padding(8).frame(width: w, height: 112, alignment: .topLeading)
                        .overlay(alignment: .topLeading) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                        .contentShape(Rectangle())
                        .onTapGesture { z.tag = t.tag; z.ansicht = .tag }
                    }
                }
            }
        }
    }

    @ViewBuilder private func seite(_ k: SenecaStand.Kalender) -> some View {
        if let e = z.entwurf { SnKalNeu(e: e, k: k, stand: stand, fokus: $titelFokus, eintragen: eintragen, abbrechen: { z.entwurf = nil }, rechneWeg: rechneWeg) }
        else if let b = auswahlBlock, let d = b.detail { detail(b, d) }
        else if let b = auswahlBlock, let f = b.frage_id { vorschlag(b, f) }
        else { plant(k) }
    }

    func eintragen() {
        guard let e = z.entwurf, !e.titel.isEmpty else { return }
        if let uid = e.uid {
            var w = L.handlung(e)
            w["kalender"] = nil
            handeln("termin.verschieben", uid, w)
            z.verschoben[uid] = (e.start, e.ende)
        } else { handeln("termin.anlegen", nil, L.handlung(e)) }
        z.entwurf = nil
    }

    private func etikett(_ t: String) -> some View { Text(t).font(Schrift.mono(12)).kerning(1.4).foregroundStyle(TafelFarbe.zweit) }

    private func plant(_ k: SenecaStand.Kalender) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            etikett("SENECA PLANT")
            if let p = k.plant {
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.titel).font(Schrift.grotesk(16, .medium)).hoehe(22).foregroundStyle(Color.white)
                    Text(p.text).font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    HStack(spacing: 8) {
                        if let knopf = p.knopf, let s = p.start, let e = p.ende {
                            Button(knopf) { handeln("termin.verschieben", p.uid, ["start": .zahl(s), "ende": .zahl(e)]) }.buttonStyle(SnTafelKnopf(groesse: 14))
                        }
                        Button("Lassen") { handeln("kalender.lassen", p.id, [:]) }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 14))
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(TafelFarbe.bernstein.opacity(0.28), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach([("termin", "Termin"), ("seneca", "von Seneca gesetzt"), ("fenster", "Entscheidungsfenster"), ("bewegung", "Sport")], id: \.0) { art, name in
                    HStack(spacing: 10) {
                        SnKalBlock.grund(art, RoundedRectangle(cornerRadius: 4)).frame(width: 22, height: 12)
                        Text(name).font(Schrift.grotesk(13)).hoehe(18).foregroundStyle(TafelFarbe.zweit)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(width: 300, alignment: .leading)
    }

    private func zeile(_ name: String, _ wert: String, _ unter: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name).font(Schrift.mono(11)).kerning(0.8).hoehe(20).foregroundStyle(TafelFarbe.leise).frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(wert).font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(Color.white)
                if let unter { Text(unter).font(Schrift.grotesk(12)).hoehe(17).foregroundStyle(TafelFarbe.leise) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func detail(_ b: SenecaStand.KalBlock, _ d: SenecaStand.TerminDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            etikett("TERMIN")
            Text(b.titel).font(Schrift.serif(34)).hoehe(35).foregroundStyle(Color.white).padding(.top, 10).padding(.bottom, 6)
            Text(d.datum.uppercased()).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(.bottom, 14)
            if let da = d.da { zeile("DU BIST DA", L.uhr(da), d.da_satz) }
            if let o = d.ort { zeile("WO", o, d.km) }
            if let w = d.weg { zeile("WEG", w, d.los) }
            if let m = d.mit { zeile("MIT", m) }
            zeile("KALENDER", d.kalender ?? "–", "Apple-Kalender, du kannst ändern")
            zeile("NOTIZ", d.notiz ?? "–")
            if let s = d.seneca {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        SnKugel(groesse: 10, atmet: false)
                        Text("SENECA · \(L.uhr(s.zeit))").font(Schrift.mono(11)).kerning(0.8).foregroundStyle(TafelFarbe.leise)
                    }
                    .padding(.bottom, 6)
                    Text(s.satz).font(Schrift.grotesk(13)).hoehe(19).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                    Button("Im Gespräch ansehen ›") { zumChat(nil) }.buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel).padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(TafelFarbe.himmel.opacity(0.08)))
                .padding(.top, 14)
            }
            HStack(spacing: 8) {
                if let o = d.ort, let u = URL(string: "maps://?daddr=\(o.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Button("Route") { NSWorkspace.shared.open(u) }.buttonStyle(SnKalKnopf(voll: true))
                }
                Button("Schreiben") { zumChat("Zu „\(b.titel)“: ") }.buttonStyle(SnKalKnopf(voll: true))
                if let uid = b.uid {
                    Button("Bearbeiten") {
                        z.entwurf = KalEntwurf(titel: b.titel, start: b.start, ende: b.ende, ort: d.ort ?? "", kalender: d.kalender ?? k?.standard ?? "Privat", weg: nil, uid: uid)
                        z.auswahl = nil
                    }.buttonStyle(SnKalKnopf(voll: false))
                }
            }
            .padding(.top, 16)
        }
    }

    private func vorschlag(_ b: SenecaStand.KalBlock, _ frage: String) -> some View {
        let f = ((stand.braucht_dich ?? []) + (stand.buendel?.fragen ?? [])).first { $0.id == frage }
        return VStack(alignment: .leading, spacing: 0) {
            etikett("VORSCHLAG")
            Text(b.titel).font(Schrift.serif(34)).hoehe(35).foregroundStyle(Color.white).padding(.top, 10).padding(.bottom, 6)
            Text(L.zeitZeile(b.start, b.ende)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(.bottom, 14)
            if let f { Text(f.text).font(Schrift.grotesk(14)).hoehe(20).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 8) {
                Button("Eintragen") { antworte(frage, "ja"); z.auswahl = nil }.buttonStyle(SnTafelKnopf(groesse: 14))
                Button("Nein") { antworte(frage, "nein"); z.auswahl = nil }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 14))
            }
            .padding(.top, 16)
        }
    }
}

struct SnKalenderEcht: View {
    let modell: AppModell
    @ObservedObject var store: SenecaStore

    var body: some View {
        if let s = store.stand {
            SnKalenderTafel(stand: s, handeln: { store.handle($0, ziel: $1, wert: $2) }, antworte: { store.antworte(frage: $0, wahl: $1) },
                            zumChat: { text in
                                if route.seite != .chat { modell.zeigeGespraechSeite() }
                                if let text { store.chat.setzeEntwurf(text, fuer: modell.gegenueber.partner); modell.chatEntwurfNeuLaden?() }
                            },
                            rechneWeg: { await SnWeg.gemeinsam.rechne($0, fussBisMin: s.regeln?["weg_zu_fuss_bis_min"] ?? 20) })
        } else {
            SnHeuteSkelett()
        }
    }

    private var route: Route { modell.route }
}

struct SnKalKnopf: ButtonStyle {
    var voll: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Schrift.grotesk(14, .medium)).foregroundStyle(voll ? Color.white : TafelFarbe.zweit)
            .padding(.horizontal, 15).frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(voll ? (configuration.isPressed ? 0.16 : 0.10) : 0)))
            .contentShape(Capsule())
    }
}

struct SnKalBlock: View {
    var b: SenecaStand.KalBlock
    var hoehe: CGFloat
    var gewaehlt = false

    static func farbe(_ art: String) -> Color {
        art.hasPrefix("bewegung") ? TafelFarbe.gruen : art == "fenster" || art == "zugleich" ? TafelFarbe.bernstein : TafelFarbe.himmel
    }

    @ViewBuilder static func grund<S: InsettableShape>(_ art: String, _ form: S, laeuft: Bool = false, gewaehlt: Bool = false) -> some View {
        let gestrichelt = StrokeStyle(lineWidth: 1, dash: [3, 2])
        switch art {
        case "seneca", "todos", "vorschlag":
            let rand: Double = laeuft ? 0.7 : art == "vorschlag" ? 0.45 : 0.55
            form.fill(TafelFarbe.himmel.opacity(laeuft ? 0.10 : art == "vorschlag" ? 0 : 0.05)).overlay(form.strokeBorder(TafelFarbe.himmel.opacity(rand), style: gestrichelt))
        case "bewegung_vorschlag":
            form.fill(TafelFarbe.gruen.opacity(0.05)).overlay(form.strokeBorder(TafelFarbe.gruen.opacity(0.6), style: gestrichelt))
        case "fenster":
            form.fill(TafelFarbe.bernstein.opacity(0.12)).overlay(form.strokeBorder(TafelFarbe.bernstein.opacity(0.55), lineWidth: 1))
        default:
            let f = farbe(art)
            form.fill(art == "zugleich" ? f.opacity(0.10) : art == "bewegung" ? f.opacity(0.12) : f.opacity(gewaehlt ? 0.3 : 0.16))
                .overlay(alignment: .leading) { Rectangle().fill(f).frame(width: 2) }
                .clipShape(form)
        }
    }

    private var titelFarbe: Color { (b.art == "seneca" && b.laeuft != true) || b.art == "vorschlag" ? TafelFarbe.akzent : Color.white }
    private var unterFarbe: Color {
        switch b.art {
        case "zugleich": TafelFarbe.hex(0xF3D58E)
        case "seneca": b.laeuft == true ? TafelFarbe.akzent : TafelFarbe.leise
        case "todos", "vorschlag": TafelFarbe.leise
        default: b.unter?.hasSuffix(" km") == true ? TafelFarbe.leise : TafelFarbe.zweit
        }
    }

    var body: some View {
        let form = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Self.grund(b.art, form, laeuft: b.laeuft == true, gewaehlt: gewaehlt).overlay(alignment: .topLeading) { inhalt }
            .overlay { if gewaehlt { form.strokeBorder(Color.white, lineWidth: 1.5) } }
            .shadow(color: .black.opacity(gewaehlt ? 0.35 : 0), radius: 12, y: 10)
            .contentShape(form)
            .accessibilityElement(children: .combine)
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(b.titel.replacingOccurrences(of: " + ", with: "\u{00A0}+ ")).font(Schrift.grotesk(12)).lineHeight(.exact(points: 16)).foregroundStyle(titelFarbe)
                .lineLimit(hoehe >= 40 ? 2 : 1).fixedSize(horizontal: !b.titel.contains(" "), vertical: hoehe >= 40)
            if let u = b.unter, hoehe >= 40 { Text(u).font(Schrift.mono(10)).foregroundStyle(unterFarbe).lineLimit(1).frame(height: 20, alignment: .bottom).padding(.top, -1) }
        }
        .padding(.horizontal, 8).padding(.vertical, hoehe <= 26 ? 4 : hoehe <= 32 ? 6 : 5)
    }
}

struct SnKalNeu: View {
    var e: KalEntwurf
    var k: SenecaStand.Kalender
    var stand: SenecaStand
    var fokus: FocusState<Bool>.Binding
    var eintragen: () -> Void
    var abbrechen: () -> Void
    var rechneWeg: (String) async -> KalWeg?
    @ObservedObject var z = SnKalZustand.gemeinsam
    @State private var rechnet = false

    private typealias L = KalenderLogik

    private func feld(_ pfad: WritableKeyPath<KalEntwurf, String>) -> Binding<String> {
        Binding(get: { z.entwurf?[keyPath: pfad] ?? "" }, set: {
            if pfad == \KalEntwurf.ort, $0 != z.entwurf?.ort { z.entwurf?.weg = nil }
            z.entwurf?[keyPath: pfad] = $0
        })
    }

    private func zeile<V: View>(_ name: String, @ViewBuilder _ inhalt: () -> V) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name).font(Schrift.mono(11)).kerning(0.8).lineHeight(.exact(points: 20)).foregroundStyle(TafelFarbe.leise).frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) { inhalt() }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private var bloecke: [SenecaStand.KalBlock] { k.tage.first { L.gleicherTag($0.tag, e.start) }?.bloecke ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(e.uid == nil ? "NEUER TERMIN" : "TERMIN ÄNDERN").font(Schrift.mono(12)).kerning(1.4).foregroundStyle(TafelFarbe.zweit)
            TextField("", text: feld(\.titel), prompt: Text("Was steht an?").foregroundStyle(TafelFarbe.aus))
                .textFieldStyle(.plain).font(Schrift.grotesk(20)).foregroundStyle(Color.white).focused(fokus)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TafelFarbe.himmel.opacity(0.5), lineWidth: 1))
                .onSubmit(eintragen)
                .padding(.top, 12).padding(.bottom, 6)
            Text(L.zeitZeile(e.start, e.ende)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(.bottom, 14)
            zeile("WO") {
                TextField("", text: feld(\.ort), prompt: Text("Ort").foregroundStyle(TafelFarbe.aus)).textFieldStyle(.plain)
                    .font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(Color.white).onSubmit(eintragen)
                if let w = e.weg { Text(L.wegZeile(w)).font(Schrift.grotesk(12)).lineHeight(.exact(points: 17)).foregroundStyle(TafelFarbe.leise) }
                else if rechnet { Text("Seneca rechnet den Weg …").font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
            }
            zeile("KALENDER") {
                Menu {
                    ForEach(k.kalender, id: \.self) { n in Button(n) { z.entwurf?.kalender = n } }
                } label: { Text("\(e.kalender) ").font(Schrift.grotesk(14)) + Text("▾").font(Schrift.grotesk(9)) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).foregroundStyle(Color.white).fixedSize().disabled(e.uid != nil)
            }
            if let r = L.erinnerung(e, vorMin: stand.regeln?["weg_erinnern_vor_min"] ?? 6) {
                zeile("ERINNERUNG") {
                    Text(r.zeile).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(Color.white)
                    Text(r.unter).font(Schrift.grotesk(12)).lineHeight(.exact(points: 17)).foregroundStyle(TafelFarbe.leise)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                SnKugel(groesse: 10, atmet: false).padding(.top, 4)
                Text(L.danach(e, bloecke: bloecke)).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            HStack(spacing: 8) {
                Button("Eintragen", action: eintragen).buttonStyle(SnKalWeissKnopf()).disabled(e.titel.isEmpty).keyboardShortcut(.defaultAction)
                Text("ENTER").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                Spacer()
                Button("Abbrechen", action: abbrechen).buttonStyle(SnKalKnopf(voll: false)).keyboardShortcut(.cancelAction)
                Text("ESC").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
            }
            .padding(.top, 18)
            Text("ZIEHEN RASTET IN VIERTELSTUNDEN · MIT OPTION IN 5 MIN").font(Schrift.mono(11)).lineHeight(.exact(points: 17)).foregroundStyle(TafelFarbe.aus)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
        }
        .task(id: e.ort) {
            guard !e.ort.isEmpty, e.weg == nil else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            rechnet = true
            let w = await rechneWeg(e.ort)
            rechnet = false
            if z.entwurf?.ort == e.ort { z.entwurf?.weg = w }
        }
    }
}

struct SnKalWeissKnopf: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Schrift.grotesk(14, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
            .padding(.horizontal, 15).frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.85 : 1)))
    }
}

@MainActor
enum SnKalenderTasten {
    static func taste(_ e: NSEvent, _ zeichen: String) -> Bool {
        let z = SnKalZustand.gemeinsam
        if e.keyCode == 53 {
            if z.entwurf != nil { z.entwurf = nil; return true }
            if z.auswahl != nil { z.auswahl = nil; return true }
            return false
        }
        guard z.entwurf == nil else { return false }
        if e.keyCode == 123 || e.keyCode == 124 { z.blaettere?(e.keyCode == 123 ? -1 : 1); return true }
        switch zeichen {
        case "t": z.woche = nil; z.tag = nil
        case "d": z.ansicht = .tag
        case "w": z.ansicht = .woche
        case "m": z.ansicht = .monat
        default: return false
        }
        return true
    }
}

@MainActor
enum SnKalenderBild {
    static func zeige(_ seite: String, _ s: SenecaStand) {
        let z = SnKalZustand.gemeinsam
        guard let heute = s.kalender?.tage.first(where: { KalenderLogik.gleicherTag($0.tag, s.jetzt) })?.tag else { return }
        if seite == "kalender-detail" { z.auswahl = s.kalender?.tage.flatMap(\.bloecke).first { $0.detail?.seneca != nil }?.id }
        if seite == "kalender-neu" {
            let start = heute + (24 + 13) * 3_600_000
            z.entwurf = KalEntwurf(titel: "Friseur", start: start, ende: start + 3_600_000, ort: "Salon am Markt", kalender: s.kalender?.standard ?? "Privat", weg: KalWeg(m: 2300, min: 9, art: "rad"))
        }
    }
}
