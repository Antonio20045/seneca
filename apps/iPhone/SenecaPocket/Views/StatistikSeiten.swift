import SwiftUI

struct StatZahl: View {
    var zahl: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(zahl.first ?? "").font(Sundartha.grotesk(26, .medium)).tracking(-0.4).monospacedDigit().foregroundStyle(.white)
                Text(zahl.dropFirst().first ?? "").mono(11).foregroundStyle(TafelFarbe.leise)
            }
            .fixedSize()
            Text(zahl.last ?? "").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
        }
    }
}

struct StatZeile: View {
    var links: String
    var wert: String
    var unter = ""
    var rechts = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(links).mono(11).foregroundStyle(TafelFarbe.leise).frame(width: 88, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(wert).font(Sundartha.grotesk(15)).monospacedDigit().foregroundStyle(.white)
                if !unter.isEmpty { Text(unter).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !rechts.isEmpty { Text(rechts).mono(11).foregroundStyle(TafelFarbe.gruen) }
        }
        .frame(minHeight: 46)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

struct StatUeberschrift: View {
    var text: String
    var body: some View { Text(text).mono(11, abstand: 1.1).fontWeight(.medium).foregroundStyle(TafelFarbe.leise) }
}

struct StatHinweis: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SenecaPunkt().padding(.top, 5)
            Text(text).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24).padding(.bottom, 30)
    }
}

struct StatRaster: View {
    var raster: [[String]]
    var namen: [String]
    var feld: CGFloat = 9
    var abstand: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: abstand) {
            ForEach(Array(raster.enumerated()), id: \.offset) { i, zeile in
                HStack(spacing: abstand) {
                    if !namen.isEmpty {
                        Text(i < namen.count ? namen[i] : "").mono(10).foregroundStyle(TafelFarbe.aus).frame(width: 12, height: feld, alignment: .leading)
                        Color.clear.frame(width: 4, height: feld)
                    }
                    ForEach(Array(zeile.enumerated()), id: \.offset) { _, z in zelle(z) }
                }
            }
        }
    }

    private func zelle(_ z: String) -> some View {
        let farbe: Color = z.hasSuffix("2") ? TafelFarbe.gruen : z.hasSuffix("1") ? TafelFarbe.gruen.opacity(0.45) : z == " " ? Color.white.opacity(0.04) : z.isEmpty ? .clear : Color.white.opacity(0.07)
        return RoundedRectangle(cornerRadius: feld > 12 ? 6 : 2).fill(farbe).frame(width: feld, height: feld)
            .overlay { if z.hasPrefix("h") { RoundedRectangle(cornerRadius: feld > 12 ? 7.5 : 3.5).stroke(Color.white, lineWidth: 1.5).padding(-0.75) } }
    }
}

struct StatLegende: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(TafelFarbe.gruen.opacity(0.45)).frame(width: 9, height: 9)
            Text("LAUFEN ODER KRAFT")
            RoundedRectangle(cornerRadius: 2).fill(TafelFarbe.gruen).frame(width: 9, height: 9).padding(.leading, 8)
            Text("BEIDES ODER LANG")
        }
        .mono(11).foregroundStyle(TafelFarbe.aus)
    }
}

struct JahrSicht: View {
    var j: SenecaStatistik.Raster
    var breite: CGFloat
    var monat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TafelSatz(vor: j.satz.first ?? "", akzent: j.satz.dropFirst().joined(separator: " "), groesse: 30, hoehe: 1.1).padding(.top, 14).padding(.bottom, 16)
            if monat {
                HStack(spacing: 6) { ForEach(Array(["M", "D", "M", "D", "F", "S", "S"].enumerated()), id: \.offset) { _, t in Text(t).mono(11).foregroundStyle(TafelFarbe.aus).frame(width: (breite - 36) / 7) } }
                    .padding(.bottom, 6)
                StatRaster(raster: j.raster, namen: [], feld: (breite - 36) / 7, abstand: 6)
            } else {
                StatRaster(raster: j.raster, namen: ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"], feld: (breite - 20 - 60) / 31)
            }
            StatLegende().padding(.top, 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .leading), GridItem(.flexible(), spacing: 20, alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(Array(j.zahlen.enumerated()), id: \.offset) { _, z in StatZahl(zahl: z) }
            }
            .padding(.top, 18)
            if let b = j.bestwerte, !b.isEmpty {
                StatUeberschrift(text: "BESTWERTE \(Calendar.current.component(.year, from: Date()))").padding(.top, 16).padding(.bottom, 2)
                ForEach(Array(b.enumerated()), id: \.offset) { _, z in
                    HStack(spacing: 12) {
                        Text(z.first ?? "").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                        Text(z.count > 1 ? z[1] : "").font(Sundartha.grotesk(14)).monospacedDigit().foregroundStyle(.white)
                        Text(z.last ?? "").mono(11).foregroundStyle(TafelFarbe.leise).frame(width: 70, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                }
            }
        }
    }
}

struct StatStellKarte: View {
    var titel: String
    var rechts = ""
    @Binding var wert: Double
    var einheit: String
    var schritt: Double
    var unten: String?
    var schliessen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(titel).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.zweit)
                Spacer()
                Text(rechts).font(.custom("IBMPlexMono-Regular", fixedSize: 10.5)).foregroundStyle(TafelFarbe.leise)
            }
            .contentShape(Rectangle()).onTapGesture(perform: schliessen)
            HStack(spacing: 10) {
                if unten != nil { knopf("−", -schritt) }
                TextField("", value: $wert, format: .number.precision(.fractionLength(schritt < 1 ? 1 : 0)).locale(Locale(identifier: "de_DE")))
                    .font(Sundartha.grotesk(30, .medium)).foregroundStyle(.white).keyboardType(.decimalPad).fixedSize()
                Text(einheit).mono(11).foregroundStyle(TafelFarbe.leise)
                if unten == nil { Spacer(); knopf("−", -schritt) }
                knopf("+", schritt)
            }
            .padding(.top, unten == nil ? 8 : 6)
            if let unten { Text(unten).font(Sundartha.grotesk(11)).foregroundStyle(TafelFarbe.leise).padding(.top, 8) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [TafelFarbe.hex(0x153A6E), TafelFarbe.hex(0x0A2148)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .padding(.vertical, 6)
    }

    private func knopf(_ zeichen: String, _ d: Double) -> some View {
        Button { wert = max(0, ((wert + d) / schritt).rounded() * schritt) } label: {
            Text(zeichen).font(Sundartha.grotesk(12, .medium)).foregroundStyle(.white).padding(.horizontal, 11).frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.1))).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TagSicht: View {
    var t: SenecaStatistik.TagSicht
    var aendern: (String, [String: JSONWert]) -> Void
    var loeschen: (String, Bool) -> Void
    @State private var offen: Int?
    @State private var neu = 0.0
    @State private var neuWerte: [String: String] = [:]
    @State private var weg: (id: String, satz: String, marke: UUID)?
    @State private var fort = Set<String>()
    @State private var zug: [Int: CGFloat] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TafelSatz(vor: t.satz.first ?? "", akzent: t.satz.dropFirst().joined(separator: " "), groesse: 30, hoehe: 1.1).padding(.top, 14).padding(.bottom, 16)
            ForEach(Array(t.zeilen.enumerated()), id: \.offset) { i, z in
                let id = z.count > 3 ? z[3] : "", wert = neuWerte[id] ?? z[2]
                if !fort.contains(id) {
                    if offen == i, let a = TagSicht.art(wert) {
                        StatStellKarte(titel: "\(z[1]) · \(tagName)", rechts: "VORHER \(z[2].split(separator: " ")[0])", wert: $neu, einheit: a.einheit, schritt: a.schritt, unten: nil) { schliessen(i) }
                    } else {
                        StatZeile(links: z[0], wert: z[1], unter: wert)
                            .opacity(weg?.id == id ? 0.35 : 1)
                            .offset(x: min(0, zug[i] ?? 0))
                            .contentShape(Rectangle())
                            .onTapGesture { if !id.isEmpty, weg == nil, let a = TagSicht.art(wert) { if let o = offen { schliessen(o) }; neu = a.zahl; offen = i } }
                            .simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { v in if !id.isEmpty, abs(v.translation.width) > abs(v.translation.height) { zug[i] = v.translation.width } }
                                .onEnded { v in
                                    Bewegung.mit(.wechsel) { zug[i] = 0 }
                                    if !id.isEmpty, v.translation.width < -80 { loesche(id, "\(z[1]), \(wert) am \(tagName), gelöscht.") }
                                })
                    }
                    if let w = weg, w.id == id {
                        TafelRueck(satz: w.satz, dauer: 5) { loeschen(id, false); Bewegung.mit(.wechsel) { weg = nil } }.padding(.horizontal, -16).padding(.vertical, 6)
                    }
                }
            }
        }
        #if DEBUG
        .onAppear(perform: demo)
        #endif
    }

    #if DEBUG
    private func demo() {
        switch ProcessInfo.processInfo.environment["SENECA_DEMO_STAT_STELL"] {
        case "korrektur": neu = 81.6; offen = 0
        case "loeschen": if let z = t.zeilen.first { loesche(z[3], "\(z[1]), \(z[2]) am \(tagName), gelöscht.") }
        default: break
        }
    }
    #endif

    private var tagName: String { String(t.kopf.split(separator: ",").first ?? "") }

    static func art(_ wert: String) -> (zahl: Double, einheit: String, feld: String, schritt: Double)? {
        let teile = wert.split(separator: " ")
        guard teile.count == 2, let z = Double(teile[0].replacingOccurrences(of: ",", with: ".")) else { return nil }
        switch teile[1] {
        case "kg": return (z, "KG", "kg", 0.1)
        case "km": return (z, "KM", "km", 0.1)
        case "Min": return (z, "MIN", "m", 1)
        default: return nil
        }
    }

    private func schliessen(_ i: Int) {
        let z = t.zeilen[i]
        offen = nil
        guard let a = TagSicht.art(neuWerte[z[3]] ?? z[2]), neu != a.zahl else { return }
        neuWerte[z[3]] = "\(neu.formatted(.number.precision(.fractionLength(a.schritt < 1 ? 1 : 0)).locale(Locale(identifier: "de_DE")))) \(z[2].split(separator: " ")[1])"
        aendern(z[3], [a.feld: .zahl(neu)])
    }

    private func loesche(_ id: String, _ satz: String) {
        let marke = UUID()
        loeschen(id, true)
        Bewegung.mit(.wechsel) { weg = (id, satz, marke) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 5))
            if weg?.marke == marke { Bewegung.mit(.wechsel) { weg = nil; fort.insert(id) } }
        }
    }
}

struct KraftTafel: View {
    var u: SenecaStatistik.Uebung
    var zurueck: () -> Void
    @State private var jahr = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: zurueck) { Text("‹ Statistik").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.akzent).frame(height: 20) }.buttonStyle(.plain)
                    Text("KRAFTTRAINING · ÜBUNG").mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.top, 18)
                    TafelSatz(vor: u.titel, akzent: u.satz).padding(.top, 6).padding(.bottom, 4)
                    TafelReiter(auswahl: $jahr, optionen: [(false, "8 Wochen"), (true, "Jahr")]).padding(.top, 4)
                    KraftKurve(punkte: jahr ? u.wochen : Array(u.wochen.suffix(8)), jahr: jahr).frame(height: 168).padding(.top, 14)
                    Text("Bester Satz je Woche · Gewicht und Wiederholungen").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(u.zeilen.enumerated()), id: \.offset) { _, z in StatZeile(links: z.links, wert: z.wert, unter: z.unter, rechts: z.bestwert ? "BESTWERT" : "") }
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 120)
            }
            if let h = u.hinweis { StatHinweis(text: h) }
        }
        .accessibilityAction(.escape, zurueck)
    }
}

struct KraftKurve: View {
    var punkte: [SenecaStatistik.Punkt]
    var jahr: Bool

    var body: some View {
        GeometryReader { g in
            let werte = punkte.compactMap(\.kg), hi = werte.max() ?? 1, lo = min(werte.min() ?? 0, hi - 0.5)
            let x = { (i: Int) in 8 + (g.size.width - 16) * CGFloat(i) / CGFloat(max(1, punkte.count - 1)) }
            let y = { (kg: Double) in 42.3 + CGFloat((hi - kg) / (hi - lo)) * 76.3 }
            let stufen = stride(from: (lo / 5).rounded(.up) * 5, through: hi, by: 5).map { $0 }
            ZStack(alignment: .topLeading) {
                ForEach(stufen, id: \.self) { kg in
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).offset(y: y(kg))
                    Text("\(Int(kg)) kg").mono(10).foregroundStyle(TafelFarbe.aus).offset(y: y(kg) - 16)
                }
                let teile = abschnitte()
                ForEach(Array(teile.enumerated()), id: \.offset) { _, t in
                    Path { p in
                        p.move(to: CGPoint(x: x(t[0]), y: 144))
                        for i in t { p.addLine(to: CGPoint(x: x(i), y: y(punkte[i].kg ?? 0))) }
                        p.addLine(to: CGPoint(x: x(t.last ?? 0), y: 144))
                    }
                    .fill(LinearGradient(colors: [TafelFarbe.gruen.opacity(0.22), TafelFarbe.gruen.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in for (n, i) in t.enumerated() { let q = CGPoint(x: x(i), y: y(punkte[i].kg ?? 0)); n == 0 ? p.move(to: q) : p.addLine(to: q) } }
                        .stroke(TafelFarbe.gruen, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
                ForEach(Array(punkte.enumerated()), id: \.offset) { i, p in
                    let letzter = i == punkte.count - 1
                    if let kg = p.kg {
                        Circle().fill(letzter ? TafelFarbe.gruen : TafelFarbe.hex(0x0B2147)).overlay(Circle().stroke(TafelFarbe.gruen, lineWidth: 1.5))
                            .frame(width: letzter ? 9 : 6, height: letzter ? 9 : 6).position(x: x(i), y: y(kg))
                        if !jahr || letzter {
                            Text("×\(p.wdh ?? 0)").font(Sundartha.grotesk(10)).foregroundStyle(letzter ? .white : TafelFarbe.zweit).position(x: x(i), y: y(kg) - 12)
                        }
                    }
                    if !jahr || (i > 0 && punkte[i - 1].monat != p.monat) {
                        Text(jahr ? p.monat : p.w).mono(10).foregroundStyle(letzter ? .white : TafelFarbe.aus).position(x: x(i), y: 158)
                    }
                }
            }
        }
    }

    private func abschnitte() -> [[Int]] {
        var teile: [[Int]] = [[]]
        for (i, p) in punkte.enumerated() { if p.kg == nil { teile.append([]) } else { teile[teile.count - 1].append(i) } }
        return teile.filter { !$0.isEmpty }
    }
}

struct LesenTafel: View {
    var b: SenecaStatistik.Buch
    var zurueck: () -> Void
    var uhr: () -> Void
    var notiz: (String, String) -> Void
    @State private var schreiben = false
    @State private var text = ""
    @State private var seite = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: zurueck) { Text("‹ Statistik").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.akzent).frame(height: 20) }.buttonStyle(.plain)
                    Text(b.kopf).mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.top, 18)
                    (Text(b.titel + " ").font(Sundartha.serif(34, italic: true)).foregroundColor(TafelFarbe.akzent) + Text(b.satz).font(Sundartha.serif(34)).foregroundColor(.white))
                        .zeilenHoehe(36, schrift: 34).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 6).padding(.bottom, 14)
                    if let s = b.seite, let a = b.anteil {
                        HStack { Text(s); Spacer(); Text(b.prozent ?? "") }.mono(11).foregroundStyle(TafelFarbe.leise)
                        Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                            .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(TafelFarbe.akzent).frame(width: g.size.width * a, height: 6) } }
                            .padding(.top, 8)
                    }
                    if let p = b.prognose { Text(p).font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(19, schrift: 13).padding(.top, 10) }
                    HStack(alignment: .top, spacing: 12) { ForEach(Array(b.zahlen.enumerated()), id: \.offset) { _, z in StatZahl(zahl: z).frame(maxWidth: .infinity, alignment: .leading) } }
                        .padding(.top, 16)
                    StatUeberschrift(text: "ZULETZT").padding(.top, 16).padding(.bottom, 4)
                    ForEach(Array(b.zuletzt.enumerated()), id: \.offset) { _, z in StatZeile(links: z.links, wert: z.wert, unter: z.unter) }
                    if let n = b.notiz {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(n.kopf).mono(11).foregroundStyle(TafelFarbe.leise)
                            Text(n.text).font(Sundartha.serif(19, italic: true)).foregroundStyle(.white).zeilenHoehe(24, schrift: 19)
                        }
                        .padding(.vertical, 14).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 120)
            }
            HStack(spacing: 10) {
                knopf("Timer an der Uhr", uhr)
                knopf("+ Notiz") { schreiben = true }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .alert("Notiz", isPresented: $schreiben) {
            TextField("Seite", text: $seite).keyboardType(.numberPad)
            TextField("Notiz", text: $text)
            Button("Merken") { if !text.isEmpty { notiz(text, seite) }; text = ""; seite = "" }
            Button("Abbrechen", role: .cancel) {}
        }
        .accessibilityAction(.escape, zurueck)
    }

    private func knopf(_ t: String, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            Text(t).font(Sundartha.grotesk(15, .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 44)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
