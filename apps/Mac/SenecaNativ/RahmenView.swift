import SwiftUI
import UserNotifications
import WidgetKit

struct RahmenView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject private var store: OverviewStore
    @ObservedObject private var ansichten: AnsichtModell
    @ObservedObject private var chat: ChatService
    @ObservedObject private var suche: SucheModell
    @ObservedObject private var snFenster: SnFensterModell
    @StateObject private var chatSteuerung: SnChatSteuerung
    @StateObject private var versionsHinweis = VersionsHinweisModell()
    @State private var verbreitert: CGFloat = 0

    init(modell: AppModell) {
        self.modell = modell
        _store = ObservedObject(wrappedValue: modell.uebersicht)
        _ansichten = ObservedObject(wrappedValue: modell.ansichten)
        _chat = ObservedObject(wrappedValue: modell.store.chat)
        _suche = ObservedObject(wrappedValue: modell.suche)
        _snFenster = ObservedObject(wrappedValue: modell.snFenster)
        _chatSteuerung = StateObject(wrappedValue: SnChatSteuerung(modell: modell))
    }

    var body: some View {
        ZStack {
            seite
                .id(modell.route.seite)
                .transition(.opacity)
            VStack(spacing: 10) {
                VersionsHinweisBand(hinweis: versionsHinweis, neuStarten: {
                    versionsHinweis.neuStarten(vorherSpeichern: { chatSteuerung.speichereEntwurfSofort() })
                })
                SnOrteLeiste(aktiv: SnOrt.von(modell.route.seite), store: modell.store, waehle: { modell.gehe($0.seite) })
                Spacer()
            }
            .padding(.top, 24)
            GeometryReader { g in
                let offen = modell.route.seite == .chat
                let agent = modell.gegenueber.ziel?.agentId ?? Hauptagent.id
                let s = SnChatSeite.spalte(g.size.width, seneca: agent == Hauptagent.id, frage: SnChatSeite.mehrFrage(modell.store.stand, agent: agent, id: modell.mehrFrage) != nil)
                VStack {
                    Spacer()
                    SnDock(offen: offen, breiteOffen: s.breite, oeffne: { modell.zeigeGespraechSeite() }, schliesse: { modell.zeigeGespraechSeite() },
                           steuerung: chatSteuerung, chat: chat, gegenueber: modell.gegenueber)
                        .offset(x: offen ? s.links + s.breite / 2 - g.size.width / 2 : 0)
                        .opacity(snFenster.offen ? 0.35 : 1)
                        .allowsHitTesting(!snFenster.offen)
                        .animation(Kurve.sn(0.45), value: snFenster.offen)
                }
                .padding(.bottom, offen ? 40 : 28)
                .frame(width: g.size.width)
            }
            toastSchicht
        }
        .animation(nil, value: modell.route.seite)
        .dateiAblage(markiere: false) { urls in
            if modell.route.seite != .chat { modell.zeigeGespraechSeite() }
            chatSteuerung.fuegeHinzu(urls)
        }
        .ignoresSafeArea(.container, edges: .top)
        .task { await SnBilder.laufe(modell: modell) }
        .task { versionsHinweis.starte() }
        .background(FensterHalter(modell: modell))
        .inspector(isPresented: Binding(get: { ansichten.panel != nil }, set: { if !$0 { ansichten.schliesse() } })) {
            PanelView()
                .inspectorColumnWidth(min: Mass.panel, ideal: Mass.panel, max: Mass.panel)
        }
        .environmentObject(ansichten)
        .environmentObject(store)
        .environmentObject(modell)
        .overlay {
            Ueberdeckung(an: suche.offen, schliessen: { suche.zu() }) { SucheView(suche: suche, schliessen: { suche.zu() }) }
        }
        .overlay {
            Ueberdeckung(an: modell.modellwahlOffen, schliessen: { modell.modellwahlOffen = false }) {
                ModellwahlView(modell: modell, modelle: modell.modelle, uebersicht: store, gegenueber: modell.gegenueber,
                               schliessen: { modell.modellwahlOffen = false })
            }
        }
        .overlay { SnKopplungSchicht(stand: modell.store.stand) }
        .overlay { TastenhilfeDialog(modell: modell) }
        .overlay(alignment: .topTrailing) {
            if MacPfade.nebenher {
                Text("Probe").font(Schrift.grotesk(11, .medium)).foregroundStyle(Color(hex: 0xE88A6B))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Farbe.warnFlaeche, in: Capsule()).overlay(Capsule().stroke(Farbe.warnKante, lineWidth: 1))
                    .padding(.top, 12).padding(.trailing, 16)
                    .allowsHitTesting(false).accessibilityIdentifier("probe-hinweis")
            }
        }
        .onChange(of: store.daten, initial: true) { _, _ in
            modell.gegenueber.pruefeBereich(); suche.aktualisiere()
            ChatPartner.agentNamen = Dictionary(modell.gegenueber.personen.alle.map { ($0.id, $0.wer) }, uniquingKeysWith: { a, _ in a })
        }
        .onChange(of: ansichten.panel != nil) { _, offen in fensterAnpassen(offen: offen) }
        .onChange(of: chat.lives.isEmpty) { _, _ in
            Task { await store.aktualisiereSitzungen() }
        }
        .task { await SnWeg.gemeinsam.laufe(modell.store) }
    }

    private var seite: some View {
        Group { switch modell.route.seite {
        case .heute:
            SnHeuteMitFenster(modell: modell)
        case .chat:
            SnChatSeite(modell: modell, steuerung: chatSteuerung, schliesse: { modell.zeigeGespraechSeite() })
                .transition(.opacity.combined(with: .offset(y: 16)))
        case .projekte:
            SnProjekteEcht(modell: modell, store: modell.store)
        case .kalender: SnKalenderEcht(modell: modell, store: modell.store)
        case .entscheidungen: SnEntscheidenEcht(store: modell.store)
        case .statistik: SnStatistikEcht(store: modell.store)
        } }
        .environment(\.mehrZu) { modell.zeigeMehr($0) }
    }

    private var toastSchicht: some View {
        VStack(spacing: 8) {
            ForEach(store.toasts) { t in
                HStack(spacing: 14) {
                    Text(t.text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1)
                    if let a = t.aktion {
                        Button(a) { Task { await store.fuehreAus(t.id) } }
                            .buttonStyle(.plain).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel)
                            .accessibilityIdentifier("toast-aktion")
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Farbe.papier2, in: Capsule())
                .overlay(alignment: .bottomLeading) { ToastBalken(dauer: t.dauer) }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .shadow(color: Farbe.hinweisSchatten, radius: 16, y: 6)
                .transition(.opacity.combined(with: .offset(y: 14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("toast")
            }
        }
        .padding(.bottom, 24)
        .animation(Kurve.feder(0.35), value: store.toasts)
        .allowsHitTesting(!store.toasts.isEmpty)
    }

    private func fensterAnpassen(offen: Bool) {
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        var f = w.frame
        if offen, verbreitert == 0 {
            let platz = (w.screen?.visibleFrame.maxX ?? f.maxX) - f.minX
            let plus = min(Mass.panel, max(0, platz - f.width))
            guard plus > 0 else { return }
            f.size.width += plus
            verbreitert = plus
            w.setFrame(f, display: true, animate: true)
        } else if !offen, verbreitert > 0 {
            f.size.width -= verbreitert
            verbreitert = 0
            w.setFrame(f, display: true, animate: true)
        }
    }
}

struct ToastBalken: View {
    var dauer: Double
    @State private var rest: CGFloat = 1
    var body: some View {
        Rectangle().fill(Farbe.ink1.opacity(0.35)).frame(height: 3)
            .scaleEffect(x: rest, anchor: .leading)
            .onAppear { withAnimation(.linear(duration: dauer)) { rest = 0 } }
    }
}
