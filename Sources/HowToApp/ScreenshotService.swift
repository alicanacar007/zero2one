import AppKit

struct ScreenshotService {
    func captureMainDisplayPNGData() -> Data? {
        let displayId = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayId)
        guard let cgImage = CGWindowListCreateImage(
            bounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}

