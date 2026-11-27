import SwiftUI

struct Haken: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 5 * s, y: r.minY + 12.5 * s))
        p.addLine(to: CGPoint(x: r.minX + 9.5 * s, y: r.minY + 17 * s))
        p.addLine(to: CGPoint(x: r.minX + 19 * s, y: r.minY + 7.5 * s))
        return p
    }
}

extension Shape {
    func haken(_ farbe: Color, _ groesse: CGFloat) -> some View {
        stroke(farbe, style: StrokeStyle(lineWidth: 2.8 * groesse / 24, lineCap: .round, lineJoin: .round))
            .frame(width: groesse, height: groesse)
    }
}

struct TafelKopf: View {
    var links: String
    var rechts: String? = nil

    var body: some View {
        HStack {
            Text(links).mono(11, .medium, abstand: 1.1)
            Spacer(minLength: 8)
            if let rechts { Text(rechts).mono(11, .medium, abstand: 1.1) }
        }
        .foregroundStyle(TafelFarbe.leise)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TafelSatz: View {
    var vor: String
    var akzent: String
    var groesse: CGFloat = 32
    var hoehe: CGFloat = 1.08

    var body: some View {
        (Text(vor + " ").font(Sundartha.serif(groesse)).foregroundColor(.white)
            + Text(akzent).font(Sundartha.serif(groesse, italic: true)).foregroundColor(TafelFarbe.akzent))
            .zeilenHoehe(groesse * hoehe, schrift: groesse)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TafelReiter<Wert: Hashable>: View {
    @Binding var auswahl: Wert
    var optionen: [(Wert, String)]

    var body: some View {
        HStack(spacing: 24) {
            ForEach(optionen, id: \.0) { w, titel in
                Button { Bewegung.mit(.wechsel) { auswahl = w } } label: {
                    Text(titel).font(Sundartha.grotesk(15, .medium))
                        .foregroundStyle(auswahl == w ? .white : TafelFarbe.leise)
                        .frame(height: 44)
                        .overlay(alignment: .bottom) { if auswahl == w { Rectangle().fill(.white).frame(height: 1.5) } }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(auswahl == w ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

struct TafelChip: View {
    var titel: String
    var an = false
    var haken = false

    var body: some View {
        HStack(spacing: 6) {
            if haken { Haken().haken(TafelFarbe.hex(0xA8EBBE), 11) }
            Text(titel).font(Sundartha.grotesk(14))
        }
        .foregroundStyle(haken ? TafelFarbe.hex(0xA8EBBE) : TafelFarbe.text)
        .padding(.horizontal, 14).frame(height: 44)
        .background(Capsule().fill(haken ? TafelFarbe.gruen.opacity(0.14) : Color.white.opacity(0.07)))
    }
}

struct TafelWahl: View {
    var titel: String
    var an: Bool
    var geschaetzt = false

    var body: some View {
        let schrift: Color = an ? .white : geschaetzt ? TafelFarbe.akzent : TafelFarbe.text
        let flaeche: Color = an ? TafelFarbe.himmel.opacity(0.22) : geschaetzt ? .clear : Color.white.opacity(0.07)
        let kante: Color = an || geschaetzt ? TafelFarbe.himmel.opacity(0.6) : .clear
        let strich = StrokeStyle(lineWidth: 1, dash: geschaetzt && !an ? [4, 3] : [])
        return Text(titel).font(Sundartha.grotesk(14)).lineLimit(1).foregroundStyle(schrift)
            .padding(.horizontal, 13).frame(height: 36)
            .background(Capsule().fill(flaeche))
            .overlay(Capsule().strokeBorder(kante, style: strich))
    }
}

struct Fliess: Layout {
    var abstand: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = reihen(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? r.map(\.breite).max() ?? 0, height: r.map(\.hoehe).reduce(0, +) + abstand * CGFloat(max(0, r.count - 1)))
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = b.minY
        for r in reihen(b.width, subviews) {
            var x = b.minX
            for i in r.teile {
                let g = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
                x += g.width + abstand
            }
            y += r.hoehe + abstand
        }
    }

    private func reihen(_ breite: CGFloat, _ s: Subviews) -> [(teile: [Int], breite: CGFloat, hoehe: CGFloat)] {
        var aus: [(teile: [Int], breite: CGFloat, hoehe: CGFloat)] = []
        for i in s.indices {
            let g = s[i].sizeThatFits(.unspecified)
            if let l = aus.last, l.breite + abstand + g.width <= breite {
                aus[aus.count - 1] = (l.teile + [i], l.breite + abstand + g.width, max(l.hoehe, g.height))
            } else {
                aus.append(([i], g.width, g.height))
            }
        }
        return aus
    }
}

struct TafelEingabe: View {
    var text: String
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 12) {
                Text("+").font(Sundartha.grotesk(20)).foregroundStyle(TafelFarbe.akzent)
                Text(text).font(Sundartha.grotesk(16)).foregroundStyle(TafelFarbe.leise)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(height: 50)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

struct TafelRueck: View {
    var satz: String
    var dauer: Double
    var rueckgaengig: () -> Void
    @State private var rest: CGFloat = 1

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Haken().haken(TafelFarbe.gruen, 12)
                Text(satz).font(Sundartha.grotesk(14)).foregroundStyle(.white).zeilenHoehe(20, schrift: 14).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Rückgängig", action: rueckgaengig).font(Sundartha.grotesk(15, .medium)).foregroundStyle(TafelFarbe.himmel)
                    .padding(.horizontal, 4).frame(height: 44).buttonStyle(.plain)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(TafelFarbe.himmel).frame(width: g.size.width * rest)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .padding(.horizontal, 16)
        .onAppear { withAnimation(.linear(duration: dauer)) { rest = 0 } }
    }
}

struct TafelBlattGrund: View {
    var body: some View {
        LinearGradient(colors: [TafelFarbe.hex(0x17345F), TafelFarbe.hex(0x0C2246)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

extension View {
    func tafelBlatt<E: Identifiable, I: View>(item: Binding<E?>, hoehe: CGFloat, @ViewBuilder _ inhalt: @escaping (E) -> I) -> some View {
        sheet(item: item) { e in inhalt(e).tafelBlattRahmen(hoehe) }
    }

    func tafelBlatt<I: View>(isPresented: Binding<Bool>, hoehe: CGFloat, @ViewBuilder _ inhalt: @escaping () -> I) -> some View {
        sheet(isPresented: isPresented) { inhalt().tafelBlattRahmen(hoehe) }
    }

    fileprivate func tafelBlattRahmen(_ hoehe: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 38, height: 5).padding(.top, 12)
            self.padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(TafelFarbe.text)
        .presentationDetents([.height(hoehe)])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.hidden)
        .presentationBackground { TafelBlattGrund() }
    }
}
