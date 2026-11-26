import SwiftUI

struct WidgetFace: View {
    enum Art { case rechteck, zeile, kreis, home }

    let lines: WidgetLines
    var inline = false
    var art: Art = .rechteck

    private static func serif(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size, relativeTo: .headline) }
    private static func grotesk(_ size: CGFloat) -> Font { .custom("SpaceGrotesk-Regular", size: size, relativeTo: .caption) }

    var body: some View {
        switch inline ? .zeile : art {
        case .zeile:
            Text(lines.jetzt.map { "\($0) \(lines.jetztBis ?? "")" } ?? lines.inline)
                .accessibilityLabel(lines.spoken)
        case .kreis: kreis
        case .rechteck: rechteck
        case .home: home
        }
    }

    private var rechteck: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let jetzt = lines.jetzt {
                Text("Jetzt \(jetzt)" + (lines.jetztBis.map { " \($0)" } ?? ""))
                    .font(Self.grotesk(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            headline(21)
                .lineLimit(lines.jetzt == nil ? 2 : 1)
                .minimumScaleFactor(0.8)
            if lines.jetzt == nil, let place = lines.place {
                Text(place)
                    .font(Self.grotesk(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken)
    }

    private var kreis: some View {
        VStack(spacing: 0) {
            if let time = lines.time {
                Text("um").font(Self.grotesk(11)).foregroundStyle(.secondary)
                Text(time).font(Self.grotesk(17)).monospacedDigit().minimumScaleFactor(0.7)
            } else if let bis = lines.jetztBis {
                Text("bis").font(Self.grotesk(11)).foregroundStyle(.secondary)
                Text(bis.replacingOccurrences(of: "bis ", with: "")).font(Self.grotesk(17)).monospacedDigit().minimumScaleFactor(0.7)
            } else {
                Image(systemName: lines.kind == .stale ? "arrow.clockwise" : "checkmark").font(.system(size: 18, weight: .medium))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let jetzt = lines.jetzt {
                Text("Jetzt").font(Self.grotesk(13)).foregroundStyle(.white.opacity(0.62))
                Text(jetzt).font(Self.serif(24)).lineLimit(2).minimumScaleFactor(0.8).padding(.top, 2)
                if let bis = lines.jetztBis { Text(bis).font(Self.grotesk(13)).foregroundStyle(.white.opacity(0.62)).padding(.top, 2) }
                Spacer(minLength: 6)
                if let time = lines.time, let title = lines.title {
                    (Text(time).monospacedDigit().foregroundColor(.white.opacity(0.62)) + Text("  " + title))
                        .font(Self.grotesk(13)).lineLimit(1)
                } else {
                    Text(lines.headline).font(Self.grotesk(13)).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
                }
            } else if let time = lines.time, let title = lines.title {
                Text("Als Nächstes").font(Self.grotesk(13)).foregroundStyle(.white.opacity(0.62))
                Text(title).font(Self.serif(26)).lineLimit(3).minimumScaleFactor(0.8).padding(.top, 2)
                Spacer(minLength: 6)
                (Text(time).monospacedDigit() + Text(lines.place.map { "  " + $0 } ?? "").foregroundColor(.white.opacity(0.62)))
                    .font(Self.grotesk(13)).lineLimit(1)
            } else {
                Text(lines.headline).font(Self.serif(lines.kind == .stale ? 20 : 24)).lineLimit(4).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken)
    }

    @ViewBuilder private func headline(_ size: CGFloat) -> some View {
        if let time = lines.time, let title = lines.title {
            Text(time).font(Self.grotesk(13)).monospacedDigit().foregroundStyle(.secondary)
                + Text("  ").font(Self.grotesk(13))
                + Text(title).font(Self.serif(size))
        } else {
            Text(lines.headline).font(Self.serif(lines.kind == .stale ? 18 : 20))
        }
    }
}
