import SwiftUI

enum BlattGroesse {
    case halb, voll
    var hoehen: Set<PresentationDetent> { self == .halb ? [.medium, .large] : [.large] }
}

struct BlattRahmen<Inhalt: View>: View {
    var titel: String?
    var groesse: BlattGroesse = .halb
    var fertig = false
    var scrollt = true
    private let inhalt: Inhalt
    private var untenInhalt: AnyView?
    @Environment(\.imBlatt) private var schonImBlatt
    @Environment(\.dismiss) private var schliessen

    init(titel: String? = nil, groesse: BlattGroesse = .halb, fertig: Bool = false, scrollt: Bool = true,
         @ViewBuilder inhalt: () -> Inhalt) {
        self.titel = titel; self.groesse = groesse; self.fertig = fertig; self.scrollt = scrollt
        self.inhalt = inhalt()
    }

    func unten<V: View>(@ViewBuilder _ v: () -> V) -> BlattRahmen { var s = self; s.untenInhalt = AnyView(v()); return s }

    var body: some View {
        if schonImBlatt {
            VStack(alignment: .leading, spacing: 0) {
                inhalt
                if let untenInhalt { untenInhalt.padding(.top, Stil.abstand.xl) }
            }
        } else {
            rahmen
        }
    }

    @ViewBuilder private var untenTeil: some View {
        if let untenInhalt {
            untenInhalt
                .seitenRand()
                .padding(.top, Stil.abstand.m)
                .padding(.bottom, Stil.unten)
        }
    }

    private var rahmen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if titel != nil || fertig {
                HStack(alignment: .center, spacing: Stil.abstand.m) {
                    if let titel {
                        Text(titel)
                            .schrift(.titel)
                            .foregroundStyle(Stil.tinte.voll)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    if fertig {
                        Button("Fertig") { schliessen() }
                            .buttonStyle(TextKnopfStil(stufe: .zeileWichtig))
                    }
                }
                .frame(minHeight: Stil.tippFlaeche)
                .seitenRand()
            }
            if scrollt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { inhalt }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .seitenRand()
                        .padding(.top, Stil.abstand.l)
                        .padding(.bottom, untenInhalt == nil ? Stil.unten : Stil.abstand.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .weicheKante(unten: untenInhalt != nil)
                .safeAreaInset(edge: .bottom, spacing: 0) { untenTeil }
            } else {
                inhalt.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) { untenTeil }
            }
        }
        .padding(.top, Stil.abstand.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.imBlatt, true)
        .presentationDetents(groesse.hoehen)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Stil.radius.gross)
        .presentationBackground { Stil.farbe.grund }
        .preferredColorScheme(.dark)
        .wischZurueck(vollbild: false) { schliessen() }
    }
}

extension View {
    func senecaBlatt<Inhalt: View>(isPresented: Binding<Bool>, groesse: BlattGroesse = .halb, titel: String? = nil,
                                   fertig: Bool = false, scrollt: Bool = true,
                                   @ViewBuilder inhalt: @escaping () -> Inhalt) -> some View {
        sheet(isPresented: isPresented) {
            BlattRahmen(titel: titel, groesse: groesse, fertig: fertig, scrollt: scrollt, inhalt: inhalt)
        }
    }

    func senecaBlatt<Inhalt: View, Unten: View>(isPresented: Binding<Bool>, groesse: BlattGroesse = .halb, titel: String? = nil,
                                                fertig: Bool = false, scrollt: Bool = true,
                                                @ViewBuilder inhalt: @escaping () -> Inhalt,
                                                @ViewBuilder unten: @escaping () -> Unten) -> some View {
        sheet(isPresented: isPresented) {
            BlattRahmen(titel: titel, groesse: groesse, fertig: fertig, scrollt: scrollt, inhalt: inhalt).unten(unten)
        }
    }

    func senecaBlatt<Eintrag: Identifiable, Inhalt: View>(item: Binding<Eintrag?>, groesse: BlattGroesse = .halb,
                                                         titel: @escaping (Eintrag) -> String? = { _ in nil },
                                                         fertig: Bool = false, scrollt: Bool = true,
                                                         @ViewBuilder inhalt: @escaping (Eintrag) -> Inhalt) -> some View {
        sheet(item: item) { e in
            BlattRahmen(titel: titel(e), groesse: groesse, fertig: fertig, scrollt: scrollt) { inhalt(e) }
        }
    }
}
