import Foundation
import ScreenCaptureKit
import AppKit

/// Captures screen snapshots via ScreenCaptureKit (uses the same Screen
/// Recording permission as system-audio capture).
enum ScreenshotCapture {
    private static func mainFilter() async throws -> (SCContentFilter, SCDisplay) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Macda", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "No display to capture."])
        }
        return (SCContentFilter(display: display, excludingWindows: []), display)
    }

    /// Full-resolution PNG for an artifact.
    static func capturePNG() async throws -> Data {
        let (filter, display) = try await mainFilter()
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = true
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Macda", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't encode screenshot."])
        }
        return data
    }

    /// A tiny grayscale "signature" of the screen (cols×rows luma values) used to
    /// cheaply detect when the screen has changed significantly.
    static func captureLumaSignature(cols: Int = 32, rows: Int = 20) async throws -> [UInt8] {
        let (filter, _) = try await mainFilter()
        let config = SCStreamConfiguration()
        config.width = cols * 4
        config.height = rows * 4
        config.showsCursor = false
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        var buffer = [UInt8](repeating: 0, count: cols * rows)
        let space = CGColorSpaceCreateDeviceGray()
        buffer.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: cols, height: rows,
                                   bitsPerComponent: 8, bytesPerRow: cols, space: space,
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            }
        }
        return buffer
    }

    /// Mean absolute difference (0–255) between two equal-length signatures.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count)
    }
}
