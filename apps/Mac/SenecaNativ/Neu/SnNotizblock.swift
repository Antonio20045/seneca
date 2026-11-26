import SwiftUI

struct SnBlattZeile: Identifiable, Equatable {
    let id: String
    let titel: String
    let meta: String
    let seit: String
    let fertig: Bool
    let ueberfaellig: Bool

    static func echt(_ t: SenecaTask, heute: String) -> SnBlattZeile {
        let seit = AufgabenLogic.seitText(plan: t.plan, heute: heute)
        return SnBlattZeile(id: t.id, titel: t.title, meta: t.projektName ?? "", seit: seit.map { "offen " + $0 } ?? "",
                            fertig: t.isDone, ueberfaellig: seit != nil && !t.isDone)
    }
}

struct SnNotizblockBlatt: View {
    let zeilen: [SnBlattZeile]
    var anlegen: (String) -> Void = { _ in }
    var umschalten: (String) -> Void = { _ in }
    @State private var eingabe = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notizblock").font(Schrift.serif(26, kursiv: true)).foregroundStyle(Farbe.blattTinte)
                .frame(height: 28.6, alignment: .leading)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                Text("+").font(Schrift.grotesk(18)).foregroundStyle(Farbe.blattTinte2).frame(width: 20)
                TextField("", text: $eingabe, prompt: Text("Notiz oder To-do …").foregroundStyle(Farbe.blattTinte2))
                    .textFieldStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(Farbe.blattTinte)
                    .onSubmit { anlegen(eingabe); eingabe = "" }
                    .accessibilityLabel("Neue Notiz")
            }
            .padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(Farbe.blattLinie).frame(height: 1) }
            if zeilen.isEmpty {
                Text("Für heute steht nichts an.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.blattTinte2)
                    .padding(.vertical, 10).padding(.leading, 32)
            }
            ForEach(zeilen) { zeile($0) }
        }
        .padding(.top, 20).padding(.leading, 46).padding(.trailing, 24).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Farbe.blatt
                .overlay { Image("BlattPapier").resizable().scaledToFill().opacity(0.3).blendMode(.multiply) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: Color(hex: 0x020816, deckkraft: 0.6), radius: 24, y: 24)
            .shadow(color: Color(hex: 0x020816, deckkraft: 0.25), radius: 3, y: 2)
        }
        .overlay(alignment: .leading) { Rectangle().fill(Farbe.blattRand).frame(width: 1).padding(.leading, 28) }
        .rotationEffect(.degrees(0.6))
        .snRein(0.42)
    }

    private func zeile(_ n: SnBlattZeile) -> some View {
        let fertig = n.fertig
        return HStack(alignment: .top, spacing: 12) {
            Button { withAnimation(Kurve.sn(0.3)) { umschalten(n.id) } } label: {
                ZStack {
                    Circle().fill(fertig ? Farbe.blattTinte : .clear)
                    Circle().strokeBorder(fertig ? Color.clear : (n.ueberfaellig ? Farbe.blattRot : Farbe.blattTinte2), lineWidth: 1.5)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Farbe.blatt).opacity(fertig ? 1 : 0)
                }
                .frame(width: 20, height: 20)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((fertig ? "Wieder offen: " : "Erledigt: ") + n.titel)
            VStack(alignment: .leading, spacing: 3) {
                Text(n.titel).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21))
                    .strikethrough(fertig)
                    .foregroundStyle(fertig ? Farbe.blattTinte2 : (n.ueberfaellig ? Farbe.blattRot : Farbe.blattTinte))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if !fertig, !(n.meta.isEmpty && n.seit.isEmpty) {
                    (Text(n.meta).foregroundColor(Farbe.blattTinte2)
                        + Text(n.meta.isEmpty || n.seit.isEmpty ? "" : " · ").foregroundColor(Farbe.blattTinte2)
                        + Text(n.seit).foregroundColor(Farbe.blattRot))
                        .font(Schrift.mono(12)).lineHeight(.exact(points: 16))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Farbe.blattLinie).frame(height: 1) }
    }
}
