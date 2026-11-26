import SwiftUI
import UIKit

struct HeuteBild: View, Equatable {
    var strecke: TagesStrecke
    var reduceMotion: Bool
    @State private var da = false

    static func == (a: HeuteBild, b: HeuteBild) -> Bool { a.strecke == b.strecke && a.reduceMotion == b.reduceMotion }

    static let schilder = 2
    static let innen = Stil.abstand.l
    static func breite(_ m: Metrics) -> Double { Double(m.size.width - 2 * Stil.rand - 2 * innen) }
    static func messen(_ text: String) -> Double {
        let font = UIFont(name: "SpaceGrotesk-Regular", size: Stil.Schrift.klein.groesse) ?? .systemFont(ofSize: Stil.Schrift.klein.groesse)
        return Double((text as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
    }

    private let zeile: CGFloat = 18
    private let block: CGFloat = 24
    private let punktBis: CGFloat = 16
    private var mitte: CGFloat { zeile + Stil.abstand.s + block / 2 }
    private var untenY: CGFloat { mitte + block / 2 + Stil.abstand.s }
    private var hoehe: CGFloat { untenY + zeile }

    var body: some View {
        let w = CGFloat(strecke.breite)
        return ZStack(alignment: .topLeading) {
            linie(w)
            if let t = strecke.tagX { tag(CGFloat(t)) }
            ForEach(Array(strecke.bloecke.enumerated()), id: \.element.id) { i, b in blockForm(b, nr: i) }
            ForEach(Self.setzen(strecke.schilder, breite: Double(w)), id: \.id) { schild($0) }
            jetztMarke(w)
        }
        .frame(width: w, height: hoehe, alignment: .topLeading)
        .padding(Self.innen)
        .modifier(Glas())
        .onAppear {
            guard !da else { return }
            Bewegung.mit(.blatt) { da = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vorgelesen)
        .accessibilityIdentifier("heute.bild")
    }

    private var vorgelesen: String {
        let teile = strecke.bloecke.filter { !$0.leise }.map { b -> String in
            switch b.lage {
            case .war: return "\(b.titel) war um \(b.zeit)"
            case .laeuft: return "\(b.titel) läuft seit \(b.zeit)"
            case .kommt: return "\(b.titel) kommt um \(b.zeit)"
            }
        }
        return teile.isEmpty ? "Dein Tag, bisher ohne Termine." : "Dein Tag: " + teile.joined(separator: ", ") + "."
    }

    private func linie(_ w: CGFloat) -> some View {
        let jetzt = min(1, max(0, strecke.jetzt / strecke.breite)), ende = min(1, max(jetzt, strecke.ende / strecke.breite))
        let verlauf = LinearGradient(stops: [.init(color: Stil.tinte.linie, location: 0), .init(color: Stil.tinte.linie, location: jetzt),
                                             .init(color: Stil.tinte.leise, location: jetzt), .init(color: Stil.tinte.leise, location: ende),
                                             .init(color: ende < 0.97 ? .clear : Stil.tinte.leise, location: 1)],
                                     startPoint: .leading, endPoint: .trailing)
        let luecken = strecke.ausgelassen
        return Rectangle()
            .fill(verlauf)
            .frame(width: w, height: 2)
            .mask {
                Canvas { ctx, size in
                    var fest = Path(), gestrichelt = Path()
                    var x: CGFloat = 0
                    for l in luecken.sorted(by: { $0.von < $1.von }) {
                        fest.move(to: CGPoint(x: x, y: 1)); fest.addLine(to: CGPoint(x: CGFloat(l.von), y: 1))
                        gestrichelt.move(to: CGPoint(x: CGFloat(l.von) + 2, y: 1)); gestrichelt.addLine(to: CGPoint(x: CGFloat(l.bis) - 1, y: 1))
                        x = CGFloat(l.bis)
                    }
                    fest.move(to: CGPoint(x: x, y: 1)); fest.addLine(to: CGPoint(x: size.width, y: 1))
                    ctx.stroke(fest, with: .color(.black), lineWidth: 2)
                    ctx.stroke(gestrichelt, with: .color(.black), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5]))
                }
            }
            .offset(y: mitte - 1)
    }

    private func tag(_ x: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Stil.tinte.linie)
                .frame(width: 1, height: hoehe)
            Text(strecke.tagName)
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.zweit)
                .lineLimit(1)
                .fixedSize()
                .offset(x: Stil.abstand.s, y: untenY)
        }
        .offset(x: x)
        .opacity(da ? 1 : 0)
    }

    private func blockForm(_ b: TagesStrecke.Block, nr: Int) -> some View {
        let breite = CGFloat(b.breite)
        let punkt = !b.leise && breite < punktBis
        let h: CGFloat = b.leise ? 6 : (punkt ? 10 : block)
        let w: CGFloat = punkt ? 10 : breite
        let farbe: Color = b.training ? Stil.farbe.gruen : Stil.tinte.voll
        let hell: Color = b.leise ? Stil.tinte.leise : farbe
        let matt: Color = b.leise ? Stil.tinte.flaeche : Stil.tinte.flaecheStark
        let fuellung: LinearGradient = {
            switch b.lage {
            case .war: return LinearGradient(colors: [matt], startPoint: .leading, endPoint: .trailing)
            case .kommt: return LinearGradient(colors: [hell], startPoint: .leading, endPoint: .trailing)
            case .laeuft:
                let a = max(0.02, min(0.98, b.anteil))
                return LinearGradient(stops: [.init(color: Stil.tinte.leise, location: 0), .init(color: Stil.tinte.leise, location: max(0, a - 0.06)),
                                              .init(color: hell, location: min(1, a + 0.06)), .init(color: hell, location: 1)],
                                      startPoint: .leading, endPoint: .trailing)
            }
        }()
        return Capsule(style: .continuous)
            .fill(fuellung)
            .overlay {
                if b.training, !punkt, breite >= 28 {
                    Image(systemName: "figure.run").font(Stil.symbol(.klein, gewicht: .semibold))
                        .foregroundStyle(b.lage == .war ? Stil.tinte.zweit : Stil.farbe.aufHell)
                }
            }
            .frame(width: w, height: h)
            .scaleEffect(x: da ? 1 : 0.01, anchor: .leading)
            .opacity(da ? 1 : 0)
            .animation(Bewegung.blatt.kurve(reduziert: reduceMotion)?.delay(0.08 + Double(min(nr, 8)) * 0.03), value: da)
            .offset(x: CGFloat(b.x) + (punkt ? (breite - w) / 2 : 0), y: mitte - h / 2)
    }

    struct Gesetzt: Identifiable, Equatable {
        var id: String
        var x: Double
        var breite: Double
        var zeit: String
        var titel: String
        var hell: Bool
    }

    static func setzen(_ schilder: [TagesStrecke.Schild], breite w: Double) -> [Gesetzt] {
        let liste = schilder.sorted { $0.x < $1.x }
        let luft = Double(Stil.abstand.m)
        var aus: [Gesetzt] = []
        var ende = -luft
        for (i, s) in liste.enumerated() {
            let zeitBreite = messen(s.zeit)
            let ganz = messen(s.zeit + " " + s.titel)
            var x = max(s.x, ende + luft)
            let letztes = i == liste.count - 1
            if letztes, x + ganz > w { x = max(ende + luft, min(x, w - ganz)) }
            let bis = letztes ? w : max(x + zeitBreite, liste[i + 1].x - luft)
            let platz = max(zeitBreite, bis - x)
            let titel = kuerzen(s.titel, platz: platz - messen(s.zeit + " "))
            let genutzt = titel.isEmpty ? zeitBreite : min(platz, messen(s.zeit + " " + titel))
            aus.append(Gesetzt(id: s.id, x: x, breite: platz, zeit: s.zeit, titel: titel, hell: s.hell))
            ende = x + genutzt
        }
        return aus
    }

    private func schild(_ s: Gesetzt) -> some View {
        (Text(s.zeit).foregroundStyle(s.hell ? Stil.tinte.zweit : Stil.tinte.leise)
            + Text(Self.mitLeer(s.titel)).foregroundStyle(s.hell ? Stil.tinte.voll : Stil.tinte.zweit))
            .schrift(.klein)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CGFloat(s.breite) + Stil.abstand.xs, height: zeile, alignment: .bottomLeading)
            .offset(x: CGFloat(s.x))
            .opacity(da ? 1 : 0)
            .animation(Bewegung.wechsel.kurve(reduziert: reduceMotion)?.delay(0.25), value: da)
    }

    static func mitLeer(_ t: String) -> String { t.isEmpty ? "" : " " + t }

    static func kuerzen(_ titel: String, platz: Double) -> String {
        if messen(titel) <= platz { return titel }
        var worte = titel.split(separator: " ").map(String.init)
        while worte.count > 1 {
            worte.removeLast()
            let t = worte.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters) + "…"
            if messen(t) <= platz { return t }
        }
        return ""
    }

    private func jetztMarke(_ w: CGFloat) -> some View {
        let x = CGFloat(strecke.jetzt)
        let halb = CGFloat(Self.messen(strecke.jetztText)) / 2
        let textX = min(max(halb, x), w - halb)
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Stil.farbe.himmel).frame(width: 2, height: block + Stil.abstand.m).offset(x: x - 1, y: mitte - block / 2 - Stil.abstand.m / 2)
            Text(strecke.jetztText)
                .schrift(.klein)
                .monospacedDigit()
                .foregroundStyle(Stil.farbe.himmel)
                .fixedSize()
                .frame(width: halb * 2 + Stil.abstand.s)
                .offset(x: textX - halb - Stil.abstand.xs, y: untenY)
        }
        .frame(width: w, height: hoehe, alignment: .topLeading)
        .animation(reduceMotion ? nil : .linear(duration: 0.8), value: strecke.jetzt)
    }
}

private struct Glas: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: Stil.radius.gross))
        } else {
            content
                .background(Stil.tinte.flaeche, in: RoundedRectangle(cornerRadius: Stil.radius.gross, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Stil.radius.gross, style: .continuous).strokeBorder(Stil.tinte.linie, lineWidth: 1))
        }
    }
}
