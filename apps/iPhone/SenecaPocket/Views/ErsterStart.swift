import SwiftUI
import AVFoundation

struct ErsterStart: View {
    enum Schritt { case start, scannen, uhr }

    @Binding var schritt: Schritt?
    var adresseEingeben: () -> Void

    @EnvironmentObject private var store: SenecaStore
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @State private var gefunden: Kopplungscode?
    @State private var fehler: String?
    @State private var abgebrochen = false
    @State private var bestaetigt = false

    var body: some View {
        GeometryReader { g in
            let sy = g.size.height / 844
            ZStack {
                switch schritt {
                case .scannen: scannen(sy)
                case .uhr: uhr(sy, breite: g.size.width)
                default: start(sy)
                }
                Capsule().fill(.white.opacity(0.7)).frame(width: 134, height: 5)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onChange(of: store.isConnected) { _, da in
            guard da, schritt != .uhr else { return }
            Task { try? await Task.sleep(for: .seconds(1.4)); Bewegung.mit(.seite) { schritt = .uhr } }
        }
        .task(id: schritt) { if schritt == .uhr, !store.demo { store.daten?.handeln("geraet.uhr_koppeln") } }
        #if DEBUG
        .onAppear {
            guard store.demo, ProcessInfo.processInfo.environment["SENECA_DEMO_START"] == "2" else { return }
            gefunden = Kopplungscode(adresse: "", schluessel: "", name: "MacBook Pro von Antonio", bis: .distantFuture)
        }
        #endif
    }

    private var blau: some View {
        LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
    }

    private func titel(_ vor: String, _ akzent: String, _ groesse: CGFloat, _ hoehe: CGFloat) -> some View {
        (Text(vor + " ").font(Sundartha.serif(groesse)).foregroundColor(.white)
            + Text(akzent).font(Sundartha.serif(groesse, italic: true)).foregroundColor(TafelFarbe.akzent))
            .zeilenHoehe(groesse * hoehe, schrift: groesse)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func knopf(_ text: String, hell: Bool = true, an: Bool = true, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            Text(text).font(Sundartha.grotesk(15, .medium)).foregroundStyle(hell ? TafelFarbe.aufHimmel : .white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(hell ? TafelFarbe.himmel : .white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain).opacity(an ? 1 : 0.4).disabled(!an)
    }

    private func start(_ sy: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            blau
            VStack(alignment: .leading, spacing: 0) {
                Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.26),
                                                     .init(color: TafelFarbe.hex(0x6E9CE0, 0.5), location: 0.56), .init(color: TafelFarbe.hex(0x6E9CE0, 0), location: 0.76)],
                                             center: .center, startRadius: 0, endRadius: 28 * 2.squareRoot()))
                    .frame(width: 56, height: 56)
                titel("Seneca lebt auf deinem Mac.", "Das iPhone ist sein Fenster.", 44, 1.04).frame(maxWidth: 334, alignment: .leading).padding(.top, 28)
                Text("Öffne Seneca auf dem Mac. Dort steht ein Code, den du gleich scannst.")
                    .font(Sundartha.grotesk(16)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(23, schrift: 16).padding(.top, 18)
            }
            .padding(.horizontal, 28).padding(.top, 200 * sy)
            VStack(spacing: 10) {
                knopf("Code scannen") { Bewegung.mit(.seite) { schritt = .scannen } }
                Button(action: adresseEingeben) {
                    Text("Ohne Kamera: Adresse eingeben").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.leise).padding(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 60 * sy)
        }
    }

    private func scannen(_ sy: CGFloat) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [TafelFarbe.hex(0x1A1F26), TafelFarbe.hex(0x0D1015)], startPoint: .top, endPoint: .bottom)
            if !store.demo { CodeKamera { gelesen($0) } }
            Text("Halte die Kamera auf den Code am Mac.").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.text)
                .frame(maxWidth: .infinity).padding(.top, 140 * sy)
            ScanRahmen(probe: store.demo).frame(width: 250, height: 250).padding(.top, 230 * sy)
            if let k = gefunden { karte(k).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 70 * sy) }
        }
        .background(Color.black)
        .wischZurueck { Bewegung.mit(.seite) { schritt = .start } }
    }

    private func karte(_ k: Kopplungscode) -> some View {
        let da = store.isConnected || store.demo
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(da ? TafelFarbe.gruen : .clear).overlay(Circle().strokeBorder(da ? .clear : TafelFarbe.zweit, lineWidth: 1.5))
                if da { Haken().haken(TafelFarbe.hex(0x062012), 15) }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(k.name.isEmpty ? "Dein Mac" : k.name).font(Sundartha.grotesk(16, .medium)).foregroundStyle(.white)
                Text(fehler ?? (da ? "Verbunden · über dein privates Netz" : "Verbinde …")).font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .background(TafelFarbe.hex(0x061022, 0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 24)
        .transition(.opacity)
    }

    private func gelesen(_ text: String) {
        guard gefunden == nil || fehler != nil, let k = Kopplungscode(text: text) else { return }
        Bewegung.mit(.klein) { gefunden = k }
        guard k.gilt() else { fehler = "Der Code ist abgelaufen. Am Mac: Neuer Code."; return }
        fehler = nil
        do { try CredentialStore.save(k.schluessel) } catch { fehler = error.localizedDescription; return }
        gatewayURL = k.adresse
        store.configure(url: k.adresse, token: k.schluessel)
        Task { await store.connect() }
    }

    private var kopplung: SenecaStand.Kopplung? {
        #if DEBUG
        if store.demo { return SenecaStand.Kopplung(geraet: "uhr1", zahl: "4817", modell: "fēnix 9 Pro · Seneca 1.0", bestaetigt: false) }
        #endif
        return store.stand?.kopplung?.last { $0.bestaetigt != true }
    }

    private func uhr(_ sy: CGFloat, breite: CGFloat) -> some View {
        let k = abgebrochen || bestaetigt ? nil : kopplung
        let ziffern = k.map { Array($0.zahl).map(String.init) } ?? ["", "", "", ""]
        return ZStack(alignment: .top) {
            blau
            VStack(alignment: .leading, spacing: 0) {
                Text("SCHRITT 3 VON 3 · GEHT AUCH SPÄTER").mono(11, abstand: 1.2).foregroundStyle(TafelFarbe.himmel)
                titel("Steht auf der Uhr", "dieselbe Zahl?", 38, 1.06).padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 90 * sy)
            HStack(spacing: 14) {
                ForEach(Array(ziffern.enumerated()), id: \.offset) { _, z in
                    Text(z).font(Sundartha.grotesk(40, .medium)).foregroundStyle(.white)
                        .frame(width: 58, height: 74).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.top, 260 * sy)
            Text(satz(k)).font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(22, schrift: 15)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 360 * sy)
            if let k { UhrZahl(zahl: k.zahl).frame(width: 170, height: 170).padding(.top, 480 * sy) }
            HStack(spacing: 10) {
                if abgebrochen || bestaetigt {
                    knopf("Fertig") { fertig() }
                } else {
                    knopf("Ja, gleich", an: k != nil) {
                        guard let k else { return }
                        store.daten?.handeln("geraet.uhr_bestaetigen", ziel: k.geraet, wert: .text(k.zahl))
                        Bewegung.mit(.klein) { bestaetigt = true }
                    }
                    knopf("Nein", hell: false) { if k == nil { fertig() } else { Bewegung.mit(.klein) { abgebrochen = true } } }
                }
            }
            .padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 60 * sy)
        }
    }

    private func satz(_ k: SenecaStand.Kopplung?) -> String {
        if bestaetigt { return "Die Uhr ist gekoppelt. Sie holt sich ihren Stand über dieses iPhone." }
        if abgebrochen { return "Abgebrochen. Neu geht es jederzeit unter Einstellungen › Uhr verbinden, solange Seneca auf der Uhr offen ist." }
        guard let k else { return "Öffne Seneca auf der Uhr. Connect IQ findet sie über dieses iPhone, dann zeigen beide dieselbe Zahl." }
        return "\(k.modell ?? "Deine Uhr") ist installiert. Die Uhr bekommt deine To-dos, Übungen und das aktuelle Buch. Sie schickt Sätze, Lesezeit und Antworten."
    }

    private func fertig() {
        Bewegung.mit(.seite) { schritt = nil }
    }
}

private struct ScanRahmen: View {
    var probe: Bool

    var body: some View {
        ZStack {
            if probe {
                ZStack {
                    VStack(spacing: 8) { ForEach(0..<11, id: \.self) { _ in Rectangle().fill(.black.opacity(0.55)).frame(height: 8) } }
                    HStack(spacing: 8) { ForEach(0..<10, id: \.self) { _ in Rectangle().fill(.white.opacity(0.75)).frame(width: 10) } }.frame(width: 170, alignment: .leading)
                }
                .frame(width: 170, height: 170).clipShape(RoundedRectangle(cornerRadius: 8)).opacity(0.55)
            }
            ForEach(0..<4, id: \.self) { i in
                Ecke().stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading][i])
            }
        }
    }

    private struct Ecke: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX + 2, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + 2, y: r.minY + 18))
            p.addArc(center: CGPoint(x: r.minX + 18, y: r.minY + 18), radius: 16, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2))
            return p
        }
    }
}

private struct UhrZahl: View {
    var zahl: String

    var body: some View {
        ZStack {
            Circle().fill(TafelFarbe.hex(0x2A2F37)).frame(width: 488, height: 488)
            Circle().fill(TafelFarbe.hex(0x1A1D22)).frame(width: 486, height: 486)
            Circle().fill(.black).frame(width: 466, height: 466)
            Capsule().fill(TafelFarbe.himmel).frame(width: 4, height: 26).offset(y: -215).rotationEffect(.degrees(60))
            Text("ja").font(Sundartha.grotesk(18, .medium)).foregroundStyle(TafelFarbe.himmel).position(x: 466 - 74 - 8, y: 98 + 9)
            Text("SENECA").mono(22, .medium, abstand: 1.4).foregroundStyle(TafelFarbe.himmel).position(x: 233, y: 150)
            Text(zahl.map(String.init).joined(separator: " ")).font(Sundartha.grotesk(80, .medium)).foregroundStyle(.white).position(x: 233, y: 240)
            Text("Steht das am iPhone?").font(Sundartha.grotesk(24)).foregroundStyle(TafelFarbe.zweit).position(x: 233, y: 320)
        }
        .frame(width: 466, height: 466)
        .scaleEffect(0.34)
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .combine)
    }
}

private struct CodeKamera: UIViewRepresentable {
    var gelesen: (String) -> Void

    func makeCoordinator() -> Leser { Leser(gelesen: gelesen) }

    func makeUIView(context: Context) -> Vorschau {
        let v = Vorschau()
        let s = AVCaptureSession()
        guard let geraet = AVCaptureDevice.default(for: .video), let eingang = try? AVCaptureDeviceInput(device: geraet), s.canAddInput(eingang) else { return v }
        s.addInput(eingang)
        let ausgang = AVCaptureMetadataOutput()
        guard s.canAddOutput(ausgang) else { return v }
        s.addOutput(ausgang)
        ausgang.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        ausgang.metadataObjectTypes = [.qr]
        v.ebene.session = s
        v.ebene.videoGravity = .resizeAspectFill
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        return v
    }

    func updateUIView(_ v: Vorschau, context: Context) {}

    static func dismantleUIView(_ v: Vorschau, coordinator: Leser) {
        let s = v.ebene.session
        DispatchQueue.global(qos: .userInitiated).async { s?.stopRunning() }
    }

    final class Vorschau: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var ebene: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Leser: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let gelesen: (String) -> Void
        init(gelesen: @escaping (String) -> Void) { self.gelesen = gelesen }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objekte: [AVMetadataObject], from connection: AVCaptureConnection) {
            for o in objekte { if let t = (o as? AVMetadataMachineReadableCodeObject)?.stringValue { gelesen(t) } }
        }
    }
}
