import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
final class SnKopplung: ObservableObject {
    static let gemeinsam = SnKopplung()

    @Published private(set) var code: Kopplungscode?
    @Published private(set) var iphone = false
    private var minuten: Double = 10
    private var seit = Date()

    func oeffne(minuten: Double?) {
        self.minuten = minuten ?? 10
        iphone = false
        neu()
    }

    func neu() {
        Task {
            guard let a = Zugang.adresse, let s = await Zugang.schluesselAbseits() else { return }
            seit = Date()
            code = Kopplungscode(adresse: a, schluessel: s, name: Host.current().localizedName ?? "Dein Mac", bis: seit.addingTimeInterval(minuten * 60))
        }
    }

    func zu() { code = nil }

    func praesenz(_ zeilen: [[String: Any]]) {
        guard code != nil, !iphone else { return }
        let da = zeilen.contains { ($0["deviceFamily"] as? String)?.lowercased() == "iphone" && (($0["ts"] as? NSNumber)?.doubleValue ?? 0) >= seit.timeIntervalSince1970 * 1000 }
        guard da else { return }
        withAnimation(Kurve.sn(0.45)) { iphone = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Kurve.sn(0.6)) { code = nil }
        }
    }
}

struct SnKopplungSchicht: View {
    @ObservedObject var kopplung = SnKopplung.gemeinsam
    var stand: SenecaStand?

    var body: some View {
        if let c = kopplung.code {
            ZStack(alignment: .top) {
                SnGrund(fortschritt: 0)
                SnOrteKapsel(aktiv: .heute, fragen: stand.map { SnOrt.fragen($0) } ?? 0, waehle: { _ in }).opacity(0.5).padding(.top, 18)
                SnKopplungTafel(code: c, iphone: kopplung.iphone, neu: { kopplung.neu() })
            }
            .onExitCommand { kopplung.zu() }
            .transition(.opacity)
        }
    }
}

struct SnKopplungTafel: View {
    var code: Kopplungscode
    var iphone: Bool
    var neu: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { t in
            HStack(alignment: .center, spacing: 70) {
                links.frame(maxWidth: .infinity, alignment: .leading)
                rechts(t.date).frame(width: 300)
            }
            .frame(width: 980)
            .frame(maxWidth: .infinity)
            .padding(.top, 150)
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ERSTER START · SCHRITT 2 VON 3").font(Schrift.mono(14)).tracking(1.4).foregroundStyle(Color(hex: 0x8FB6E3))
            (Text("Jetzt das iPhone. ").font(Schrift.serif(56)).foregroundColor(.white)
                + Text("Halte die Kamera auf den Code.").font(Schrift.serif(56, kursiv: true)).foregroundColor(Color(hex: 0xCFE4FA)))
                .lineHeight(.exact(points: 58.2)).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            Text("Der Code enthält die Adresse deines Macs und einen Schlüssel. Er gilt zehn Minuten und nur für ein Gerät.")
                .font(Schrift.grotesk(19)).foregroundStyle(Color(hex: 0xBAC1CB)).lineHeight(.exact(points: 28)).fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            VStack(alignment: .leading, spacing: 14) {
                schritt("Seneca läuft auf diesem Mac", fertig: true)
                schritt("iPhone verbinden", fertig: iphone)
                schritt("Uhr verbinden · geht auch später", fertig: false, leise: true)
            }
            .padding(.top, 30)
        }
    }

    private func schritt(_ text: String, fertig: Bool, leise: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if fertig {
                    Circle().fill(Color(hex: 0x6BD98F))
                    Path { p in p.move(to: CGPoint(x: 2.5, y: 6.2)); p.addLine(to: CGPoint(x: 5, y: 8.6)); p.addLine(to: CGPoint(x: 9.6, y: 3.6)) }
                        .stroke(Color(hex: 0x062012), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(Color(hex: leise ? 0x6B7686 : 0x8FB6E3), lineWidth: 2)
                }
            }
            .frame(width: 24, height: 24)
            Text(text).font(Schrift.grotesk(18)).foregroundStyle(leise ? Color(hex: 0x939EAD) : .white)
        }
    }

    private func rechts(_ jetzt: Date) -> some View {
        let gilt = code.gilt(jetzt)
        return VStack(spacing: 16) {
            Image(nsImage: Self.qr(code.text))
                .interpolation(.none).resizable().frame(width: 236, height: 236)
                .padding(32).background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .opacity(gilt ? 1 : 0.25)
            HStack(spacing: 0) {
                Text(gilt ? "NOCH \(Kopplungscode.rest(code.bis, jetzt)) GÜLTIG · " : "ABGELAUFEN · ")
                Button("NEUER CODE", action: neu).buttonStyle(.plain)
            }
            .font(Schrift.mono(14)).foregroundStyle(Color(hex: 0x939EAD))
        }
    }

    static func qr(_ text: String) -> NSImage {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        let farbe = CIFilter.falseColor()
        farbe.inputImage = f.outputImage
        farbe.color0 = CIColor(red: 0x0B / 255, green: 0x14 / 255, blue: 0x24 / 255)
        farbe.color1 = CIColor.white
        guard let bild = farbe.outputImage, let cg = CIContext().createCGImage(bild, from: bild.extent) else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: bild.extent.width, height: bild.extent.height))
    }
}
