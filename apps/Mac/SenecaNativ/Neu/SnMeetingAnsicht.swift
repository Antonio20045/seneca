import SwiftUI

struct SnMeetingAnsicht: View {
    var termin: SenecaStand.Termin
    var todos: [SenecaStand.Todo]
    var zurueck: () -> Void
    var notiere: (String) -> Void
    var uebernimm: (SenecaStand.Meeting.Angebot) -> Void
    @State private var gesendet: Set<String> = []

    private var m: SenecaStand.Meeting { termin.meeting ?? SenecaStand.Meeting(grund: "", phase: "vorher", du: [], seneca: []) }

    private var kopf: String {
        let phase = ["vorher": "", "laeuft": " · LÄUFT GERADE", "danach": " · VORBEI"][m.phase] ?? ""
        return "MEETING · \(HeuteTafelLogik.uhr(termin.start)) · \(SnTageskalender.dauer(termin.ende - termin.start))\(phase) · ERKANNT AN \(m.grund.uppercased())".uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("‹ Heute", action: zurueck).buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
            Text(kopf).font(Schrift.mono(11)).kerning(1.2).foregroundStyle(TafelFarbe.koralle).padding(.top, 18).padding(.bottom, 10)
            Text(termin.titel).font(Schrift.serif(40)).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let mit = termin.mit, !mit.isEmpty { Text("mit " + mit.joined(separator: ", ")).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.leise).padding(.top, 6) }
            if m.du.isEmpty && m.seneca.isEmpty {
                Text(m.phase == "laeuft" ? "Das Meeting läuft. Danach bietet Seneca die Nachbereitung an." : "Dazu gibt es nichts mehr anzubieten.").font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.leise).padding(.top, 30)
            }
            if !m.du.isEmpty {
                titel("DU")
                ForEach(m.du) { d in zeile(d.text, mark: todos.contains { $0.titel == d.text } || gesendet.contains(d.id), knopf: "Als To-do", fertig: "Steht in deinen To-dos") { gesendet.insert(d.id); notiere(d.text) } }
            }
            if !m.seneca.isEmpty {
                titel("SENECA KANN")
                ForEach(m.seneca) { a in zeile(a.text, mark: a.genommen || gesendet.contains(a.id), knopf: "Übernehmen", fertig: "Übernommen") { gesendet.insert(a.id); uebernimm(a) } }
            }
        }
        .frame(width: 700, alignment: .leading).padding(.leading, 120).padding(.top, 104).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func titel(_ t: String) -> some View {
        Text(t).font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise).padding(.top, 34).padding(.bottom, 10)
    }

    private func zeile(_ text: String, mark: Bool, knopf: String, fertig: String, tu: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Text(text).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).foregroundStyle(mark ? TafelFarbe.leise : .white).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if mark { Text(fertig).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.gruen) }
            else { Button(knopf, action: tu).buttonStyle(MeetingKnopf(voll: false)) }
        }
        .padding(.vertical, 10).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
