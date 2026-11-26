import SwiftUI

struct FederEin: ViewModifier {
    var dauer: Double
    var versatz: CGFloat
    var skala: CGFloat
    var verzoegerung: Double
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0).offset(y: da ? 0 : versatz).scaleEffect(da ? 1 : skala)
            .onAppear { withAnimation(Kurve.feder(dauer).delay(verzoegerung)) { da = true } }
    }
}

struct VerlaufRein: ViewModifier {
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0).offset(y: da ? 0 : 10)
            .onAppear { withAnimation(Kurve.ease(0.5)) { da = true } }
    }
}

extension View {
    func bkRein(_ i: Int = 0) -> some View { modifier(FederEin(dauer: 0.65, versatz: 16, skala: 0.98, verzoegerung: 0.05 * Double(i))) }
    func verlaufRein() -> some View { modifier(VerlaufRein()) }
}
