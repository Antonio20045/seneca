import SwiftUI

extension FadenLayer {
    var schreibzeile: some View {
        let bilder = model.anhaenge[partner.id] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            if !bilder.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 13))
                    Text("Bilder verkleinert Seneca vor dem Senden. Bis zehn pro Nachricht.").fixedSize(horizontal: false, vertical: true)
                }
                .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                rundKnopf("plus", "Anhängen") { fokus = false; anhangWahl = true }
                VStack(alignment: .leading, spacing: 10) {
                    if !bilder.isEmpty { AnhangFeldLeiste(anhaenge: bilder) { id in model.anhaenge[partner.id]?.removeAll { $0.id == id } } }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("", text: $feld, prompt: Text(partner.platzhalter).foregroundColor(TafelFarbe.leise), axis: .vertical)
                            .font(Sundartha.grotesk(16)).foregroundStyle(.white).lineLimit(1...5).focused($fokus)
                            .padding(.vertical, 13)
                            .accessibilityIdentifier("faden.feld")
                        if !feldLeer || !bilder.isEmpty {
                            Button { senden() } label: {
                                Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel)
                                    .frame(width: 36, height: 36).background(Circle().fill(TafelFarbe.akzent))
                            }
                            .buttonStyle(.plain).padding(.bottom, 6)
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityLabel("Senden")
                        }
                    }
                }
                .padding(.leading, 18).padding(.trailing, feldLeer && bilder.isEmpty ? 18 : 6)
                .padding(.top, bilder.isEmpty ? 0 : 10)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.09)))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, -8)
        .bewegt(.wechsel, wert: feldLeer && !fokus)
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
    }
    #endif

    private func rundKnopf(_ bild: String, _ name: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: bild).font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain).padding(.bottom, 2).accessibilityLabel(name)
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
