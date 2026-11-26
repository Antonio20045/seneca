import SwiftUI
import UIKit

struct Seite<Inhalt: View>: View {
    var titel: String?
    var zurueck: String?
    var scrollt = true
    var beimZurueck: (() -> Void)?
    private let inhalt: Inhalt
    private var reiterInhalt: AnyView?
    private var rechtsInhalt: AnyView?
    private var untenInhalt: AnyView?

    @Environment(\.wege) private var wege
    @Environment(\.imBlatt) private var imBlatt
    @State private var tastatur = false

    init(titel: String? = nil, zurueck: String? = nil, scrollt: Bool = true,
         beimZurueck: (() -> Void)? = nil, @ViewBuilder inhalt: () -> Inhalt) {
        self.titel = titel; self.zurueck = zurueck; self.scrollt = scrollt
        self.beimZurueck = beimZurueck
        self.inhalt = inhalt()
    }

    func reiter<V: View>(@ViewBuilder _ v: () -> V) -> Seite { var s = self; s.reiterInhalt = AnyView(v()); return s }
    func rechts<V: View>(@ViewBuilder _ v: () -> V) -> Seite { var s = self; s.rechtsInhalt = AnyView(v()); return s }
    func unten<V: View>(@ViewBuilder _ v: () -> V) -> Seite { var s = self; s.untenInhalt = AnyView(v()); return s }

    private var oben: CGFloat { (imBlatt ? 0 : Stil.fensterRaender.top) + Stil.kopfOben }
    private var untenLuft: CGFloat { tastatur ? Stil.abstand.s : Stil.fensterRaender.bottom + Stil.unten }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopfNormal
                .padding(.top, oben)
                .seitenRand()
            if scrollt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { inhalt }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .seitenRand()
                        .padding(.top, Stil.abstand.l)
                        .padding(.bottom, untenInhalt == nil ? untenLuft : Stil.abstand.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .weicheKante(unten: untenInhalt != nil)
                .claimsVerticalDrags()
                .safeAreaInset(edge: .bottom, spacing: 0) { untenTeil }
            } else {
                inhalt
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) { untenTeil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .vertical)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in tastatur = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in tastatur = false }
    }

    @ViewBuilder private var untenTeil: some View {
        if let untenInhalt {
            untenInhalt
                .seitenRand()
                .padding(.top, Stil.abstand.s)
                .padding(.bottom, untenLuft)
        }
    }

    private func zurueckTun() {
        if let beimZurueck { beimZurueck() } else { wege.zurueck() }
    }

    private var kopfNormal: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let zurueck {
                Button(action: zurueckTun) {
                    HStack(spacing: Stil.abstand.xs) {
                        Image(systemName: "chevron.left").font(Stil.symbol(.klein, gewicht: .medium))
                        Text(zurueck).schrift(.zeileWichtig)
                    }
                    .foregroundStyle(Stil.tinte.zweit)
                    .frame(minHeight: Stil.tippFlaeche)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück zu \(zurueck)")
                .accessibilityIdentifier("seite.zurueck")
            }
            if titel != nil || rechtsInhalt != nil {
                HStack(alignment: .center, spacing: Stil.abstand.m) {
                    titelTeil
                    Spacer(minLength: 0)
                    if let rechtsInhalt { rechtsInhalt }
                }
                .frame(minHeight: Stil.tippFlaeche)
                .padding(.top, zurueck == nil ? 0 : Stil.abstand.s)
            }
            if let reiterInhalt {
                reiterInhalt.padding(.top, Stil.abstand.s)
            }
        }
    }

    @ViewBuilder private var titelTeil: some View {
        if let titel {
            let text = Text(titel)
                .schrift(.titel)
                .foregroundStyle(Stil.tinte.voll)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            text
        }
    }
}

extension View {
    func senecaGrund() -> some View {
        background(Stil.farbe.grund.ignoresSafeArea())
    }
}

private struct ImBlattSchluessel: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var imBlatt: Bool {
        get { self[ImBlattSchluessel.self] }
        set { self[ImBlattSchluessel.self] = newValue }
    }
}
