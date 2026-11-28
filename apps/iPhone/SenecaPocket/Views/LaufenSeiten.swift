import MapKit
import SwiftUI

struct LaufenBereich: View {
    @ObservedObject var model: StatistikModel
    var zurueck: () -> Void
    var oeffnen: (String) -> Void

    enum Ansicht { case start, alle }
    @State private var ansicht = Ansicht.start
    @State private var offen: String?

    var body: some View {
        ZStack {
            LaufenStart(daten: model.laufDaten, planKm: planKm, zurueck: zurueck, alle: { wechsel { ansicht = .alle } }, oeffnen: oeffne)
            if ansicht == .alle {
                AlleLaeufe(liste: model.laufDaten?.kennzahlen?.lauf.liste ?? [], zurueck: { wechsel { ansicht = .start } }, oeffnen: oeffne)
                    .background(TafelGrund()).transition(.move(edge: .trailing))
            }
            if let id = offen {
                LaufEinzelTafel(lauf: model.einzel?.lauf.id == id ? model.einzel?.lauf : nil, spur: model.einzel?.lauf.id == id ? model.einzel?.spur : nil,
                                daten: model.laufDaten, id: id, zurueck: ansicht == .alle ? "Alle Läufe" : "Laufen") { wechsel { offen = nil } }
                    .background(TafelGrund()).transition(.move(edge: .trailing))
            }
        }
        #if DEBUG
        .task {
            let env = ProcessInfo.processInfo.environment
            if env["SENECA_DEMO_LAUF"] == "alle" { ansicht = .alle }
            if env["SENECA_DEMO_LAUF"] == "einzel", let id = model.laufDaten?.kennzahlen?.lauf.liste?.first?.id { oeffne(id) }
        }
        #endif
    }

    private var planKm: Double? {
        model.daten?.woche.karten.first { $0.art == "laufen" }.flatMap { k in (k.rechts + " " + k.einheit).firstMatch(of: /VON (\d+)/).flatMap { Double($0.1) } }
            ?? model.laufDaten?.kennzahlen?.lauf.aufbau.first?.last?.d
    }

    private func oeffne(_ id: String) {
        oeffnen(id)
        wechsel { offen = id }
    }

    private func wechsel(_ a: () -> Void) { Bewegung.mit(.wechsel, a) }
}

struct LaufTitel: View {
    var text: String
    var rechts: String = ""
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(text).font(Sundartha.grotesk(15, .medium)).foregroundStyle(.white)
            Spacer()
            Text(rechts).mono(11).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.top, 26).padding(.bottom, 10)
    }
}

struct LaufZurueck: View {
    var text: String
    var tun: () -> Void
    var body: some View {
        Button(action: tun) { Text("‹ \(text)").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(height: 32) }.buttonStyle(.plain)
    }
}

struct StreckenForm: View {
    var form: [[Double]]
    var farbe = TafelFarbe.himmel
    var breite: CGFloat = 2

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) / 100, dx = (g.size.width - 100 * s) / 2, dy = (g.size.height - 100 * s) / 2
            let p = form.filter { $0.count == 2 }.map { CGPoint(x: dx + $0[0] * s, y: dy + $0[1] * s) }
            ZStack {
                Path { pfad in pfad.addLines(p) }.stroke(farbe, style: StrokeStyle(lineWidth: breite, lineCap: .round, lineJoin: .round))
                if let a = p.first { Circle().fill(TafelFarbe.gruen).frame(width: 6, height: 6).position(a) }
            }
        }
    }
}

struct LaufenStart: View {
    var daten: LaufDaten?
    var planKm: Double?
    var zurueck: () -> Void
    var alle: () -> Void
    var oeffnen: (String) -> Void

    private var k: LaufDaten.Lauf? { daten?.kennzahlen?.lauf }
    private var liste: [LaufDaten.Zeile] { k?.liste ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LaufZurueck(text: "Statistik", tun: zurueck)
                Text("LAUFEN · " + LaufRechnen.datum(Date(), "'WOCHE' w").uppercased()).mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.top, 10)
                let satz = LaufRechnen.satzStart(liste, planKm: planKm, jetzt: Date())
                TafelSatz(vor: satz.0, akzent: satz.1).padding(.top, 8).padding(.bottom, 4)
                if k == nil {
                    Text("Die Laufdaten kommen mit dem nächsten Abgleich vom Server.").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.leise).padding(.top, 20)
                } else {
                    woche
                    naechster
                    letzte
                    trends
                }
                Button(action: alle) {
                    HStack {
                        Text("Alle Läufe").font(Sundartha.grotesk(15, .medium)).foregroundStyle(.white)
                        Spacer()
                        Text("\(liste.count) ›").mono(12).foregroundStyle(TafelFarbe.leise)
                    }
                    .frame(height: 54).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
                .padding(.top, 26)
                .accessibilityIdentifier("alle-laeufe")
            }
            .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private var woche: some View {
        let w = LaufRechnen.woche(liste, jetzt: Date())
        return VStack(alignment: .leading, spacing: 10) {
            LaufTitel(text: "Diese Woche", rechts: planKm.map { "PLAN \(LaufRechnen.zahl($0, 0)) KM" } ?? "")
            HStack(alignment: .top, spacing: 8) {
                wert(LaufRechnen.zahl(w.km), planKm.map { "von \(LaufRechnen.zahl($0, 0)) km" } ?? "km")
                wert("\(w.laeufe)", w.laeufe == 1 ? "Lauf" : "Läufe")
                wert(LaufRechnen.dauer(w.s), "Zeit")
            }
            Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(TafelFarbe.gruen).frame(width: g.size.width * min(1, w.km / max(1, planKm ?? 1)), height: 3) }
                }
                .padding(.top, 4)
        }
    }

    private func wert(_ a: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(a).font(Sundartha.grotesk(26, .medium)).monospacedDigit().foregroundStyle(.white)
            Text(b).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var naechster: some View {
        let n = k?.naechster, tag = n?.datum.flatMap { ISO8601DateFormatter.tag.date(from: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            LaufTitel(text: "Nächster Lauf", rechts: tag.map { LaufRechnen.datum($0, "EEEE, d. MMM").uppercased() } ?? "")
            if let name = n?.name {
                Text(name).font(Sundartha.serif(22, italic: true)).foregroundStyle(TafelFarbe.akzent)
                if let b = n?.beschreibung { Text(b).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text("Der Trainer hat noch keinen Lauf eingeplant.").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.leise)
            }
        }
    }

    private var letzte: some View {
        VStack(alignment: .leading, spacing: 0) {
            LaufTitel(text: "Letzte Läufe", rechts: "WISCHEN")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(liste.prefix(12)) { l in
                        Button { oeffnen(l.id) } label: { karte(l) }.buttonStyle(.plain).accessibilityIdentifier("lauf-\(l.id)")
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)
            .accessibilityIdentifier("letzte-laeufe")
        }
    }

    private func karte(_ l: LaufDaten.Zeile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.18))
                if let f = l.form { StreckenForm(form: f).padding(12) } else { Text("ohne Strecke").mono(10).foregroundStyle(TafelFarbe.aus) }
            }
            .frame(height: 92)
            Text(LaufRechnen.kurz(l.datum)).mono(10).foregroundStyle(TafelFarbe.leise).padding(.top, 4)
            Text("\(LaufRechnen.zahl(l.km, 2)) km").font(Sundartha.grotesk(20, .medium)).monospacedDigit().foregroundStyle(.white)
            Text("\(LaufRechnen.pace(l.pace)) pro km").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
        }
        .padding(10)
        .frame(width: 148)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var trends: some View {
        let monate = k?.pace_monat ?? []
        let effizienz = monate.compactMap { $0.count > 2 ? $0[2].d : nil }
        let mitPuls = effizienz.count >= 2
        let pace = mitPuls ? effizienz.map { 60000 / ($0 * 140) } : monate.compactMap { $0.count > 1 ? $0[1].d : nil }
        let km = Array((k?.km ?? []).suffix(12))
        return VStack(alignment: .leading, spacing: 0) {
            LaufTitel(text: "Trends", rechts: "12 MONATE · 12 WOCHEN")
            HStack(alignment: .top, spacing: 12) {
                trendKarte(mitPuls ? "Pace bei Puls 140" : "Pace je Monat", LaufRechnen.pace(pace.last), mitPuls ? "schneller ist oben" : "Puls fehlt noch, darum Pace allein") {
                    GeometryReader { g in
                        let lo = pace.min() ?? 0, hi = pace.max() ?? 1, n = max(1, pace.count - 1)
                        Path { p in p.addLines(pace.enumerated().map { CGPoint(x: g.size.width * CGFloat($0.offset) / CGFloat(n), y: hi > lo ? g.size.height * CGFloat(($0.element - lo) / (hi - lo)) : g.size.height / 2) }) }
                            .stroke(TafelFarbe.himmel, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    }
                }
                trendKarte("Wochenumfang", "\(LaufRechnen.zahl(km.last ?? 0)) km", "diese Woche") {
                    GeometryReader { g in
                        let hi = max(1, km.max() ?? 1)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(km.enumerated()), id: \.offset) { i, v in
                                RoundedRectangle(cornerRadius: 1.5).fill(i == km.count - 1 ? Color.white : TafelFarbe.himmel.opacity(0.55))
                                    .frame(height: max(2, g.size.height * CGFloat(v / hi)))
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
        }
    }

    private func trendKarte<Inhalt: View>(_ titel: String, _ wert: String, _ unter: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.zweit)
            Text(wert).font(Sundartha.grotesk(20, .medium)).monospacedDigit().foregroundStyle(.white)
            inhalt().frame(height: 40).padding(.vertical, 6)
            Text(unter).mono(10).foregroundStyle(TafelFarbe.aus).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }
}

extension ISO8601DateFormatter {
    static let tag: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

struct AlleLaeufe: View {
    var liste: [LaufDaten.Zeile]
    var zurueck: () -> Void
    var oeffnen: (String) -> Void

    private var monate: [(id: String, name: String, laeufe: [LaufDaten.Zeile])] {
        var m: [(id: String, name: String, laeufe: [LaufDaten.Zeile])] = []
        for l in liste {
            let id = LaufRechnen.datum(l.datum, "yyyy-MM")
            if m.last?.id == id { m[m.count - 1].laeufe.append(l) } else { m.append((id, LaufRechnen.datum(l.datum, "MMMM yyyy"), [l])) }
        }
        return m
    }

    var body: some View {
        let m = monate, gesamt = liste.reduce(0) { $0 + $1.km }
        ScrollViewReader { leser in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LaufZurueck(text: "Laufen", tun: zurueck)
                    Text("LAUFEN · SEIT " + (liste.last.map { LaufRechnen.datum($0.datum, "MMM yyyy") } ?? "").uppercased()).mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.top, 10)
                    TafelSatz(vor: "\(liste.count) Läufe, \(LaufRechnen.zahl(gesamt, 0)) km.", akzent: liste.first.map { "Der letzte am \(LaufRechnen.datum($0.datum, "d. MMMM"))." } ?? "")
                        .padding(.top, 8).padding(.bottom, 16)
                    streifen(m) { id in withAnimation(Bewegung.wechsel.kurve) { leser.scrollTo(id, anchor: .top) } }
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(m, id: \.id) { monat in
                            HStack {
                                Text(monat.name.uppercased()).mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.zweit)
                                Spacer()
                                Text("\(LaufRechnen.zahl(monat.laeufe.reduce(0) { $0 + $1.km })) KM · \(monat.laeufe.count) \(monat.laeufe.count == 1 ? "LAUF" : "LÄUFE")").mono(11).foregroundStyle(TafelFarbe.leise)
                            }
                            .padding(.top, 22).padding(.bottom, 6).id(monat.id)
                            ForEach(monat.laeufe) { l in zeile(l) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func streifen(_ m: [(id: String, name: String, laeufe: [LaufDaten.Zeile])], springen: @escaping (String) -> Void) -> some View {
        let letzte = Array(m.prefix(12).reversed()), hi = max(1, letzte.map { $0.laeufe.reduce(0) { $0 + $1.km } }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(letzte, id: \.id) { monat in
                let km = monat.laeufe.reduce(0) { $0 + $1.km }
                Button { springen(monat.id) } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(TafelFarbe.himmel.opacity(0.6)).frame(height: max(3, 34 * km / hi))
                        Text(String(monat.name.prefix(1))).mono(10).foregroundStyle(TafelFarbe.leise)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54, alignment: .bottom).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
    }

    private func zeile(_ l: LaufDaten.Zeile) -> some View {
        Button { oeffnen(l.id) } label: {
            HStack(spacing: 14) {
                Text(LaufRechnen.datum(l.datum, "EEEEEE").replacingOccurrences(of: ".", with: "").uppercased() + LaufRechnen.datum(l.datum, " d.")).mono(11).foregroundStyle(TafelFarbe.leise).frame(width: 52, alignment: .leading)
                ZStack {
                    if let f = l.form { StreckenForm(form: f, breite: 1.2) } else { Circle().strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 2])) }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(LaufRechnen.zahl(l.km, 2)) km").font(Sundartha.grotesk(16, .medium)).monospacedDigit().foregroundStyle(.white)
                    Text("\(LaufRechnen.dauer(l.s)) · \(LaufRechnen.pace(l.pace)) pro km").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                }
                Spacer()
                Text("›").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.aus)
            }
            .frame(height: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}

struct LaufEinzelTafel: View {
    var lauf: SenecaStatistik.Lauf?
    var spur: LaufDaten.Spur?
    var daten: LaufDaten?
    var id: String
    var zurueck: String
    var schliessen: () -> Void

    @State private var stelle: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LaufZurueck(text: zurueck, tun: schliessen)
                if let lauf {
                    Text(lauf.kopf).mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.top, 10)
                    TafelSatz(vor: vor(lauf), akzent: lauf.satz.dropFirst().joined(separator: " ")).padding(.top, 8).padding(.bottom, 18)
                    karte
                    kern(lauf)
                    splits(lauf)
                    verlauf
                    zonen
                    vergleich
                    trainer(lauf)
                } else {
                    HeuteSkelett().frame(height: 400)
                }
            }
            .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(stelle != nil)
        .accessibilityAction(.escape, schliessen)
    }

    private func vor(_ lauf: SenecaStatistik.Lauf) -> String {
        guard lauf.satz.first == "Lauf.", let l = daten?.kennzahlen?.lauf.liste?.first(where: { $0.id == id }) else { return lauf.satz.first ?? "" }
        let h = Calendar.current.component(.hour, from: l.datum)
        return "\(LaufRechnen.zahl(l.km)) km am \(LaufRechnen.datum(l.datum, "EEEE"))\(h < 11 ? "morgen" : h < 14 ? "mittag" : h < 18 ? "nachmittag" : "abend")."
    }

    private var koordinaten: [CLLocationCoordinate2D] { LaufRechnen.koordinaten(spur?.p) }
    private var punkte: [LaufPunkt] { LaufRechnen.punkte(spur?.r ?? []) }

    @ViewBuilder private var karte: some View {
        let k = koordinaten
        if k.count > 1 {
            Map(initialPosition: .rect(MKPolyline(coordinates: k, count: k.count).boundingMapRect.insetBy(dx: -400, dy: -400)), interactionModes: []) {
                MapPolyline(coordinates: k).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Annotation("", coordinate: k[0]) { Circle().fill(TafelFarbe.gruen).frame(width: 9, height: 9) }
                if let s = stelle, let o = LaufRechnen.ort(k, anteil: s) {
                    Annotation("", coordinate: o) { Circle().fill(.white).frame(width: 12, height: 12).shadow(color: TafelFarbe.himmel, radius: 6) }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keine Strecke für diesen Lauf.").font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.zweit)
                Text(spur == nil ? "Die App hat dafür weder von Garmin noch aus Apple Health eine Strecke bekommen." : "Die Uhr oder App hat keine GPS-Punkte mitgeschickt.")
                    .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
    }

    private func kern(_ lauf: SenecaStatistik.Lauf) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3), alignment: .leading, spacing: 16) {
            ForEach(Array(lauf.werte.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.first ?? "").font(Sundartha.grotesk(22, .medium)).monospacedDigit().foregroundStyle(.white)
                    Text(w.last ?? "").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
        .padding(.top, 8)
    }

    @ViewBuilder private func splits(_ lauf: SenecaStatistik.Lauf) -> some View {
        if !lauf.km.isEmpty {
            LaufTitel(text: "Kilometer")
            VStack(spacing: 3) {
                ForEach(lauf.km, id: \.nr) { k in
                    HStack(spacing: 10) {
                        Text("\(k.nr)").mono(11).foregroundStyle(TafelFarbe.aus).frame(width: 22, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 2).fill(k.schnellste ? Color.white : TafelFarbe.himmel.opacity(0.55))
                                .frame(width: g.size.width * k.anteil, height: 4).frame(maxHeight: .infinity)
                        }
                        Text(k.zeit).mono(11).foregroundStyle(k.schnellste ? .white : TafelFarbe.leise).frame(width: 40, alignment: .trailing)
                    }
                    .frame(height: 17)
                }
            }
            if let b = lauf.bestwert {
                HStack(spacing: 8) {
                    Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
                    Text(b).font(Sundartha.grotesk(14)).foregroundStyle(.white)
                }
                .padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var verlauf: some View {
        let p = punkte
        if p.count > 3 {
            let ende = max(1, p.last?.m ?? 1)
            let hier = stelle.map { s in p.min { abs($0.m - s * ende) < abs($1.m - s * ende) } } ?? nil
            let mitPuls = p.contains { $0.puls != nil }, mitHoehe = p.contains { $0.hoehe != nil }
            LaufTitel(text: "Verlauf", rechts: hier.map { "KM " + LaufRechnen.zahl($0.m / 1000, 2) } ?? "")
            HStack(spacing: 14) {
                (Text(LaufRechnen.pace(hier?.pace)).foregroundColor(TafelFarbe.himmel) + Text(" pro km").foregroundColor(TafelFarbe.leise))
                if mitPuls { Text("\(hier?.puls.map { "\(Int($0))" } ?? "–")").foregroundColor(TafelFarbe.jetzt) + Text(" Puls").foregroundColor(TafelFarbe.leise) }
                if mitHoehe { Text("\(hier?.hoehe.map { "\(Int($0)) m" } ?? "–")").foregroundColor(.white) + Text(" Höhe").foregroundColor(TafelFarbe.leise) }
            }
            .font(Sundartha.grotesk(14, .medium)).monospacedDigit().padding(.bottom, 8)
            GeometryReader { g in
                VStack(spacing: 10) {
                    kurve("Pace", p.map { $0.pace }, farbe: TafelFarbe.himmel, umgekehrt: true, ende: ende)
                    if mitPuls { kurve("Puls", p.map { $0.puls }, farbe: TafelFarbe.jetzt, ende: ende) }
                    if mitHoehe { kurve("Höhe", p.map { $0.hoehe }, farbe: TafelFarbe.zweit, ende: ende, flaeche: true) }
                }
                .overlay(alignment: .topLeading) {
                    if let s = stelle {
                        Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1).frame(maxHeight: .infinity).offset(x: g.size.width * s)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .onChanged { stelle = min(1, max(0, $0.location.x / max(1, g.size.width))) }
                    .onEnded { _ in
                        let war = stelle
                        Task { try? await Task.sleep(for: .seconds(1.5)); if stelle == war { withAnimation(.easeOut(duration: 0.3)) { stelle = nil } } }
                    })
            }
            .frame(height: CGFloat(1 + (mitPuls ? 1 : 0) + (mitHoehe ? 1 : 0)) * 64)
            .accessibilityIdentifier("verlauf")
            Text(mitPuls ? "Mit dem Finger über die Kurve ziehen." : "Mit dem Finger über die Kurve ziehen. Für diesen Lauf gibt es keinen Puls.")
                .font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.aus).padding(.top, 8)
        } else {
            LaufTitel(text: "Verlauf")
            Text("Für diesen Lauf gibt es nur die Summen, keinen Verlauf.").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise)
        }
    }

    private func kurve(_ name: String, _ werte: [Double?], farbe: Color, umgekehrt: Bool = false, ende: Double, flaeche: Bool = false) -> some View {
        let p = punkte
        let da = werte.compactMap { $0 }.sorted()
        let lo = da.isEmpty ? 0 : da[Int(Double(da.count - 1) * 0.03)], hi = da.isEmpty ? 1 : da[Int(Double(da.count - 1) * 0.97)]
        return VStack(alignment: .leading, spacing: 2) {
            Text(name).mono(10).foregroundStyle(TafelFarbe.aus)
            GeometryReader { g in
                let punkt = { (i: Int, v: Double) -> CGPoint in
                    let t = hi > lo ? (min(hi, max(lo, v)) - lo) / (hi - lo) : 0.5
                    return CGPoint(x: g.size.width * p[i].m / ende, y: g.size.height * (umgekehrt ? t : 1 - t))
                }
                let linie = werte.enumerated().compactMap { i, v in v.map { punkt(i, $0) } }
                ZStack {
                    if flaeche {
                        Path { pfad in pfad.addLines(linie); if let l = linie.last, let a = linie.first { pfad.addLine(to: CGPoint(x: l.x, y: g.size.height)); pfad.addLine(to: CGPoint(x: a.x, y: g.size.height)) } }
                            .fill(farbe.opacity(0.18))
                    }
                    Path { pfad in pfad.addLines(linie) }.stroke(farbe, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var zonen: some View {
        LaufTitel(text: "Pulszonen")
        if let z = LaufRechnen.zonen(spur?.r ?? [], pulsMax: daten?.kennzahlen?.lauf.puls_max) {
            Text("Bezogen auf deinen höchsten gemessenen Puls: \(Int(daten?.kennzahlen?.lauf.puls_max ?? (spur?.r ?? []).compactMap { $0.count > 2 ? $0[2] : nil }.max() ?? 0))").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.aus).padding(.bottom, 6)
            let hi = max(1, z.max() ?? 1)
            VStack(spacing: 5) {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    HStack(spacing: 10) {
                        Text("Z\(i + 1)").mono(11).foregroundStyle(TafelFarbe.aus).frame(width: 22, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 2).fill(TafelFarbe.jetzt.opacity(0.35 + 0.13 * Double(i))).frame(width: max(2, g.size.width * z[i] / hi), height: 4).frame(maxHeight: .infinity)
                        }
                        Text("\(Int((z[i] / 60).rounded())) Min").mono(11).foregroundStyle(z[i] == z.max() ? .white : TafelFarbe.leise).frame(width: 52, alignment: .trailing)
                    }
                    .frame(height: 16)
                }
            }
        } else {
            Text("Ohne Puls keine Zonen. Die fenix bringt ihn mit.").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise)
        }
    }

    @ViewBuilder private var vergleich: some View {
        let a = LaufRechnen.aehnlich(daten?.kennzahlen?.lauf.liste ?? [], zu: id)
        if a.count > 1, let l = a.first {
            let schnellster = a.min { ($0.pace ?? .infinity) < ($1.pace ?? .infinity) }?.id
            LaufTitel(text: "Ähnlich lange Läufe", rechts: "\(LaufRechnen.zahl(max(0, l.km - max(1, l.km * 0.2)))) BIS \(LaufRechnen.zahl(l.km + max(1, l.km * 0.2))) KM")
            ForEach(a) { x in
                HStack(spacing: 14) {
                    Text(x.id == id ? "DIESER LAUF" : LaufRechnen.kurz(x.datum))
                        .mono(10).foregroundStyle(x.id == id ? .white : TafelFarbe.leise).frame(width: 78, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(LaufRechnen.pace(x.pace)) pro km").font(Sundartha.grotesk(16, .medium)).monospacedDigit().foregroundStyle(.white)
                        Text("\(LaufRechnen.zahl(x.km, 2)) km · \(LaufRechnen.dauer(x.s))").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                    }
                    Spacer()
                    if x.id == schnellster { Text("SCHNELLSTER").mono(10).foregroundStyle(TafelFarbe.gruen) }
                }
                .frame(height: 50)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }

    @ViewBuilder private func trainer(_ lauf: SenecaStatistik.Lauf) -> some View {
        let satz = spur?.trainer ?? LaufRechnen.befund(lauf.km.map(\.zeit))
        if let satz {
            HStack(alignment: .top, spacing: 10) {
                SenecaPunkt().padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(satz).font(Sundartha.grotesk(15)).foregroundStyle(.white).zeilenHoehe(21, schrift: 15).fixedSize(horizontal: false, vertical: true)
                    Text(spur?.trainer == nil ? "aus den Kilometerzeiten" : "Trainer").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                }
            }
            .padding(.top, 28)
        }
    }
}
