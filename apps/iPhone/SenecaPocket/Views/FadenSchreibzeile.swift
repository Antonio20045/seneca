import SwiftUI

extension FadenLayer {
    var schreibzeile: some View {
        let bilder = model.anhaenge[partner.id] ?? [], diktat = model.diktatSeit
        return VStack(alignment: .leading, spacing: 10) {
            if diktat != nil {
                Text("Diktat · der Text kommt ins Feld, senden tust du").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise).padding(.horizontal, 4)
            } else if !bilder.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 13))
                    Text("Bilder verkleinert Seneca vor dem Senden. Bis zehn pro Nachricht.").fixedSize(horizontal: false, vertical: true)
                }
                .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if diktat == nil { rundKnopf("plus", "Anhängen") { fokus = false; anhangWahl = true } }
                if feldLeer, bilder.isEmpty, !fokus, diktat == nil, model.sprechenErlaubt { sprechen }
                VStack(alignment: .leading, spacing: 10) {
                    if !bilder.isEmpty { AnhangFeldLeiste(anhaenge: bilder) { id in model.anhaenge[partner.id]?.removeAll { $0.id == id } } }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("", text: $feld, prompt: Text(partner.platzhalter).foregroundColor(TafelFarbe.leise), axis: .vertical)
                            .font(Sundartha.grotesk(16)).foregroundStyle(.white).lineLimit(1...5).focused($fokus)
                            .padding(.vertical, diktat == nil ? 13 : 0)
                            .accessibilityIdentifier("faden.feld")
                        if diktat != nil {
                        } else if !feldLeer || !bilder.isEmpty {
                            Button { senden() } label: {
                                Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel)
                                    .frame(width: 36, height: 36).background(Circle().fill(TafelFarbe.akzent))
                            }
                            .buttonStyle(.plain).padding(.bottom, 6)
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityLabel("Senden")
                        } else if model.sprechenErlaubt {
                            Button { fokus = false; model.diktatStarten(basis: feld) { feld = $0 } } label: {
                                Image(systemName: "mic").font(.system(size: 17)).foregroundStyle(TafelFarbe.zweit).frame(width: 36, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.bottom, 6).accessibilityLabel("Diktieren")
                        }
                    }
                    if let diktat { DiktatZeile(seit: diktat, pegel: { model.pegel }) { model.diktatEnde() } }
                }
                .padding(.leading, diktat == nil ? 18 : 16).padding(.trailing, diktat == nil && feldLeer && bilder.isEmpty && !model.sprechenErlaubt ? 18 : 6)
                .padding(.top, diktat == nil ? (bilder.isEmpty ? 0 : 10) : 12).padding(.bottom, diktat == nil ? 0 : 8)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: diktat == nil ? 24 : 22, style: .continuous).fill(Color.white.opacity(diktat == nil ? 0.09 : 0.1)))
                .overlay {
                    if diktat != nil {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(TafelFarbe.jetzt.opacity(0.45), lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                }
                if diktat != nil {
                    rundKnopf("waveform", "Gespräch") {
                        model.diktatEnde()
                        model.gespraechStarten(feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
                    }
                }
            }
        }
        .padding(.horizontal, -8)
        .bewegt(.wechsel, wert: feldLeer && !fokus)
        .bewegt(.wechsel, wert: diktat != nil)
        .tafelBlatt(isPresented: $anhangWahl, hoehe: 640) {
            AnhangWahl(anhaengen: { d, n, mime in model.anhaengen(d, name: n, mime: mime, fuer: partner) }) { anhangWahl = false }
        }
    }

    #if DEBUG
    func demoAnhang(_ env: [String: String]) {
        if let pfad = env["SENECA_DEMO_ANHANG"], let d = FileManager.default.contents(atPath: pfad), model.anhaenge[partner.id] == nil {
            for _ in 0..<2 { model.anhaengen(d, name: nil, mime: "image/png", fuer: partner) }
            if env["SENECA_DEMO_ANHANG_SENDEN"] == "1" { Task { @MainActor in try? await Task.sleep(for: .seconds(1)); senden() } }
        }
        if env["SENECA_DEMO_ANHANG_WAHL"] == "1" { anhangWahl = true }
        if env["SENECA_DEMO_DIKTAT"] == "1" { Task { @MainActor in try? await Task.sleep(for: .seconds(1)); model.diktatStarten(basis: "") { feld = $0 } } }
    }
    #endif

    private func rundKnopf(_ bild: String, _ name: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: bild).font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain).padding(.bottom, 2).accessibilityLabel(name)
    }

    private var sprechen: some View {
        Button {
            guard allowTap() else { return }
            fokus = false
            model.gespraechStarten(feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic").font(.system(size: 15, weight: .medium))
                Text("Sprechen").font(Sundartha.grotesk(15, .medium))
            }
            .foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 16).frame(height: 48)
            .background(Capsule().fill(TafelFarbe.akzent))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Sagen, was du willst; \(partner.satzName) antwortet")
        .accessibilityIdentifier("faden.sprechen")
    }

    func sprechWunschErfuellen() {
        guard model.sprechWunschOffen else { return }
        model.sprechWunschOffen = false
        guard !model.gespraech.aktiv else { return }
        if model.sprechenErlaubt, feldLeer {
            fokus = false
            model.gespraechStarten(taste: model.sprechWunschTaste, feld: { feld = $0 }, senden: { text in feld = text; return senden(text) })
        } else {
            fokus = true
        }
    }

    @discardableResult
    func senden(_ gesagt: String? = nil) -> Bool {
        let text = gesagt ?? feld
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(model.anhaenge[partner.id] ?? []).isEmpty else { return false }
        let vorher = ankerPartner
        ankerPartner = partner.id
        if model.senden(text, an: partner) {
            feld = ""
            return true
        }
        ankerPartner = vorher
        if model.macUnreachable { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        return false
    }
}
