import SwiftUI
import AppKit
import ScreenCaptureKit

private struct DiktatHellKey: EnvironmentKey { static let defaultValue = 0.0 }

extension EnvironmentValues {
    var diktatHell: Double {
        get { self[DiktatHellKey.self] }
        set { self[DiktatHellKey.self] = newValue }
    }
}

enum DiktatUntergrund {
    static func hell(helligkeit: Double) -> Double {
        let x = min(1, max(0, (helligkeit - 0.4) / 0.22))
        return x * x * (3 - 2 * x)
    }

    @MainActor static func ausSystem() -> Double {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? 1 : 0
    }

    static func messe(zone: CGRect, schirm: NSScreen, ohneFenster nummer: Int) async -> Double? {
        guard CGPreflightScreenCaptureAccess(),
              let id = schirm.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let inhalt = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let anzeige = inhalt.displays.first(where: { $0.displayID == id }) else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: zone.minX - schirm.frame.minX, y: schirm.frame.maxY - zone.maxY, width: zone.width, height: zone.height)
        cfg.width = 48
        cfg.height = 10
        cfg.showsCursor = false
        let filter = SCContentFilter(display: anzeige, excludingWindows: inhalt.windows.filter { $0.windowID == CGWindowID(nummer) })
        guard let bild = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        return helligkeit(bild)
    }

    static func helligkeit(_ bild: CGImage) -> Double? {
        let b = 48, h = 10
        var px = [UInt8](repeating: 0, count: b * h * 4)
        let ok = px.withUnsafeMutableBytes { p -> Bool in
            guard let c = CGContext(data: p.baseAddress, width: b, height: h, bitsPerComponent: 8, bytesPerRow: b * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(bild, in: CGRect(x: 0, y: 0, width: b, height: h))
            return true
        }
        guard ok else { return nil }
        var summe = 0.0
        for i in stride(from: 0, to: px.count, by: 4) { summe += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2]) }
        return summe / Double(b * h) / 255
    }
}
