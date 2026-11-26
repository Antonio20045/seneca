import SwiftUI

struct SnKalZeitraster: View {
    @ObservedObject var k: SnKalenderSpeicher
    let tage: [Date]

    static let h: CGFloat = 52
    static let rand: CGFloat = 56

    private struct Zug: Equatable {
        enum Art { case schieben, laenge }
        var e: KalEreignis
        var art: Art
        var tag: Int
        var von: Double
        var bis: Double
        var dx: CGFloat = 0
        var dy: CGFloat = 0
    }

    private struct Teil: Identifiable {
        var id: String
        var e: KalEreignis
        var tag: Int
        var von: Double
        var bis: Double
        var lage: KalLage
    }

    @State private var zug: Zug?
    @State private var neuZug: (tag: Int, a: Double, b: Double)?
    @State private var gerollt = false
    @State private var amEndeBis: Date?

    var body: some View {
        let liste = k.anzeige
        let balken = KalRaster.balken(liste, tage: tage, k.cal)
        VStack(spacing: 0) {
            kopfzeile
            if !balken.isEmpty { balkenleiste(balken, liste) }
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.top, 8)
            GeometryReader { aussen in
                ScrollViewReader { rolle in
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            stundenSpalte
                            GeometryReader { g in flaeche(liste, breite: g.size.width) }
                        }
                        .frame(height: 24 * Self.h)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: aussen.size.height) { _, _ in
                        if let bis = amEndeBis, Date() < bis { rolle.scrollTo("stunde-23", anchor: .bottom) }
                    }
                    .onAppear {
                        guard !gerollt else { return }
                        gerollt = true
                        let erste = KalRaster.ersteStunde(liste, tage: tage, jetzt: k.jetzt, sichtbar: Double(aussen.size.height / Self.h), k.cal)
                        let luft = 12 / max(1, aussen.size.height - Self.h)
                        let sichtbar = Double(aussen.size.height / Self.h)
                        if erste >= 24 - min(24, sichtbar) - 0.01, erste > 0 {
                            rolle.scrollTo("stunde-23", anchor: .bottom)
                            amEndeBis = Date().addingTimeInterval(4)
                        } else {
                            rolle.scrollTo("stunde-\(Int(erste.rounded(.down)))", anchor: UnitPoint(x: 0.5, y: min(0.5, luft)))
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "kalraster")
    }

    private var kopfzeile: some View {
        let heute = k.cal.startOfDay(for: k.jetzt)
        return HStack(spacing: 0) {
            Color.clear.frame(width: Self.rand, height: 1)
            ForEach(Array(tage.enumerated()), id: \.element) { _, d in
                let ist = d == heute
                let nummer = k.cal.component(.day, from: d)
                Button { k.zeigeTag(d) } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text(KalRaster.wochentageKurz[KalRaster.wochentag(d, k.cal)]).font(Schrift.grotesk(13)).foregroundStyle(ist ? Farbe.himmel : Farbe.ink3)
                        Text("\(nummer)").font(Schrift.grotesk(16, .medium))
                            .foregroundStyle(ist ? Farbe.aufWeiss : Color.white)
                            .frame(minWidth: 28, minHeight: 28)
                            .background(Circle().fill(ist ? Farbe.himmel : .clear))
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(tage.count > 1)
                .accessibilityLabel("\(KalRaster.wochentageLang[KalRaster.wochentag(d, k.cal)]), \(nummer). \(KalRaster.monate[k.cal.component(.month, from: d) - 1])" + (ist ? ", heute" : ""))
            }
        }
        .frame(height: 30)
        .id(tage[0]).transition(.opacity)
    }

    private func balkenleiste(_ balken: [KalBalken], _ liste: [KalEreignis]) -> some View {
        let zeilen = (balken.map(\.zeile).max() ?? 0) + 1
        let nach = Dictionary(liste.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return HStack(alignment: .top, spacing: 0) {
            Text("ganztägig").font(Schrift.grotesk(10)).foregroundStyle(Farbe.ink3).fixedSize()
                .frame(width: Self.rand - 6, height: 20, alignment: .trailing).padding(.trailing, 6)
            GeometryReader { g in
                let spalte = g.size.width / CGFloat(tage.count)
                ZStack(alignment: .topLeading) {
                    ForEach(balken) { b in
                        if let e = nach[b.id] {
                            SnKalBalkenView(e: e, an: k.offenId == e.id, davor: b.davor, danach: b.danach) { k.oeffne(e) }
                                .frame(width: max(8, spalte * CGFloat(b.bis - b.von + 1) - 4), height: 20)
                                .offset(x: spalte * CGFloat(b.von) + 2, y: CGFloat(b.zeile) * 23)
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(zeilen) * 23 - 3)
        .padding(.top, 8)
        .id(tage[0]).transition(.opacity)
    }

    private var stundenSpalte: some View {
        let heuteDa = tage.contains(k.cal.startOfDay(for: k.jetzt))
        let jetzt = KalRaster.stunde(k.jetzt, k.cal)
        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { s in
                    Text(s == 0 ? "" : String(format: "%02d:00", s)).font(Schrift.mono(10.5)).foregroundStyle(Farbe.ink3)
                        .opacity(heuteDa && abs(Double(s) - jetzt) < 0.3 ? 0 : 1)
                        .offset(y: -7)
                        .frame(width: Self.rand - 12, height: Self.h, alignment: .topTrailing)
                        .id("stunde-\(s)")
                }
            }
            if heuteDa {
                Text(KalRaster.uhr(jetzt)).font(Schrift.mono(10.5)).foregroundStyle(Farbe.koralle)
                    .offset(y: CGFloat(jetzt) * Self.h - 7)
                    .frame(width: Self.rand - 12, alignment: .trailing)
            }
        }
        .frame(width: Self.rand, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func teile(_ liste: [KalEreignis]) -> [Teil] {
        var out: [Teil] = []
        for (i, d) in tage.enumerated() {
            let st = liste.compactMap { e in KalRaster.stueck(e, tag: d, k.cal).map { (e, $0) } }
            let lage = KalRaster.spuren(st.map(\.1))
            for (e, s) in st { out.append(Teil(id: "\(e.id)#\(i)", e: e, tag: i, von: s.von, bis: s.bis, lage: lage[e.id] ?? KalLage(spur: 0, anzahl: 1))) }
        }
        return out
    }

    private func flaeche(_ liste: [KalEreignis], breite: CGFloat) -> some View {
        let h = Self.h
        let spalte = breite / CGFloat(tage.count)
        let heute = k.cal.startOfDay(for: k.jetzt)
        let jetzt = KalRaster.stunde(k.jetzt, k.cal)
        let schub = CGFloat(k.richtung) * 22
        return ZStack(alignment: .topLeading) {
            ForEach(0..<25, id: \.self) { s in
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: breite, height: 1).offset(y: CGFloat(s) * h)
            }
            ForEach(1..<max(1, tage.count), id: \.self) { i in
                Rectangle().fill(Color.white.opacity(0.04)).frame(width: 1, height: 24 * h).offset(x: CGFloat(i) * spalte)
            }
            Color.clear.frame(width: breite, height: 24 * h).contentShape(Rectangle())
                .gesture(anlegen(spalte))
                .accessibilityHidden(true)
            ZStack(alignment: .topLeading) {
                if let i = tage.firstIndex(of: heute) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Farbe.himmel.opacity(0.05))
                        .frame(width: spalte, height: 24 * h).offset(x: CGFloat(i) * spalte).allowsHitTesting(false)
                }
                ForEach(teile(liste)) { t in kachel(t, spalte: spalte, heute: tage[t.tag] == heute, jetzt: jetzt) }
                if let i = tage.firstIndex(of: heute) {
                    HStack(spacing: 0) {
                        Circle().fill(Farbe.koralle).frame(width: 7, height: 7)
                        Rectangle().fill(Farbe.koralle).frame(height: 1.5)
                    }
                    .frame(width: spalte + 3).offset(x: CGFloat(i) * spalte - 3.5, y: CGFloat(jetzt) * h - 3.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(width: breite, height: 24 * h, alignment: .topLeading)
            .id(tage[0])
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: schub)), removal: .opacity))
            if let n = neuZug {
                let r = KalRaster.neu(tag: tage[n.tag], von: n.a, bis: n.b, k.cal)
                let von = KalRaster.stunde(r.start, k.cal), bis = r.ende > r.start && KalRaster.stunde(r.ende, k.cal) == 0 ? 24 : KalRaster.stunde(r.ende, k.cal)
                geist(titel: "Neuer Termin", von: von, bis: bis, farbe: Farbe.himmel)
                    .frame(width: spalte - 4, height: max(18, CGFloat(bis - von) * h - 2))
                    .offset(x: CGFloat(n.tag) * spalte + 2, y: CGFloat(von) * h + 1)
            }
            if let z = zug, z.dx != 0 || z.dy != 0 {
                let p = ziel(z, spalte: spalte)
                geist(titel: z.e.titel, von: p.von, bis: p.bis, farbe: .kal(z.e.farbe))
                    .frame(width: spalte - 4, height: max(18, CGFloat(p.bis - p.von) * h - 2))
                    .offset(x: CGFloat(p.tag) * spalte + 2, y: CGFloat(p.von) * h + 1)
            }
        }
        .frame(width: breite, height: 24 * h, alignment: .topLeading)
    }

    private func kachel(_ t: Teil, spalte: CGFloat, heute: Bool, jetzt: Double) -> some View {
        let h = Self.h
        let b = (spalte - 4) / CGFloat(t.lage.anzahl)
        let hoehe = max(18, CGFloat(t.bis - t.von) * h - 2)
        let gezogen = zug?.e.id == t.e.id && (zug?.dx != 0 || zug?.dy != 0)
        return SnKalKachel(e: t.e, zeit: zeitText(t), hoehe: hoehe, schmal: b < 90, an: k.offenId == t.e.id,
                           entwurf: t.e.id == SnKalenderSpeicher.entwurfId, matt: heute && t.bis <= jetzt)
            .frame(width: b - 2, height: hoehe)
            .contentShape(Rectangle())
            .onTapGesture { k.oeffne(t.e) }
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("kalraster"))
                .onChanged { v in
                    guard t.e.aenderbar else { return }
                    zug = Zug(e: t.e, art: .schieben, tag: t.tag, von: t.von, bis: t.bis, dx: v.translation.width, dy: v.translation.height)
                }
                .onEnded { _ in lasseLos(spalte) })
            .overlay(alignment: .bottom) {
                if t.e.aenderbar, t.e.id != SnKalenderSpeicher.entwurfId {
                    Color.clear.frame(height: 7).contentShape(Rectangle())
                        .onHover { drin in if drin { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("kalraster"))
                            .onChanged { v in zug = Zug(e: t.e, art: .laenge, tag: t.tag, von: t.von, bis: t.bis, dx: 0, dy: v.translation.height) }
                            .onEnded { _ in lasseLos(spalte) })
                }
            }
            .opacity(gezogen ? 0.35 : 1)
            .offset(x: CGFloat(t.tag) * spalte + 2 + b * CGFloat(t.lage.spur), y: CGFloat(t.von) * h + 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(t.e.titel), \(zeitText(t))")
            .accessibilityAddTraits(.isButton)
    }

    private func zeitText(_ t: Teil) -> String { "\(KalRaster.uhr(t.e.start, k.cal)) – \(KalRaster.uhr(t.e.ende, k.cal))" }

    private func geist(titel: String, von: Double, bis: Double, farbe: Color) -> some View {
        let form = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(titel).font(Schrift.grotesk(12, .medium)).foregroundStyle(Color.white).lineLimit(1)
            Text("\(KalRaster.uhr(von)) – \(KalRaster.uhr(bis))").font(Schrift.mono(10)).foregroundStyle(Farbe.ink2).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(form.fill(farbe.opacity(0.30)))
        .overlay(form.strokeBorder(farbe, lineWidth: 1.5))
        .clipShape(form)
        .allowsHitTesting(false)
    }

    private func ziel(_ z: Zug, spalte: CGFloat) -> (tag: Int, von: Double, bis: Double) {
        let dh = Double(z.dy / Self.h)
        switch z.art {
        case .schieben:
            let tag = min(tage.count - 1, max(0, z.tag + Int((z.dx / spalte).rounded())))
            let dauer = z.bis - z.von
            let von = min(24 - min(dauer, 0.25), max(0, KalRaster.raste(z.von + dh)))
            return (tag, von, min(24, von + dauer))
        case .laenge:
            return (z.tag, z.von, max(z.von + 0.25, KalRaster.raste(z.bis + dh)))
        }
    }

    private func lasseLos(_ spalte: CGFloat) {
        guard let z = zug else { return }
        zug = nil
        let p = ziel(z, spalte: spalte)
        switch z.art {
        case .schieben:
            let tag = k.cal.date(byAdding: .day, value: p.tag - z.tag, to: k.cal.startOfDay(for: z.e.start))!
            let stunde = min(23.75, max(0, KalRaster.stunde(z.e.start, k.cal) + (p.von - z.von)))
            let r = KalRaster.verschoben(z.e, auf: tag, stunde: stunde, k.cal)
            k.setzeZeit(z.e, start: r.start, ende: r.ende)
        case .laenge:
            k.setzeZeit(z.e, start: z.e.start, ende: KalRaster.verlaengert(z.e, tag: tage[z.tag], bis: p.bis, k.cal))
        }
    }

    private func anlegen(_ spalte: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard abs(v.translation.height) > 5, k.entwurf == nil else { return }
                let i = min(tage.count - 1, max(0, Int(v.startLocation.x / spalte)))
                neuZug = (i, Double(v.startLocation.y / Self.h), Double(v.location.y / Self.h))
            }
            .onEnded { v in
                let gezogen = neuZug
                neuZug = nil
                if k.entwurf != nil || k.sprungOffen {
                    withAnimation(Kurve.sn(0.18)) { k.sprungOffen = false }
                    k.schliesse()
                    return
                }
                let i = min(tage.count - 1, max(0, Int(v.startLocation.x / spalte)))
                let r = KalRaster.neu(tag: tage[i], von: gezogen?.a ?? Double(v.startLocation.y / Self.h), bis: gezogen?.b, k.cal)
                k.neu(start: r.start, ende: r.ende)
            }
    }
}

struct SnKalKachel: View {
    let e: KalEreignis
    let zeit: String
    let hoehe: CGFloat
    var schmal = false
    var an = false
    var entwurf = false
    var matt = false

    var body: some View {
        let farbe = Color.kal(e.farbe)
        let form = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let titel = Text(e.titel).font(Schrift.grotesk(12, .medium)).foregroundStyle(Color.white)
        Group {
            if hoehe < 34 {
                HStack(spacing: 6) {
                    titel.lineLimit(1)
                    if !schmal { Text(zeit.prefix(5)).font(Schrift.mono(10)).foregroundStyle(Farbe.ink2).lineLimit(1).fixedSize() }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    titel.lineLimit(hoehe >= 70 ? 2 : 1).lineHeight(.exact(points: 15))
                    Text(schmal ? String(zeit.prefix(5)) : zeit).font(Schrift.mono(10)).foregroundStyle(Farbe.ink2).lineLimit(1)
                    if hoehe >= 86, let o = e.ort { Text(o).font(Schrift.grotesk(11)).foregroundStyle(Farbe.ink3).lineLimit(1) }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .background(form.fill(farbe.opacity(entwurf ? 0.14 : (an ? 0.34 : 0.22))))
        .overlay(alignment: .leading) { Rectangle().fill(farbe).frame(width: 3) }
        .overlay { if an || entwurf { form.strokeBorder(farbe, lineWidth: 1.5) } }
        .clipShape(form)
        .opacity(matt && !an ? 0.55 : 1)
        .help("\(zeit)  \(e.titel)")
    }
}

struct SnKalBalkenView: View {
    let e: KalEreignis
    var an = false
    var davor = false
    var danach = false
    let aktion: () -> Void

    var body: some View {
        let farbe = Color.kal(e.farbe)
        let form = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: aktion) {
            HStack(spacing: 4) {
                if davor { Image(systemName: "chevron.left").font(.system(size: 8, weight: .bold)).foregroundStyle(Farbe.ink2) }
                Text(e.titel).font(Schrift.grotesk(12, .medium)).foregroundStyle(Color.white).lineLimit(1)
                Spacer(minLength: 0)
                if danach { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Farbe.ink2) }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(form.fill(farbe.opacity(an ? 0.42 : 0.28)))
            .overlay { if an { form.strokeBorder(farbe, lineWidth: 1.5) } }
            .contentShape(form)
        }
        .buttonStyle(.plain)
        .help(e.titel)
    }
}
