import SwiftUI

enum DevotionalDeity {
    case ayyappa, shiva, rama, venkateswara, saiBaba, ganesha, generic
    
    static func detect(track: MediaTrack?) -> DevotionalDeity? {
        guard let track = track else { return nil }
        let text = "\(track.title) \(track.artist) \(track.album ?? "") \(track.genre ?? "")".lowercased()
        
        let isDevotional = (track.genre?.localizedCaseInsensitiveContains("devotional") == true) ||
            ["ayyappa", "manikanta", "harivarasanam", "uyyala", "yedakeltav",
             "shiva", "manjunatha", "lingashtakam", "mahaprana",
             "rama", "ramadasu", "bhadra shaila", "andari bandhuvaya",
             "venkateswara", "om namo venkatesaya", "adhivo", "annamayya",
             "sai baba", "shirdi", "vakratunda", "vinayaka", "swamy", "saranam"].contains { text.contains($0) }
        
        guard isDevotional else { return nil }
        
        if ["ayyappa", "manikanta", "harivarasanam", "uyyala", "yedakeltav", "sabarimala",
            "erumeli", "pamba", "irumudi", "bhagavan saranam", "pallikattu", "karthika"].contains(where: { text.contains($0) }) {
            return .ayyappa
        } else if ["manjunatha", "shiva", "mahaprana", "lingashtakam", "brahma murari", "shankara"].contains(where: { text.contains($0) }) {
            return .shiva
        } else if ["ramadasu", "bhadra shaila", "andari bandhuvaya", "ramayya", "kodandaram", "sitarama", "ayodhya"].contains(where: { text.contains($0) }) {
            return .rama
        } else if ["venkateswara", "akhilanda koti", "om namo venkatesaya", "adhivo", "annamayya", "govinda"].contains(where: { text.contains($0) }) {
            return .venkateswara
        } else if ["sai baba", "shirdi", "sai saranam", "baba sai baba"].contains(where: { text.contains($0) }) {
            return .saiBaba
        } else if ["vakratunda", "kanipaka", "vinayaka", "ganapathi", "vighneshwara"].contains(where: { text.contains($0) }) {
            return .ganesha
        }
        return .generic
    }
}

/// Animated divine background with rotating radiant halo, floating deepam embers,
/// and Lord Ayyappa / deity idol illustration.
struct DevotionalGodEffectsView: View {
    let deity: DevotionalDeity
    var isPlaying: Bool = true
    
    @State private var particles: [Spark] = (0..<26).map { _ in
        Spark(
            xNorm: Double.random(in: 0.05...0.95),
            speed: Double.random(in: 0.15...0.35),
            size: Double.random(in: 2.5...5.5),
            wobblePhase: Double.random(in: 0...(2 * .pi)),
            color: [Color.yellow, Color.orange, Color(red: 1.0, green: 0.85, blue: 0.4), Color.white].randomElement()!
        )
    }
    
    private struct Spark {
        let xNorm: Double
        let speed: Double
        let size: Double
        let wobblePhase: Double
        let color: Color
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.96 + 0.08 * sin(time * 1.8)
            let jewelGlow = 0.6 + 0.4 * sin(time * 3.5)
            let haloRotation = (time * 9.0).truncatingRemainder(dividingBy: 360.0)
            
            ZStack {
                // 1. Deep Saffron & Golden Sanctum Glow
                RadialGradient(
                    colors: [
                        Color(red: 0.42, green: 0.15, blue: 0.0, opacity: 0.42 * pulse),
                        Color(red: 0.22, green: 0.08, blue: 0.0, opacity: 0.25),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 360 * pulse
                )
                .ignoresSafeArea()
                
                // 2. Rising Deepam Sparks / Aarthi Embers
                Canvas { context, size in
                    for p in particles {
                        let progress = (time * p.speed + p.wobblePhase / (2 * .pi)).truncatingRemainder(dividingBy: 1.0)
                        let y = size.height * (1.0 - progress)
                        let xWobble = sin(progress * 4 * .pi + p.wobblePhase) * 20.0
                        let x = min(max(0, p.xNorm * size.width + xWobble), size.width)
                        let alpha = sin(progress * .pi) * 0.75
                        
                        let rect = CGRect(x: x - p.size / 2, y: y - p.size / 2, width: p.size, height: p.size)
                        context.opacity = alpha
                        context.fill(Circle().path(in: rect), with: .color(p.color))
                    }
                }
                
                // 3. Central Deity Arch & Idol
                ZStack {
                    Canvas { context, size in
                        let cx = size.width / 2.0
                        let cy = size.height / 2.0
                        let r = min(size.width, size.height) * 0.38
                        
                        // A. Rotating Sunbeam Rays (Prabhavali)
                        var rayContext = context
                        rayContext.translateBy(x: cx, y: cy)
                        rayContext.rotate(by: .degrees(haloRotation))
                        
                        let numRays = 24
                        for i in 0..<numRays {
                            let angle = (Double(i) * 360.0 / Double(numRays)) * (.pi / 180.0)
                            let inner = r * 0.45
                            let outer = r * (0.85 + 0.10 * pulse)
                            let start = CGPoint(x: inner * cos(angle), y: inner * sin(angle))
                            let end = CGPoint(x: outer * cos(angle), y: outer * sin(angle))
                            
                            var rayPath = Path()
                            rayPath.move(to: start)
                            rayPath.addLine(to: end)
                            
                            rayContext.stroke(
                                rayPath,
                                with: .color(Color.yellow.opacity(0.24)),
                                lineWidth: 2.5
                            )
                        }
                        
                        // B. Halo Center Disc
                        let haloRect = CGRect(x: cx - r * 0.65 * pulse, y: cy - r * 0.65 * pulse, width: r * 1.30 * pulse, height: r * 1.30 * pulse)
                        context.fill(
                            Circle().path(in: haloRect),
                            with: .radialGradient(
                                Gradient(colors: [Color.yellow.opacity(0.22 * pulse), Color.orange.opacity(0.10 * pulse), Color.clear]),
                                center: CGPoint(x: cx, y: cy),
                                startRadius: 0,
                                endRadius: r * 0.65 * pulse
                            )
                        )
                    }
                    .frame(width: 320, height: 320)
                    
                    // Authentic Swami Ayyappa Idol Image with gentle breathing animation
                    if deity == .ayyappa {
                        AyyappaIdolImageView()
                            .scaleEffect(min(max(0.96, pulse), 1.04))
                            .opacity(0.88)
                            .shadow(color: Color.orange.opacity(0.35), radius: 20)
                    }
                }
            }
        }
    }
    
    private func drawAyyappaIdol(context: GraphicsContext, cx: Double, cy: Double, r: Double, pulse: Double, jewelGlow: Double) {
        let goldPrimary = Color(red: 1.0, green: 0.84, blue: 0.31, opacity: 0.55)
        let goldShine = Color(red: 1.0, green: 0.98, blue: 0.77, opacity: 0.85)
        let goldDeep = Color(red: 1.0, green: 0.55, blue: 0.0, opacity: 0.45)
        
        let idolWidth = r * 1.05
        let idolHeight = r * 1.35
        let baseBottom = cy + idolHeight * 0.40
        let headCenterY = cy - idolHeight * 0.24
        
        // 1. Lotus Pedestal (Padmasanam)
        var lotusPath = Path()
        lotusPath.move(to: CGPoint(x: cx - idolWidth * 0.42, y: baseBottom))
        lotusPath.addQuadCurve(to: CGPoint(x: cx + idolWidth * 0.42, y: baseBottom), control: CGPoint(x: cx, y: baseBottom - 16))
        lotusPath.addQuadCurve(to: CGPoint(x: cx - idolWidth * 0.42, y: baseBottom), control: CGPoint(x: cx, y: baseBottom + 20))
        lotusPath.closeSubpath()
        context.fill(lotusPath, with: .color(goldDeep))
        context.stroke(lotusPath, with: .color(goldShine), lineWidth: 2.0)
        
        // 2. Seated Folded Legs with Raised Knees in Yoga Asana
        var legsPath = Path()
        legsPath.move(to: CGPoint(x: cx - idolWidth * 0.40, y: baseBottom - 4))
        legsPath.addCurve(
            to: CGPoint(x: cx - idolWidth * 0.18, y: baseBottom - 65),
            control1: CGPoint(x: cx - idolWidth * 0.42, y: baseBottom - 40),
            control2: CGPoint(x: cx - idolWidth * 0.25, y: baseBottom - 75)
        )
        legsPath.addQuadCurve(to: CGPoint(x: cx + idolWidth * 0.18, y: baseBottom - 65), control: CGPoint(x: cx, y: baseBottom - 35))
        legsPath.addCurve(
            to: CGPoint(x: cx + idolWidth * 0.40, y: baseBottom - 4),
            control1: CGPoint(x: cx + idolWidth * 0.25, y: baseBottom - 75),
            control2: CGPoint(x: cx + idolWidth * 0.42, y: baseBottom - 40)
        )
        legsPath.closeSubpath()
        context.fill(legsPath, with: .color(goldPrimary))
        context.stroke(legsPath, with: .color(goldShine), lineWidth: 2.0)
        
        // 3. Sacred Yogapatta (Gold knee band)
        let yogapattaY = baseBottom - 54
        var yogapattaPath = Path()
        yogapattaPath.move(to: CGPoint(x: cx - idolWidth * 0.24, y: yogapattaY))
        yogapattaPath.addQuadCurve(to: CGPoint(x: cx + idolWidth * 0.24, y: yogapattaY), control: CGPoint(x: cx, y: yogapattaY + 12))
        yogapattaPath.addQuadCurve(to: CGPoint(x: cx - idolWidth * 0.24, y: yogapattaY), control: CGPoint(x: cx, y: yogapattaY + 20))
        yogapattaPath.closeSubpath()
        context.fill(yogapattaPath, with: .color(goldShine))
        context.stroke(yogapattaPath, with: .color(Color.yellow), lineWidth: 1.5)
        
        // 4. Torso & Arms
        let torsoTopY = headCenterY + 20
        var torsoPath = Path()
        torsoPath.move(to: CGPoint(x: cx - idolWidth * 0.24, y: torsoTopY + 10))
        torsoPath.addQuadCurve(to: CGPoint(x: cx - idolWidth * 0.12, y: baseBottom - 40), control: CGPoint(x: cx - idolWidth * 0.16, y: torsoTopY + 40))
        torsoPath.addLine(to: CGPoint(x: cx + idolWidth * 0.12, y: baseBottom - 40))
        torsoPath.addQuadCurve(to: CGPoint(x: cx + idolWidth * 0.24, y: torsoTopY + 10), control: CGPoint(x: cx + idolWidth * 0.16, y: torsoTopY + 40))
        torsoPath.closeSubpath()
        context.fill(torsoPath, with: .color(goldPrimary))
        context.stroke(torsoPath, with: .color(goldShine), lineWidth: 2.0)
        
        // 5. Head & Conical Kireetam (Crown)
        let faceRect = CGRect(x: cx - 18, y: headCenterY - 18, width: 36, height: 40)
        context.fill(Ellipse().path(in: faceRect), with: .color(goldPrimary))
        context.stroke(Ellipse().path(in: faceRect), with: .color(goldShine), lineWidth: 2.0)
        
        var crownPath = Path()
        crownPath.move(to: CGPoint(x: cx - 22, y: headCenterY - 12))
        crownPath.addLine(to: CGPoint(x: cx - 16, y: headCenterY - 42))
        crownPath.addLine(to: CGPoint(x: cx - 9, y: headCenterY - 68))
        crownPath.addLine(to: CGPoint(x: cx, y: headCenterY - 80))
        crownPath.addLine(to: CGPoint(x: cx + 9, y: headCenterY - 68))
        crownPath.addLine(to: CGPoint(x: cx + 16, y: headCenterY - 42))
        crownPath.addLine(to: CGPoint(x: cx + 22, y: headCenterY - 12))
        crownPath.closeSubpath()
        context.fill(crownPath, with: .color(goldShine))
        context.stroke(crownPath, with: .color(Color.yellow), lineWidth: 2.0)
        
        // 6. Radiant Manikanta Bell / Jewel on Neck
        let jewelCenter = CGPoint(x: cx, y: torsoTopY + 14)
        let jewelRect = CGRect(x: jewelCenter.x - 7 * jewelGlow, y: jewelCenter.y - 7 * jewelGlow, width: 14 * jewelGlow, height: 14 * jewelGlow)
        context.fill(Circle().path(in: jewelRect), with: .color(Color.white.opacity(0.95)))
    }
}

#if os(macOS)
import AppKit

struct AyyappaIdolImageView: View {
    var body: some View {
        if let nsImage = loadAyyappaImage() {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240, height: 280)
        }
    }
    
    private func loadAyyappaImage() -> NSImage? {
        if let img = NSImage(named: "ayyappa_idol") { return img }
        if let path = Bundle.main.path(forResource: "ayyappa_idol", ofType: "png"),
           let img = NSImage(contentsOfFile: path) { return img }
        
        let userDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AuraPlayer/ayyappa_idol.png")
        if let userDir = userDir, let img = NSImage(contentsOf: userDir) { return img }
        
        let devPath = "/Users/manikantaamara/Desktop/Antigravity/AuraPlayer/macos/Resources/ayyappa_idol.png"
        if let img = NSImage(contentsOfFile: devPath) { return img }
        return nil
    }
}
#else
import UIKit

struct AyyappaIdolImageView: View {
    var body: some View {
        if let uiImage = UIImage(named: "ayyappa_idol") {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240, height: 280)
        } else {
            Image("ayyappa_idol")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240, height: 280)
        }
    }
}
#endif

