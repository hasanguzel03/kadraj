import SwiftUI

struct TouchFocusEvOverlay: View {
    let focusPoint: CGPoint?
    let tapVersion: Int
    let isFocusLocked: Bool
    let evBias: Float
    let minEv: Float
    let maxEv: Float
    let isDraggingEv: Bool
    let isVisible: Bool

    @State private var popScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            if let pt = focusPoint, isVisible {
                let boxHalf: CGFloat = 36 * popScale
                let cx = min(max(pt.x, boxHalf + 12), geo.size.width - boxHalf - 12)
                let cy = min(max(pt.y, boxHalf + 18), geo.size.height - boxHalf - 28)
                let placeLeft = cx + boxHalf + 34 > geo.size.width
                let sliderX = placeLeft ? (cx - boxHalf - 20) : (cx + boxHalf + 20)

                let trackHalf: CGFloat = 56
                let trackCenterY = min(max(cy, trackHalf + 24), geo.size.height - trackHalf - 28)
                let trackTopY = trackCenterY - trackHalf
                let trackBotY = trackCenterY + trackHalf
                let span = max(maxEv - minEv, 0.5)
                let frac = CGFloat(min(max((evBias - minEv) / span, 0), 1))
                let sunY = trackBotY - frac * (trackBotY - trackTopY)

                ZStack {
                    // Apple Camera Focus Square with Mid-Edge Ticks
                    Canvas { context, _ in
                        let rect = CGRect(x: cx - boxHalf, y: cy - boxHalf, width: boxHalf * 2, height: boxHalf * 2)
                        context.stroke(Path(rect), with: .color(.black.opacity(0.32)), lineWidth: 3.0)
                        context.stroke(Path(rect), with: .color(KadrajTheme.yellow), lineWidth: 1.5)

                        let tickLen: CGFloat = 6
                        var ticks = Path()
                        ticks.move(to: CGPoint(x: cx, y: rect.minY))
                        ticks.addLine(to: CGPoint(x: cx, y: rect.minY + tickLen))
                        ticks.move(to: CGPoint(x: cx, y: rect.maxY))
                        ticks.addLine(to: CGPoint(x: cx, y: rect.maxY - tickLen))
                        ticks.move(to: CGPoint(x: rect.minX, y: cy))
                        ticks.addLine(to: CGPoint(x: rect.minX + tickLen, y: cy))
                        ticks.move(to: CGPoint(x: rect.maxX, y: cy))
                        ticks.addLine(to: CGPoint(x: rect.maxX - tickLen, y: cy))
                        context.stroke(ticks, with: .color(KadrajTheme.yellow), lineWidth: 1.5)

                        let lineOpacity = (isDraggingEv || abs(evBias) > 0.05) ? 0.88 : 0.42
                        let gap: CGFloat = 15
                        if sunY - gap > trackTopY + 2 {
                            var upper = Path()
                            upper.move(to: CGPoint(x: sliderX, y: trackTopY))
                            upper.addLine(to: CGPoint(x: sliderX, y: sunY - gap))
                            context.stroke(upper, with: .color(KadrajTheme.yellow.opacity(lineOpacity)), lineWidth: 1.4)
                        }
                        if trackBotY - 2 > sunY + gap {
                            var lower = Path()
                            lower.move(to: CGPoint(x: sliderX, y: sunY + gap))
                            lower.addLine(to: CGPoint(x: sliderX, y: trackBotY))
                            context.stroke(lower, with: .color(KadrajTheme.yellow.opacity(lineOpacity)), lineWidth: 1.4)
                        }
                    }

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: isDraggingEv ? 17 : 14, weight: .semibold))
                        .foregroundColor(KadrajTheme.yellow)
                        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                        .position(x: sliderX, y: sunY)
                }
                .opacity(isDraggingEv ? 1.0 : 0.88)
                .allowsHitTesting(false)
                .onChange(of: tapVersion) { _ in
                    popScale = 1.36
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.68)) {
                        popScale = 1.0
                    }
                }
            }
        }
    }
}
