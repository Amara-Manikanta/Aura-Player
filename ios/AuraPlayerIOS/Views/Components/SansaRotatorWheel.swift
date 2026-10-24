import SwiftUI

public enum SansaWheelMode: String, CaseIterable, Identifiable {
    case seek = "Scrub Time"
    case volume = "Volume"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .seek: return "forward.fill"
        case .volume: return "speaker.wave.3.fill"
        }
    }
}

public struct SansaRotatorWheel: View {
    public let diameter: CGFloat
    public let onRotate: (_ step: Int) -> Void
    public let onCenterTap: () -> Void
    public var isCenterActive: Bool = false
    
    @State private var rotationAngle: Angle = .zero
    @State private var previousTouchAngle: Angle?
    @State private var accumulatedDegrees: Double = 0
    @State private var isTouching: Bool = false
    
    private let tickStepDegrees: Double = 14.0 // Angle threshold per haptic tick / scrub step
    
    public init(
        diameter: CGFloat = 200,
        isCenterActive: Bool = false,
        onRotate: @escaping (_ step: Int) -> Void,
        onCenterTap: @escaping () -> Void
    ) {
        self.diameter = diameter
        self.isCenterActive = isCenterActive
        self.onRotate = onRotate
        self.onCenterTap = onCenterTap
    }
    
    public var body: some View {
        ZStack {
            // 1. Ambient Outer Neon Blue Glow Ring
            Circle()
                .stroke(
                    SansaTheme.neonBlueGradient,
                    lineWidth: 6
                )
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: SansaTheme.neonBlue.opacity(isTouching ? 0.9 : 0.65),
                    radius: isTouching ? 22 : 14,
                    x: 0,
                    y: 0
                )
                .shadow(
                    color: SansaTheme.neonBlueGlow.opacity(0.4),
                    radius: 32,
                    x: 0,
                    y: 0
                )
            
            // 2. Beveled Wheel Housing Ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x222634),
                            Color(hex: 0x161822),
                            Color(hex: 0x0E1017)
                        ],
                        center: .center,
                        startRadius: diameter * 0.25,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter - 8, height: diameter - 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            
            // 3. Rotating Grooved Wheel Texture & Grip Ridges
            ZStack {
                // Concentric machining micro-grooves
                ForEach(0..<4) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        .frame(
                            width: diameter * (0.55 + CGFloat(i) * 0.1),
                            height: diameter * (0.55 + CGFloat(i) * 0.1)
                        )
                }
                
                // Radial Grip Notches around the wheel
                ForEach(0..<16) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3.5, height: 16)
                        .offset(y: -(diameter * 0.38))
                        .rotationEffect(.degrees(Double(i) * 22.5))
                }
                
                // Subtle directional marker dot on wheel
                Circle()
                    .fill(SansaTheme.neonBlue.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .offset(y: -(diameter * 0.40))
            }
            .frame(width: diameter - 12, height: diameter - 12)
            .rotationEffect(rotationAngle)
            
            // 4. Center Metallic Select / Action Button
            Button(action: {
                Haptics.medium()
                onCenterTap()
            }) {
                ZStack {
                    // Center button outer bezel
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: 0x32384A),
                                    Color(hex: 0x1E222D),
                                    Color(hex: 0x14161E)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: diameter * 0.22
                            )
                        )
                        .frame(width: diameter * 0.44, height: diameter * 0.44)
                        .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 3)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    // Center Icon / Status
                    VStack(spacing: 3) {
                        Image(systemName: isCenterActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: isCenterActive ? 0 : 1)
                        
                        Text("SELECT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(SansaTheme.lcdTextSecondary)
                            .tracking(1)
                    }
                }
            }
            .buttonStyle(CenterPressButtonStyle())
        }
        .frame(width: diameter + 20, height: diameter + 20)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDrag(value: value)
                }
                .onEnded { _ in
                    isTouching = false
                    previousTouchAngle = nil
                }
        )
    }
    
    // MARK: - Circular Rotation Tracking
    
    private func handleDrag(value: DragGesture.Value) {
        let center = CGPoint(x: (diameter + 20) / 2, y: (diameter + 20) / 2)
        let deltaX = value.location.x - center.x
        let deltaY = value.location.y - center.y
        let currentTouchRadius = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        // Ignore gestures inside center button so center tapping works cleanly
        guard currentTouchRadius > (diameter * 0.22) else {
            previousTouchAngle = nil
            return
        }
        
        isTouching = true
        let currentAngle = Angle(radians: Double(atan2(deltaY, deltaX)))
        
        if let prev = previousTouchAngle {
            var diff = currentAngle.degrees - prev.degrees
            // Normalize wraparound around -180 / +180
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }
            
            rotationAngle += .degrees(diff)
            accumulatedDegrees += diff
            
            // Check if rotated past the step threshold
            if abs(accumulatedDegrees) >= tickStepDegrees {
                let steps = Int(accumulatedDegrees / tickStepDegrees)
                accumulatedDegrees -= Double(steps) * tickStepDegrees
                
                Haptics.light()
                onRotate(steps)
            }
        }
        
        previousTouchAngle = currentAngle
    }
}

// Center Button Push Animation
private struct CenterPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
