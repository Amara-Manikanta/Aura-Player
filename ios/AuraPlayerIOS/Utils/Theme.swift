import SwiftUI
import UIKit

public enum AuraTheme {
    // Brand Colors
    public static let primary = Color(hex: 0xED5564)
    public static let primaryGradient = LinearGradient(
        colors: [Color(hex: 0xED5564), Color(hex: 0xFF758C)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let ambientGradient = LinearGradient(
        colors: [Color(hex: 0xED5564).opacity(0.35), Color(hex: 0x1A0E18), Color(hex: 0x0D0D11)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Backgrounds & Surfaces
    public static let backgroundDark = Color(hex: 0x0D0D11)
    public static let surfaceCard = Color(hex: 0x181822)
    public static let surfaceElevated = Color(hex: 0x222230)
    public static let glassFill = Color(hex: 0x1E1E28).opacity(0.75)
    public static let glassBorder = Color.white.opacity(0.12)
    
    // Typography Tints
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textTertiary = Color.white.opacity(0.38)
}

// Color Hex Extension
public extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

// Haptic Feedback Helper
public enum Haptics {
    public static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
