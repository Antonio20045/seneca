import SwiftUI
import AVFoundation

struct MeetingKnopf: ButtonStyle {
    var voll = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Schrift.grotesk(14, .medium)).foregroundStyle(voll ? TafelFarbe.aufHimmel : TafelFarbe.text).padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(voll ? TafelFarbe.himmel : .clear)).overlay { if !voll { Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MeetingKarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: Inhalt
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { inhalt }.padding(.horizontal, 18).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }
}

@MainActor
final class MeetingSpieler: ObservableObject {
    @Published private(set) var laeuft = false
    @Published private(set) var zeit: Double = 0
    private var spieler: [(AVAudioPlayer, Double)] = []
    private var takt: Timer?

    func lade(_ name: String?) {
        guard spieler.isEmpty, let name, let o = MeetingDienst.aufnahmenOrdner?.appendingPathComponent(name) else { return }
        let m = MeetingArchiv.liesMeta(o)
        spieler = [("mikrofon.wav", m?.versatzMikro ?? 0), ("systemton.wav", m?.versatzSystem ?? 0)].compactMap { d, v in (try? AVAudioPlayer(contentsOf: o.appendingPathComponent(d))).map { ($0, v) } }
    }

    func spiele(ab t: Double? = nil) {
        if laeuft, t == nil { spieler.forEach { $0.0.pause() }; laeuft = false; takt?.invalidate(); return }
        if let t { zeit = t }
        guard let start = spieler.first?.0.deviceCurrentTime else { return }
        for (p, v) in spieler { p.currentTime = max(0, zeit - v); p.play(atTime: start + 0.05) }
        laeuft = true
        takt?.invalidate()
        takt = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { guard let self, let (p, v) = self.spieler.first else { return }; self.zeit = p.currentTime + v; if !p.isPlaying { self.laeuft = false } } }
    }
}

struct SnMeetingErgebnis: View {
    var e: MeetingErgebnis
    var datei: URL
    var dienst: MeetingDienst?
    var zurueck: (() -> Void)?
    var todos: [SenecaStand.Todo] = []
    @StateObject private var spieler = MeetingSpieler()
    @State private var aus: Set<Int> = []
    @State private var texte: [Int: String] = [:]
    @State private var bearbeiten = false
    @State private var rueck: Int?
    @State private var gesendet = false
    @State private var neuerName: (Int, String)?
    @State private var huelle: [Double] = []

    private func uhr(_ s: Double) -> String { HeuteTafelLogik.uhr((e.beginn.timeIntervalSince1970 + s) * 1000) }
    private var vorschlaege: [MeetingAufgabe] { e.alle }
    private func doppelt(_ a: MeetingAufgabe) -> SenecaStand.Todo? { MeetingDienst.doppelt(a, todos) }
    private var gewaehlt: [MeetingAufgabe] { vorschlaege.enumerated().filter { !aus.contains($0.offset) && doppelt($0.element) == nil }.map { var a = $0.element; a.text = texte[$0.offset] ?? a.text; return a } }

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            links.frame(width: 700, alignment: .leading)
            rechts.frame(width: 460).padding(.top, 46)
        }
        .padding(.leading, 120).padding(.top, 104).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { spieler.lade(e.aufnahme); if let n = e.aufnahme, let o = MeetingDienst.aufnahmenOrdner?.appendingPathComponent(n) { huelle = MeetingWav.huelle(o.appendingPathComponent("mikrofon.wav"), teile: 38) } }
        .background { Button("") { spieler.spiele() }.keyboardShortcut(.space, modifiers: []).opacity(0) }
    }

    private func titel(_ t: String, oben: CGFloat = 26) -> some View {
        Text(t).font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise).padding(.top, oben).padding(.bottom, 10)
    }

    private var kopf: String {
        let ende = e.beginn.addingTimeInterval(e.dauer).timeIntervalSince1970 * 1000
        return [(e.termin ?? e.titel), uhr(0) + "–" + HeuteTafelLogik.uhr(ende), "\(Int((e.dauer / 60).rounded())) Min"].joined(separator: " · ").uppercased()
    }

    private var satz: (String, String) {
        let s = e.zusammenfassung.split(separator: ".", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) + "." } ?? ""
        guard let k = s.range(of: ", ") else { return (s, "") }
        return (String(s[..<k.upperBound]), String(s[k.upperBound...]))
    }

    @ViewBuilder private var links: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let zurueck { Button("‹ Heute", action: zurueck).buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise) }
            Text(kopf).font(Schrift.mono(11)).kerning(1.2).foregroundStyle(TafelFarbe.leise).monospacedDigit().padding(.top, 18).padding(.bottom, 10)
            if e.stand == .laeuft || dienst?.fasstSeit != nil { fasst } else {
                (Text(satz.0).foregroundColor(.white) + Text(satz.1).font(Schrift.serif(40, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                    .font(Schrift.serif(40)).lineHeight(.exact(points: 43)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if !e.entscheidungen.isEmpty {
                    titel("ENTSCHIEDEN")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(e.entscheidungen.enumerated()), id: \.offset) { _, t in
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(t).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if let st = MeetingTranskript.stelle(t, in: e.segmente) {
                                    Button("▸ " + uhr(st)) { spieler.spiele(ab: st) }.buttonStyle(.plain).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.himmel).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                if !vorschlaege.isEmpty { vorschlagListe }
                if !e.offeneFragen.isEmpty {
                    titel("OFFEN")
                    ForEach(Array(e.offeneFragen.enumerated()), id: \.offset) { _, f in
                        let teil = f.split(separator: "?", maxSplits: 1).map(String.init)
                        (Text(teil[0] + (teil.count > 1 ? "?" : "")).foregroundColor(TafelFarbe.text) + Text(teil.count > 1 ? teil[1] : "").foregroundColor(TafelFarbe.leise))
                            .font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var fasst: some View {
        TimelineView(.periodic(from: .now, by: 1)) { z in
            let s = z.date.timeIntervalSince(dienst?.fasstSeit ?? z.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Circle().fill(TafelFarbe.himmel).frame(width: 7, height: 7)
                    Text("Fasse zusammen").font(Schrift.grotesk(15, .medium)).foregroundStyle(.white)
                    GeometryReader { g in Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) { Capsule().fill(TafelFarbe.himmel).frame(width: g.size.width * min(0.95, s / MeetingDienst.regel("meeting_zusammenfassen_ziel_s", 60))) } }.frame(height: 3)
                    Text(MeetingTranskript.zeit(s)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).monospacedDigit()
                }
                Text("Die Mitschrift ist schon lesbar.").font(Schrift.grotesk(13.5)).foregroundStyle(TafelFarbe.leise)
            }
            .padding(.horizontal, 18).padding(.vertical, 16).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06))).padding(.top, 26)
        }
    }

    private var vorschlagListe: some View {
        VStack(alignment: .leading, spacing: 0) {
            titel("VORSCHLÄGE FÜR DICH · DU ENTSCHEIDEST")
            ForEach(Array(vorschlaege.enumerated()), id: \.offset) { i, a in
                let d = doppelt(a), an = d == nil && !aus.contains(i)
                HStack(spacing: 12) {
                    Button { if d == nil { if aus.contains(i) { aus.remove(i) } else { aus.insert(i) } } } label: {
                        RoundedRectangle(cornerRadius: 5).fill(an ? TafelFarbe.himmel : .clear).frame(width: 18, height: 18)
                            .overlay { if an { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(TafelFarbe.aufHimmel) } else { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5) } }
                    }.buttonStyle(.plain).disabled(gesendet)
                    VStack(alignment: .leading, spacing: 0) {
                        if bearbeiten, d == nil { TextField("", text: Binding(get: { texte[i] ?? a.text }, set: { texte[i] = $0 })).textFieldStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(.white) }
                        else { Text(texte[i] ?? a.text).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).foregroundStyle(d == nil ? .white : TafelFarbe.leise) }
                        Text(d.map { ["gibt es schon", HeuteTafelLogik.todoZeile($0), "wird nicht doppelt angelegt"].filter { !$0.isEmpty }.joined(separator: " · ") }
                             ?? ([a.fuerAntonio ? "To-do" : a.wer] + (a.fuerAntonio ? [e.termin?.components(separatedBy: " · ").last].compactMap { $0 } : []) + [a.termin.map { a.fuerAntonio ? "bis " + $0 : $0 }].compactMap { $0 }).joined(separator: " · "))
                            .font(Schrift.grotesk(12.5)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.leise)
                    }
                    Spacer(minLength: 0)
                    if !a.fuerAntonio { Text("AUFTRAG").font(Schrift.mono(10)).kerning(1).foregroundStyle(TafelFarbe.gruen).padding(.horizontal, 8).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 6).fill(TafelFarbe.gruen.opacity(0.14))) }
                }
                .padding(.vertical, 10).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
            HStack(spacing: 10) {
                if gesendet { Text("Übernommen").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.leise) }
                else if let r = rueck { Button("Rückgängig · \(r) s") { rueck = nil }.buttonStyle(MeetingKnopf(voll: false)) }
                else {
                    Button("\(gewaehlt.count) übernehmen") { uebernimm() }.buttonStyle(MeetingKnopf()).disabled(gewaehlt.isEmpty)
                    Button(bearbeiten ? "Fertig" : "Bearbeiten") { bearbeiten.toggle() }.buttonStyle(MeetingKnopf(voll: false))
                }
            }.padding(.top, 14)
        }
    }

    private func uebernimm() {
        let auswahl = gewaehlt, n = Int(AppRegel.wert("rueckgaengig_s", 5))
        rueck = n; bearbeiten = false
        Task {
            for i in stride(from: n - 1, through: 0, by: -1) { try? await Task.sleep(for: .seconds(1)); guard rueck != nil else { return }; rueck = i }
            rueck = nil; gesendet = true; dienst?.uebernimm(auswahl)
        }
    }

    @ViewBuilder private var rechts: some View {
        let sprecher = MeetingTranskript.sprecherAnzahl(e.segmente)
        let anteil = Dictionary(grouping: e.segmente, by: \.sprecher).mapValues { $0.reduce(0) { $0 + $1.ende - $1.start } }
        let summe = max(1, anteil.values.reduce(0, +))
        let marken = e.marken.map { ($0, "gemerkt") } + e.entscheidungen.compactMap { t in MeetingTranskript.stelle(t, in: e.segmente).flatMap { st in e.marken.contains { abs($0 - st) < 90 } ? nil : st }.map { ($0, t.split(separator: " ").dropFirst().first { $0.first?.isUppercase == true }.map { String($0).trimmingCharacters(in: .punctuationCharacters) } ?? "") } }
        VStack(alignment: .leading, spacing: 14) {
            MeetingKarte {
                HStack(spacing: 12) {
                    Button { spieler.spiele() } label: { Circle().fill(.white).frame(width: 36, height: 36).overlay(Image(systemName: spieler.laeuft ? "pause" : "play").font(.system(size: 13, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel)) }.buttonStyle(.plain)
                    GeometryReader { g in
                        HStack(spacing: 2) { ForEach(Array(huelle.enumerated()), id: \.offset) { i, h in RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(Double(i) / Double(max(1, huelle.count)) < spieler.zeit / max(1, e.dauer) ? 0.75 : 0.3)).frame(width: 3, height: 6 + 16 * min(1, h * 2.5)) } }
                            .frame(maxHeight: .infinity)
                        ForEach(Array(marken.prefix(2).enumerated()), id: \.offset) { i, m in Rectangle().fill(TafelFarbe.himmel.opacity(i == 0 ? 1 : 0.55)).frame(width: 2, height: 42).offset(x: g.size.width * m.0 / max(1, e.dauer), y: -6) }
                    }.frame(height: 30)
                    Text(MeetingTranskript.zeit(e.dauer)).font(Schrift.mono(12)).foregroundStyle(TafelFarbe.zweit).monospacedDigit()
                }
                HStack(spacing: 16) {
                    ForEach(Array(marken.prefix(2).enumerated()), id: \.offset) { i, m in Button("▮ \(uhr(m.0)) \(m.1)") { spieler.spiele(ab: m.0) }.buttonStyle(.plain).foregroundStyle(i == 0 ? TafelFarbe.akzent : TafelFarbe.leise) }
                    Text("Leertaste spielt ab")
                }.font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).monospacedDigit()
            }
            if !sprecher.isEmpty {
                MeetingKarte {
                    Text("SPRECHER").font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
                    ForEach(sprecher, id: \.self) { n in
                        HStack(spacing: 8) {
                            if n == 1, e.rollen[1] != nil, e.namen[1] == nil { (Text("Du").foregroundColor(TafelFarbe.akzent) + Text(" · Mikrofon").foregroundColor(TafelFarbe.text)) }
                            else if let neu = neuerName, neu.0 == n {
                                Text("Sprecher \(n)").foregroundStyle(TafelFarbe.leise).strikethrough(); Text("→").foregroundStyle(TafelFarbe.aus)
                                TextField("", text: Binding(get: { neu.1 }, set: { neuerName = (n, $0) })).textFieldStyle(.plain).foregroundStyle(.white).fixedSize()
                                    .padding(.horizontal, 10).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TafelFarbe.himmel.opacity(0.6), lineWidth: 1))
                                    .onSubmit { dienst?.benenne(n, neu.1); neuerName = nil }
                            } else if let name = e.namen[n] {
                                Text("Sprecher \(n)").foregroundStyle(TafelFarbe.leise).strikethrough(); Text("→").foregroundStyle(TafelFarbe.aus); Text(name).foregroundStyle(.white)
                            } else if n >= 2, let k = e.kandidaten.first {
                                Text("Sprecher \(n) klingt wie \(k).").foregroundStyle(TafelFarbe.text)
                                Button("Ja, \(k)") { dienst?.benenne(n, k) }.buttonStyle(MeetingKnopf())
                                Button("Anderer Name") { neuerName = (n, "") }.buttonStyle(MeetingKnopf(voll: false))
                            } else { Button("Sprecher \(n)") { neuerName = (n, "") }.buttonStyle(.plain).foregroundStyle(TafelFarbe.text) }
                            Spacer(minLength: 0)
                            Text("\(Int((100 * (anteil[n] ?? 0) / summe).rounded())) %").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                        }.font(Schrift.grotesk(14))
                    }
                }
            }
            MeetingKarte {
                Text("MITSCHRIFT").font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
                let ziel = e.segmente.firstIndex(where: e.gemerkt) ?? max(0, e.segmente.count - 1)
                ForEach(Array(e.segmente.enumerated()).filter { $0.offset >= ziel - 1 && $0.offset <= ziel }, id: \.offset) { _, z in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(uhr(z.start)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).frame(width: 44, alignment: .leading)
                        Text(e.name(z.sprecher)).font(Schrift.grotesk(13.5, .medium)).foregroundStyle(z.sprecher == 1 ? TafelFarbe.akzent : .white).lineLimit(1).frame(width: 62, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(z.text).font(Schrift.grotesk(13.5)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                            if e.gemerkt(z) { Label("GEMERKT", systemImage: "bookmark").font(Schrift.mono(10)).foregroundStyle(TafelFarbe.akzent).padding(.horizontal, 7).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(TafelFarbe.himmel.opacity(0.16))).fixedSize() }
                        }
                    }
                }
                HStack {
                    Button("Ganze Mitschrift · \(e.segmente.reduce(0) { $0 + $1.text.split(separator: " ").count }.formatted(.number.grouping(.automatic).locale(Locale(identifier: "fr_FR")))) Wörter ▸") { NSWorkspace.shared.open(datei) }.buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel)
                    Spacer(); Text("durchsuchbar").foregroundStyle(TafelFarbe.leise)
                }.font(Schrift.grotesk(13)).padding(.top, 4)
            }
            (Text(datei.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~") + " · ") + Text("im Finder zeigen"))
                .font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).lineSpacing(4).onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([datei]) }.padding(.top, 4)
        }
    }
}
