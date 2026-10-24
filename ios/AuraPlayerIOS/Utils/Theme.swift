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

// MARK: - Player Theme Selection

public enum PlayerTheme: String, CaseIterable, Identifiable, Codable {
    case modern = "Modern AMOLED"
    case sansa = "Sansa e260 Retro"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .modern: return "iphone"
        case .sansa: return "opticaldisc.fill"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .modern: return "Dark AMOLED design with Echo Coral accents"
        case .sansa: return "SanDisk Sansa e260 MP3 player with neon blue virtual rotator"
        }
    }
}

// MARK: - SanDisk Sansa e260 Retro Theme Palette

public enum SansaTheme {
    // Chassis & Metallic Hardware
    public static let metallicDark = Color(hex: 0x12141B)
    public static let metallicMid = Color(hex: 0x1E212B)
    public static let metallicLight = Color(hex: 0x2E3342)
    public static let metallicHighlight = Color(hex: 0x485066)
    public static let metallicEdge = Color.white.opacity(0.22)
    
    public static let chassisGradient = LinearGradient(
        colors: [Color(hex: 0x2C303F), Color(hex: 0x1B1D26), Color(hex: 0x0F1015)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Screen & LCD Bezel
    public static let screenBezel = Color(hex: 0x08090C)
    public static let screenInnerBezel = Color(hex: 0x11131A)
    public static let lcdBacklight = Color(hex: 0x07111D)
    public static let lcdGlassReflection = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // The Iconic Sansa Electric Neon Blue Glowing Ring
    public static let neonBlue = Color(hex: 0x00D4FF)
    public static let neonBlueGlow = Color(hex: 0x0088FF)
    public static let neonBlueDark = Color(hex: 0x004CB3)
    public static let neonBlueGradient = LinearGradient(
        colors: [Color(hex: 0x66E5FF), Color(hex: 0x00D4FF), Color(hex: 0x0066FF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // LCD Digital Text & Indicators
    public static let lcdTextPrimary = Color.white
    public static let lcdTextCyan = Color(hex: 0x00E5FF)
    public static let lcdTextSecondary = Color(hex: 0x7E9EB8)
    public static let lcdProgressBar = Color(hex: 0x00D4FF)
    public static let lcdProgressTrack = Color(hex: 0x132338)
    
    // Buttons
    public static let buttonSurface = Color(hex: 0x1C202C)
    public static let buttonSurfaceActive = Color(hex: 0x2A3042)
    public static let buttonBorder = Color.white.opacity(0.16)
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
