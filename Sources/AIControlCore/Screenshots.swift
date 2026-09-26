import AppKit
import SwiftUI

/// Renders the menu-bar window with example accounts to PNG files for the README.
///
/// The view is drawn offscreen by AppKit itself, so no screen-recording permission is needed and no real
/// account ever appears in an image.
@MainActor
public func renderScreenshots(to directory: String) -> Int32 {
    _ = NSApplication.shared
    let shots: [(name: String, appearance: NSAppearance.Name, adding: CLIProvider?)] = [
        ("menu-dark", .darkAqua, nil), ("menu-light", .aqua, nil), ("add-account", .darkAqua, .claude)
    ]
    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for shot in shots {
            let appearance = NSAppearance(named: shot.appearance)
            let content = ControlView(adding: shot.adding)
                .environmentObject(ControlStore.demo())
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                .padding(24)
            let host = NSHostingView(rootView: content)
            host.appearance = appearance
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = host
            // Measured heights arrive asynchronously; let SwiftUI settle before sizing and drawing.
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.frame.size = host.fittingSize
                window.setContentSize(host.frame.size)
            }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return 1 }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(shot.name + ".png"))
            print("Wrote \(shot.name).png \(Int(host.bounds.width))x\(Int(host.bounds.height))")
        }
        return 0
    } catch {
        print("Could not write screenshots: \(error)")
        return 1
    }
}
