import SwiftUI
import UIKit

public enum AuraTheme {
    // Brand Colors: soft violet, like light through tinted glass
    public static let primary = Color(hex: 0xB9A8FF)
    public static let primaryGradient = LinearGradient(
        colors: [Color(hex: 0x9D8CFF), Color(hex: 0xC48CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let ambientGradient = LinearGradient(
        colors: [Color(hex: 0xC48CFF).opacity(0.35), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Backgrounds & Surfaces: translucent white "glass" over the violet backdrop
    public static let backgroundDark = Color(hex: 0x2A2470)
    public static let surfaceCard = Color.white.opacity(0.10)
    public static let surfaceElevated = Color.white.opacity(0.15)
    public static let glassFill = Color.white.opacity(0.12)
    public static let glassBorder = Color.white.opacity(0.28)
    
    // Typography Tints
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.75)
    public static let textTertiary = Color.white.opacity(0.52)
}

/// The app's backdrop: a violet → indigo gradient with soft, blurred light blobs, so glass on top has
/// something to refract (the "liquid glass" look).
public struct AuraBackground: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x7B6BE0), Color(hex: 0x5446B8), Color(hex: 0x2E2678)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: 0xE38CF2).opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 150, y: -280)
            Circle()
                .fill(Color(hex: 0x6FB7FF).opacity(0.45))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -170, y: 60)
            Circle()
                .fill(Color(hex: 0xA77BFF).opacity(0.5))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 120, y: 380)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

public extension View {
    /// Liquid glass panel: Apple's real glass on iOS 26, frosted material with a light rim before that.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            // A little white tint keeps the glass light and airy on the violet backdrop
            let glass = Glass.regular.tint(Color.white.opacity(0.12))
            self.glassEffect(interactive ? glass.interactive() : glass,
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        }
    }
}

// MARK: - Player Theme Selection

public enum PlayerTheme: String, CaseIterable, Identifiable, Codable {
    case modern = "Modern Glass"
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
        case .modern: return "Liquid glass design with soft violet light"
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
