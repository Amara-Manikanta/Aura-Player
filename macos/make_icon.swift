import AppKit

func createIcon() {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    
    // Background squircle
    let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
    let path = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.12, green: 0.05, blue: 0.28, alpha: 1.0),
            NSColor(red: 0.35, green: 0.12, blue: 0.65, alpha: 1.0),
            NSColor(red: 0.08, green: 0.45, blue: 0.85, alpha: 1.0)
        ]
    )
    gradient?.draw(in: path, angle: -45)
    
    // Glowing inner ring
    path.lineWidth = 12
    NSColor(white: 1.0, alpha: 0.25).setStroke()
    path.stroke()
    
    // Draw glowing symbols
    let ctx = NSGraphicsContext.current?.cgContext
    ctx?.saveGState()
    ctx?.setShadow(offset: CGSize(width: 0, height: -10), blur: 35, color: CGColor(red: 0.6, green: 0.2, blue: 1.0, alpha: 0.8))
    
    let sfConfig = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    if let noteImg = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(sfConfig) {
        let noteRect = NSRect(x: 232, y: 232, width: 560, height: 560)
        noteImg.draw(in: noteRect)
    }
    ctx?.restoreGState()
    
    image.unlockFocus()
    
    // Save iconset
    let fileManager = FileManager.default
    let iconsetPath = "/tmp/AuraPlayer.iconset"
    try? fileManager.removeItem(atPath: iconsetPath)
    try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
    
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes {
        let resized = NSImage(size: NSSize(width: s, height: s))
        resized.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        
        if let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            if s <= 512 {
                try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(s)x\(s).png"))
            }
            if s >= 32 {
                let half = s / 2
                try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(half)x\(half)@2x.png"))
            }
        }
    }
}

createIcon()
