import SwiftUI
import WidgetKit

enum WidgetFarbe {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255).opacity(a)
    }
    static let leise = hex(0x939EAD), zweit = hex(0xBAC1CB), aus = hex(0x6B7686), bernstein = hex(0xE8B84B), gruen = hex(0x6BD98F)
    static let himmel = hex(0x8FB6E3), jetzt = hex(0xF07A5F)
    static let grund = LinearGradient(colors: [hex(0x17345F), hex(0x0C2246)], startPoint: .top, endPoint: .bottom)
}

struct WidgetFace: View {
    enum Art { case klein, mittel, zeile, rechteck, kreis }
    var lage: WidgetLage?
    var jetzt: Date
    var art: Art

    var body: some View {
        if let l = lage {
            let z = WidgetLogik.zustand(l, jetzt)
            Group {
                switch art {
                case .klein: klein(l, z)
                case .mittel: mittel(l, z)
                case .zeile: Text(WidgetLogik.zeile(l, jetzt))
                case .rechteck: rechteck(l, z)
                case .kreis: kreis(l, z)
                }
            }
            .widgetURL(WidgetLogik.ziel(l, jetzt))
        } else {
            Text("Öffne Seneca einmal.").font(.custom("SpaceGrotesk-Regular", size: 13)).foregroundStyle(WidgetFarbe.zweit)
        }
    }

    private func g(_ s: CGFloat, _ m: Bool = false) -> Font { .custom(m ? "SpaceGrotesk-Medium" : "SpaceGrotesk-Regular", size: s) }
    private func mono(_ s: CGFloat) -> Font { .custom("IBMPlexMono-Medium", size: s) }

    private func kopf(_ z: WidgetZustand, _ l: WidgetLage, _ text: String) -> some View {
        HStack(spacing: 5) {
            switch z {
            case .fokus: Image(systemName: "circle.lefthalf.filled").font(.system(size: 9))
            case .frage: Circle().fill(WidgetFarbe.bernstein).frame(width: 6, height: 6)
            case .alt: Circle().strokeBorder(WidgetFarbe.leise, lineWidth: 1.2).frame(width: 7, height: 7)
            case .ruhig: EmptyView()
            }
            Text(text).font(mono(10)).tracking(0.8)
        }
        .foregroundStyle(z == .frage ? WidgetFarbe.bernstein : WidgetFarbe.leise)
    }

    private func punktZeile(_ farbe: Color, _ text: String) -> some View {
        HStack(spacing: 6) { Circle().fill(farbe).frame(width: 5, height: 5); Text(text).font(g(11)).foregroundStyle(WidgetFarbe.zweit) }
    }

    @ViewBuilder private func klein(_ l: WidgetLage, _ z: WidgetZustand) -> some View {
        let n = WidgetLogik.naechste(l, jetzt).first
        VStack(alignment: .leading, spacing: 0) {
            switch z {
            case .ruhig:
                kopf(z, l, "ALS NÄCHSTES")
                if let n {
                    Text(WidgetLogik.uhr(n.von)).font(g(30, true)).foregroundStyle(.white).padding(.top, 6)
                    Text(n.titel).font(g(14, true)).foregroundStyle(.white).lineLimit(2).padding(.top, 2)
                    if let u = n.unter { Text(u).font(g(11)).foregroundStyle(WidgetFarbe.zweit).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if l.wartend > 0 { punktZeile(WidgetFarbe.bernstein, "\(WidgetLogik.fragen(l.wartend)) \(l.wartend == 1 ? "wartet" : "warten")") }
            case .fokus:
                kopf(z, l, "FOKUS")
                Text("Fokus bis \(WidgetLogik.stundeWort(l.fokusBis ?? jetzt)).").font(.custom("InstrumentSerif-Regular", size: 26)).foregroundStyle(.white).lineLimit(2).padding(.top, 4)
                Text("noch \(WidgetLogik.minuten(jetzt, l.fokusBis ?? jetzt)) Min").font(g(11)).foregroundStyle(WidgetFarbe.zweit).padding(.top, 6)
                balken(l).padding(.top, 8)
                Spacer(minLength: 0)
                if !l.fragen.isEmpty { punktZeile(WidgetFarbe.bernstein, "danach \(WidgetLogik.fragen(l.fragen.count))") }
            case .frage:
                kopf(z, l, "BRAUCHT DICH")
                Text(l.fragen[0].kurz).font(g(15, true)).foregroundStyle(.white).lineLimit(3).padding(.top, 8)
                Text([l.fragen[0].von, l.fragen[0].seit.map { "seit \(WidgetLogik.uhr($0))" }].compactMap { $0 }.joined(separator: " · ")).font(g(11)).foregroundStyle(WidgetFarbe.zweit).padding(.top, 4)
                Spacer(minLength: 0)
                if l.fragen.count > 1 { Text("und \(l.fragen.count - 1) weitere").font(g(11)).foregroundStyle(WidgetFarbe.zweit) }
            case .alt:
                kopf(z, l, "STAND \(WidgetLogik.uhr(l.stand))")
                if let n {
                    Text(WidgetLogik.uhr(n.von)).font(g(30, true)).foregroundStyle(.white.opacity(0.7)).padding(.top, 6)
                    Text(n.titel).font(g(13, true)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).padding(.top, 2)
                }
                Text("Mac antwortet nicht. Fragen siehst du erst danach.").font(g(10)).foregroundStyle(WidgetFarbe.leise).padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func balken(_ l: WidgetLage) -> some View {
        let von = l.fokusVon ?? jetzt, bis = l.fokusBis ?? jetzt
        let p = bis > von ? min(1, max(0, jetzt.timeIntervalSince(von) / bis.timeIntervalSince(von))) : 0
        return GeometryReader { r in
            ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.15)); Capsule().fill(.white.opacity(0.9)).frame(width: r.size.width * p) }
        }
        .frame(height: 3)
    }

    private func band(_ l: WidgetLage, _ z: WidgetZustand) -> some View {
        GeometryReader { r in
            let cal = Calendar.current, start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: jetzt) ?? jetzt
            let x = { (d: Date) in r.size.width * min(1, max(0, d.timeIntervalSince(start) / (15 * 3600))) }
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                ForEach(Array(l.termine.enumerated()), id: \.offset) { _, t in
                    Capsule().fill(farbe(t.art)).frame(width: max(5, x(t.bis) - x(t.von)), height: 5).offset(x: x(t.von))
                }
                Rectangle().fill(WidgetFarbe.jetzt).frame(width: 1.5, height: 11).offset(x: x(jetzt))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .opacity(z == .alt ? 0.6 : 1)
    }

    private func farbe(_ art: String) -> Color {
        switch art {
        case "bewegung": return WidgetFarbe.gruen.opacity(0.8)
        case "fokus": return WidgetFarbe.himmel.opacity(0.7)
        case "fenster": return WidgetFarbe.bernstein.opacity(0.8)
        case "termin": return .white.opacity(0.85)
        default: return .white.opacity(0.3)
        }
    }

    @ViewBuilder private func mittel(_ l: WidgetLage, _ z: WidgetZustand) -> some View {
        let naechste = WidgetLogik.naechste(l, jetzt)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                switch z {
                case .ruhig: kopf(z, l, WidgetLogik.tag(jetzt).uppercased())
                case .fokus: kopf(z, l, "FOKUS BIS \(WidgetLogik.uhr(l.fokusBis ?? jetzt))")
                case .frage: kopf(z, l, WidgetLogik.fragen(l.fragen.count).uppercased())
                case .alt: kopf(z, l, "STAND \(WidgetLogik.uhr(l.stand))")
                }
                Spacer()
                Group {
                    switch z {
                    case .ruhig: Text(l.bodyBattery.map { "Body Battery \($0)" } ?? "")
                    case .fokus: Text("noch \(WidgetLogik.minuten(jetzt, l.fokusBis ?? jetzt)) Min")
                    case .frage: Text(WidgetLogik.uhr(jetzt))
                    case .alt: Text("seit \(WidgetLogik.minuten(l.stand, jetzt)) Min")
                    }
                }
                .font(g(11)).foregroundStyle(WidgetFarbe.zweit)
            }
            if z != .frage { band(l, z).padding(.top, 6) }
            HStack(alignment: .top, spacing: 14) {
                switch z {
                case .ruhig, .alt:
                    VStack(alignment: .leading, spacing: 2) {
                        if let n = naechste.first {
                            Text(WidgetLogik.uhr(n.von)).font(g(22, true)).foregroundStyle(.white.opacity(z == .alt ? 0.75 : 1))
                            Text(n.titel).font(g(13, true)).foregroundStyle(.white).lineLimit(1)
                            if z == .ruhig { Text("in \(WidgetLogik.minuten(jetzt, n.von)) Min").font(g(11)).foregroundStyle(WidgetFarbe.zweit) }
                        }
                    }
                    .frame(width: 110, alignment: .leading)
                    if z == .ruhig {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(naechste.dropFirst().prefix(3).enumerated()), id: \.offset) { _, t in
                                HStack(spacing: 12) { Text(WidgetLogik.uhr(t.von)).foregroundStyle(WidgetFarbe.zweit); Text(t.titel).foregroundStyle(.white).lineLimit(1) }
                            }
                        }
                        .font(g(11))
                    } else {
                        Text("Termine stimmen, sie kommen vom iPhone. Fragen und Team zeigt das Widget erst wieder mit dem Mac.").font(g(10.5)).foregroundStyle(WidgetFarbe.zweit)
                    }
                case .fokus:
                    Text(l.danach ?? "").font(.custom("InstrumentSerif-Regular", size: 20)).foregroundStyle(.white).lineLimit(3).frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if !l.fragen.isEmpty { punktZeile(WidgetFarbe.bernstein, "\(WidgetLogik.fragen(l.fragen.count)) warten") }
                        if let t = l.team { punktZeile(WidgetFarbe.gruen, t) }
                        if let n = naechste.first(where: { $0.von >= (l.fokusBis ?? jetzt) }) {
                            HStack(spacing: 12) { Text(WidgetLogik.uhr(n.von)).foregroundStyle(WidgetFarbe.zweit); Text(WidgetLogik.kurzName(n)).foregroundStyle(.white) }.font(g(11)).padding(.leading, 11)
                        }
                    }
                case .frage:
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(l.fragen.prefix(3).enumerated()), id: \.offset) { _, f in
                            HStack { Text(f.kurz).font(g(12.5, true)).foregroundStyle(.white).lineLimit(1); Spacer(); Text(f.frist.map { _ in "Frist morgen" } ?? f.von).font(g(11.5)).foregroundStyle(WidgetFarbe.zweit) }
                        }
                        Text("Tippen öffnet Entscheiden").font(g(10)).foregroundStyle(WidgetFarbe.leise).padding(.top, 4)
                    }
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func rechteck(_ l: WidgetLage, _ z: WidgetZustand) -> some View {
        let n = WidgetLogik.naechste(l, jetzt).first
        VStack(alignment: .leading, spacing: 1) {
            switch z {
            case .ruhig:
                Text(n.map { "\(WidgetLogik.uhr($0.von)) \(WidgetLogik.kurzName($0))" } ?? "Frei").font(.system(size: 15, weight: .semibold))
                if let n { Text("\(n.titel.split(separator: " ").first ?? "") · in \(WidgetLogik.minuten(jetzt, n.von)) Min") }
            case .fokus:
                Label("Fokus bis \(WidgetLogik.uhr(l.fokusBis ?? jetzt))", systemImage: "circle.lefthalf.filled").font(.system(size: 15, weight: .semibold))
                if !l.fragen.isEmpty { Text("danach \(WidgetLogik.fragen(l.fragen.count))") }
            case .frage:
                Text(l.fragen[0].kurz.split(separator: " ").first.map { "\($0)?" } ?? "").font(.system(size: 15, weight: .semibold))
                Text(l.fragen[0].von + (l.fragen.count > 1 ? " · und \(l.fragen.count - 1) weitere" : ""))
            case .alt:
                Text(n.map { "\(WidgetLogik.uhr($0.von)) \(WidgetLogik.kurzName($0))" } ?? "").font(.system(size: 15, weight: .semibold))
                Text("Stand \(WidgetLogik.uhr(l.stand))")
            }
        }
        .font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func kreis(_ l: WidgetLage, _ z: WidgetZustand) -> some View {
        switch z {
        case .fokus:
            let von = l.fokusVon ?? jetzt, bis = l.fokusBis ?? jetzt
            Gauge(value: bis > von ? min(1, max(0, jetzt.timeIntervalSince(von) / bis.timeIntervalSince(von))) : 0) { EmptyView() } currentValueLabel: { Text(WidgetLogik.uhr(bis)).font(.system(size: 10)) }
                .gaugeStyle(.accessoryCircularCapacity)
        case .alt:
            VStack(spacing: 0) { Text("–").font(.headline); Text(WidgetLogik.uhr(l.stand)).font(.system(size: 9)) }
        case .ruhig, .frage:
            let n = z == .frage ? l.fragen.count : l.wartend
            VStack(spacing: 0) { Text("\(n)").font(.headline); Text(n == 1 ? "Frage" : "Fragen").font(.system(size: 9)) }
        }
    }
}
