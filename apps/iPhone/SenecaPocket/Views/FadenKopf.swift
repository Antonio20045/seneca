import SwiftUI

extension FadenLayer {
    struct Zustand {
        var satz: String
        var art: HinweisZeile.Art = .info
        var wort: String?
        var aktion: () -> Void = {}
    }

    var zustand: Zustand? {
        if let hinweis = model.zustandsHinweis { return Zustand(satz: hinweis) }
        if model.macUnreachable { return Zustand(satz: "Der Mac ist gerade nicht erreichbar.", art: .offline) }
        if model.liestVor || speech.isSpeaking {
            return Zustand(satz: "\(partner.satzName) liest die Antwort vor.", wort: "Aufhören", aktion: { model.unterbrechen() })
        }
        if fragtNeu {
            let p = partner
            return Zustand(satz: "\(p.satzName) vergisst dann dieses Gespräch.", wort: "Ja, neu beginnen", aktion: {
                fragtNeu = false
                zeigtFuellstand = false
                Task { @MainActor in
                    if await !chat.reset(p) { model.zeigeHinweis(chat.problem ?? "Neu beginnen hat gerade nicht geklappt.", sekunden: 5) }
                }
            })
        }
        if chat.fill.map({ $0.percent >= 70 }) == true || zeigtFuellstand {
            let satz = chat.fill.map { "Das Gespräch ist zu \($0.percent) % gefüllt." } ?? "Wie voll das Gespräch ist, weiß ich gerade nicht."
            return Zustand(satz: satz, wort: "Neu beginnen", aktion: {
                fragtNeu = true
                Task { @MainActor in try? await Task.sleep(for: .seconds(4)); fragtNeu = false }
            })
        }
        if let anderer = GespraechsPartner.alle.first(where: { chat.neu.contains($0.id) && $0.id != partner.id }) {
            return Zustand(satz: "\(anderer.satzName) hat dir geschrieben.", wort: "Ansehen", aktion: {
                Haptik.auswahl()
                chat.waehle(anderer)
            })
        }
        return nil
    }

    @ViewBuilder var zustandsZeile: some View {
        if let z = zustand {
            Group {
                if let wort = z.wort {
                    let tun = z.aktion
                    let darf = allowTap
                    HinweisZeile(z.satz, art: z.art, aktion: (titel: wort, ausfuehren: { if darf() { tun() } }))
                } else {
                    HinweisZeile(z.satz, art: z.art)
                }
            }
            .seitenRand()
            .padding(.bottom, Stil.abstand.xs)
            .transition(.wechsel)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("faden.zustand")
        }
    }

    @ViewBuilder var anhaltenKnopf: some View {
        if laeuft {
            TextKnopf("Anhalten") {
                guard allowTap() else { return }
                Haptik.tipp()
                model.anhalten(partner)
            }
            .accessibilityHint("Hält die Antwort an")
            .accessibilityIdentifier("faden.anhalten")
            .transition(.wechsel)
        }
    }

    func springe(_ t: SucheTreffer, _ proxy: ScrollViewProxy) {
        if partner != t.partner { gewaehlt(t.partner, proxy) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            Bewegung.mit(.blatt) { proxy.scrollTo("r:" + t.nachricht.id, anchor: .center) }
            Bewegung.mit(.wechsel) { markiert = t.nachricht.id }
            try? await Task.sleep(for: .seconds(1.6))
            Bewegung.mit(.wechsel) { if markiert == t.nachricht.id { markiert = nil } }
        }
    }

    func gewaehlt(_ p: ChatPartner, _ proxy: ScrollViewProxy) {
        if partner == p {
            Bewegung.mit(.blatt) { proxy.scrollTo("ende", anchor: .bottom) }
            Task { await chat.refreshFill(p) }
            let bis = Date().addingTimeInterval(8)
            fuellstandBis = bis
            Bewegung.mit(.wechsel) { zeigtFuellstand = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                if fuellstandBis == bis { Bewegung.mit(.wechsel) { zeigtFuellstand = false } }
            }
        } else {
            zeigtFuellstand = false
            fragtNeu = false
            Haptik.auswahl()
            chat.waehle(p)
        }
    }
}

