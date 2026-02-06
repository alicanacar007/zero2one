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
        let windowIds = visibleWindowIDsExcludingCurrentApp(in: bounds)
        guard !windowIds.isEmpty else {
            return captureMainDisplayPNGData()
        }
        guard let cgImage = CGImage(
            windowListFromArrayScreenBounds: bounds,
            windowArray: windowIds as CFArray,
            imageOption: .bestResolution
        ) else {
            return captureMainDisplayPNGData()
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }

    private func visibleWindowIDsExcludingCurrentApp(in bounds: CGRect) -> [CGWindowID] {
        let currentPID = NSRunningApplication.current.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: [CGWindowID] = []
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != currentPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            if let isOnscreen = info[kCGWindowIsOnscreen as String] as? Int, isOnscreen == 0 {
                continue
            }
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let windowBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               !bounds.intersects(windowBounds) {
                continue
            }
            ids.append(windowID)
        }
        return ids
    }
}
