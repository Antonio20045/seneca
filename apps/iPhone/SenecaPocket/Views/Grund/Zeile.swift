import SwiftUI

struct Zeile: View {
    enum Vorn {
        case keins
        case haken(an: Bool, umschalten: () -> Void)
        case punkt(Color)
        case zeit(String)
    }

    enum Hinten {
        case keins
        case text(String)
        case pfeil
    }

    var vorn: Vorn = .keins
    var titel: String
    var unter: String?
    var hinten: Hinten = .keins
    var betont = false
    var leise = false
    var linie = true
    var aktion: (() -> Void)?

    init(vorn: Vorn = .keins, titel: String, unter: String? = nil, hinten: Hinten = .keins,
         betont: Bool = false, leise: Bool = false, linie: Bool = true, aktion: (() -> Void)? = nil) {
        self.vorn = vorn; self.titel = titel; self.unter = unter; self.hinten = hinten
        self.betont = betont; self.leise = leise; self.linie = linie; self.aktion = aktion
    }

    private var vornBreite: CGFloat {
        switch vorn {
        case .keins: 0
        case .haken: 22
        case .punkt: 8
        case .zeit: 40
        }
    }
    private var vornAbstand: CGFloat {
        switch vorn {
        case .keins: 0
        case .punkt, .zeit: Stil.abstand.m
        default: Stil.abstand.l
        }
    }
    private var erledigt: Bool {
        if case .haken(let an, _) = vorn { return an }
        return false
    }

    @Environment(\.displayScale) private var pixel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            vornTeil
                .frame(width: vornBreite, alignment: .leading)
                .padding(.trailing, vornAbstand)
            if let aktion {
                Button(action: aktion) { textTeil }
                    .buttonStyle(ZeilenStil())
            } else {
                textTeil
            }
        }
        .padding(.vertical, Stil.abstand.l)
        .frame(minHeight: Stil.zeilenHoehe)
        .overlay(alignment: .bottom) {
            if linie {
                Rectangle()
                    .fill(Stil.tinte.linie)
                    .frame(height: 1 / max(pixel, 1))
                    .padding(.leading, vornBreite + vornAbstand)
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Stil.radius.mittel).inset(by: -Stil.abstand.s))
        .bewegt(.klein, wert: erledigt)
    }

    private var textTeil: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                Text(titel)
                    .schrift(betont ? .zeileWichtig : .zeile)
                    .strikethrough(erledigt, color: Stil.tinte.leise)
                    .foregroundStyle(erledigt || leise ? Stil.tinte.zweit : Stil.tinte.voll)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let unter, !unter.isEmpty {
                    Text(unter)
                        .schrift(.klein)
                        .foregroundStyle(Stil.tinte.zweit)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            hintenTeil
        }
        .padding(.vertical, Stil.abstand.l)
        .contentShape(Rectangle())
        .padding(.vertical, -Stil.abstand.l)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var vornTeil: some View {
        switch vorn {
        case .keins:
            EmptyView()
        case .haken(let an, let umschalten):
            Button {
                if !an { Haptik.erledigt() } else { Haptik.auswahl() }
                umschalten()
            } label: {
                HakenKreis(an: an)
                    .padding(Stil.abstand.m)
                    .contentShape(Rectangle())
                    .padding(-Stil.abstand.m)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(an ? "Erledigt, zurücknehmen" : "Abhaken")
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        case .punkt(let farbe):
            Circle().fill(farbe).frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        case .zeit(let zeit):
            Text(zeit)
                .schrift(.klein)
                .monospacedDigit()
                .foregroundStyle(Stil.tinte.zweit)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder private var hintenTeil: some View {
        switch hinten {
        case .keins:
            EmptyView()
        case .text(let t):
            Text(t)
                .schrift(.klein)
                .monospacedDigit()
                .foregroundStyle(Stil.tinte.leise)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, Stil.abstand.m)
        case .pfeil:
            Image(systemName: "chevron.right")
                .font(Stil.symbol(.klein, gewicht: .medium))
                .foregroundStyle(Stil.tinte.leise)
                .padding(.leading, Stil.abstand.m)
                .accessibilityHidden(true)
        }
    }
}

private struct ZeilenStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .bewegt(.klein, wert: configuration.isPressed)
    }
}

struct HakenKreis: View {
    var an: Bool
    var groesse: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduziert

    var body: some View {
        let k = groesse / 22
        ZStack {
            Circle().fill(an ? Stil.tinte.voll : .clear)
            Circle().strokeBorder(an ? .clear : Stil.tinte.zweit, lineWidth: 1.4 * k)
            HakenForm()
                .trim(from: 0, to: an ? 1 : 0)
                .stroke(Stil.farbe.aufHell, style: StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round))
                .animation(reduziert ? nil : (an ? Bewegung.wechsel.kurve.delay(0.05) : Bewegung.klein.kurve), value: an)
        }
        .frame(width: groesse, height: groesse)
        .bewegt(.klein, wert: an)
        .accessibilityHidden(true)
    }
}

struct HakenForm: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 22
        var p = Path()
        p.move(to: CGPoint(x: 6.6 * k, y: 11.4 * k))
        p.addLine(to: CGPoint(x: 9.6 * k, y: 14.3 * k))
        p.addLine(to: CGPoint(x: 15.4 * k, y: 8.2 * k))
        return p
    }
}
