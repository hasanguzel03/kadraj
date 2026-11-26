import SwiftUI

struct GridAndHorizonView: View {
    let showThirds: Bool
    let showGoldenRatio: Bool
    let showHorizon: Bool
    let alwaysShowHorizon: Bool
    let showCrosshair: Bool
    let rollDegrees: Double
    var pitchRad: Double = 0

    var body: some View {
        ZStack {
            if showThirds || showGoldenRatio {
                Canvas { ctx, size in
                    if showThirds {
                        drawLines(ctx: &ctx, size: size, fractions: [1.0 / 3.0, 2.0 / 3.0], color: KadrajTheme.gridLine)
                    }
                    if showGoldenRatio {
                        drawLines(ctx: &ctx, size: size, fractions: [0.382, 0.618], color: KadrajTheme.yellow.opacity(0.28))
                    }
                }
            }

            if showHorizon {
                IosBrokenHorizonLevel(
                    rollDegrees: rollDegrees,
                    pitchRad: pitchRad,
                    alwaysVisible: alwaysShowHorizon,
                    showCrosshair: showCrosshair
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawLines(ctx: inout GraphicsContext, size: CGSize, fractions: [CGFloat], color: Color) {
        for f in fractions {
            let x = size.width * f
            let y = size.height * f
            var vPath = Path()
            vPath.move(to: CGPoint(x: x, y: 0))
            vPath.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(vPath, with: .color(KadrajTheme.gridShadow), lineWidth: 1.8)
            ctx.stroke(vPath, with: .color(color), lineWidth: 0.8)

            var hPath = Path()
            hPath.move(to: CGPoint(x: 0, y: y))
            hPath.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(hPath, with: .color(KadrajTheme.gridShadow), lineWidth: 1.8)
            ctx.stroke(hPath, with: .color(color), lineWidth: 0.8)
        }
    }
}

struct IosBrokenHorizonLevel: View {
    let rollDegrees: Double
    var pitchRad: Double = 0
    let alwaysVisible: Bool
    let showCrosshair: Bool

    var body: some View {
        let absRoll = abs(rollDegrees)
        let extremeTilt = abs(pitchRad) > 0.95
        let visible = !extremeTilt && (alwaysVisible || absRoll <= 18.0)
        let isLevel = absRoll < 2.0
        let sideColor = isLevel ? KadrajTheme.yellow : Color.white.opacity(0.55)
        let centerColor = isLevel ? KadrajTheme.yellow : Color.white.opacity(0.9)

        ZStack {
            if visible {
                Canvas { ctx, size in
                    let cx = size.width * 0.5
                    let cy = size.height * 0.5

                    if showCrosshair {
                        var cross = Path()
                        cross.move(to: CGPoint(x: cx, y: cy - 8))
                        cross.addLine(to: CGPoint(x: cx, y: cy + 8))
                        ctx.stroke(cross, with: .color(sideColor.opacity(0.45)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                    }

                    var wings = Path()
                    wings.move(to: CGPoint(x: cx - 42, y: cy))
                    wings.addLine(to: CGPoint(x: cx - 22, y: cy))
                    wings.move(to: CGPoint(x: cx + 22, y: cy))
                    wings.addLine(to: CGPoint(x: cx + 42, y: cy))
                    ctx.stroke(wings, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    ctx.stroke(wings, with: .color(sideColor), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                }

                Capsule()
                    .fill(centerColor)
                    .frame(width: isLevel ? 44 : 36, height: isLevel ? 1.4 : 1.0)
                    .shadow(color: .black.opacity(0.35), radius: 1.0)
                    .rotationEffect(.degrees(isLevel ? 0 : rollDegrees))
                    .animation(.linear(duration: 0.06), value: rollDegrees)
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: visible)
    }
}

struct AngleGuideOverlay: View {
    let guideState: CompositionGuideState
    let isScanning: Bool

    @State private var scanAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.5

                // Subtle Golden Ratio lines during guided composition
                for f in [CGFloat(0.382), CGFloat(0.618)] {
                    let gx = size.width * f
                    let gy = size.height * f
                    var vp = Path()
                    vp.move(to: CGPoint(x: gx, y: 0))
                    vp.addLine(to: CGPoint(x: gx, y: size.height))
                    ctx.stroke(vp, with: .color(KadrajTheme.gridLine), lineWidth: 0.7)
                    var hp = Path()
                    hp.move(to: CGPoint(x: 0, y: gy))
                    hp.addLine(to: CGPoint(x: size.width, y: gy))
                    ctx.stroke(hp, with: .color(KadrajTheme.gridLine), lineWidth: 0.7)
                }

                if isScanning { return }

                let rawTargetX = cx + guideState.targetOffsetX * (size.width * 0.5)
                let rawTargetY = cy + guideState.targetOffsetY * (size.height * 0.5)
                let targetX = min(max(rawTargetX, size.width * 0.14), size.width * 0.86)
                let targetY = min(max(rawTargetY, size.height * 0.16), size.height * 0.78)
                let targetPt = CGPoint(x: targetX, y: targetY)

                if !guideState.isAligned {
                    var connector = Path()
                    connector.move(to: CGPoint(x: cx, y: cy))
                    connector.addLine(to: targetPt)
                    ctx.stroke(
                        connector,
                        with: .color(.white.opacity(0.62)),
                        style: StrokeStyle(lineWidth: 1.6, dash: [6, 5])
                    )
                }

                let accent = guideState.isAligned ? KadrajTheme.yellow : Color.white.opacity(0.95)
                let targetR: CGFloat = (guideState.isAligned ? 16 : 14) * pulseScale
                let targetRect = CGRect(x: targetPt.x - targetR, y: targetPt.y - targetR, width: targetR * 2, height: targetR * 2)
                ctx.stroke(Path(ellipseIn: targetRect), with: .color(.black.opacity(0.35)), lineWidth: 3.6)
                ctx.stroke(Path(ellipseIn: targetRect), with: .color(accent), lineWidth: 2.2)
                let dotRect = CGRect(x: targetPt.x - 3.5, y: targetPt.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(accent))
            }

            if isScanning {
                Circle()
                    .trim(from: 0, to: 0.34)
                    .stroke(KadrajTheme.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(scanAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                            scanAngle = 360
                        }
                    }
            } else {
                IosBrokenHorizonLevel(rollDegrees: guideState.currentRollDegrees, alwaysVisible: true, showCrosshair: false)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.8)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: guideState.alignmentScore)
                        .stroke(
                            guideState.isAligned ? KadrajTheme.yellow : .white,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulseScale = 1.07
            }
        }
        .allowsHitTesting(false)
    }
}
