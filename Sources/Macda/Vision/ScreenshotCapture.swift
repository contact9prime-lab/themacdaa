import Foundation
import ScreenCaptureKit
import AppKit

/// Captures a single full-screen snapshot via ScreenCaptureKit (uses the same
/// Screen Recording permission as system-audio capture).
enum ScreenshotCapture {
    static func capturePNG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Macda", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "No display to capture."])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
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
}
