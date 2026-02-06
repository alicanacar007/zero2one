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
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }

    func captureMainDisplayExcludingAppWindowPNGData() -> Data? {
        let displayId = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayId)
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            return captureMainDisplayPNGData()
        }
        let windowId = CGWindowID(window.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            bounds,
            .optionOnScreenBelowWindow,
            windowId,
            .bestResolution
        ) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}
