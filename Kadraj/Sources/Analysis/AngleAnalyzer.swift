import Foundation
import CoreMotion
import Vision
import UIKit

enum InternalSceneMode {
    case cinematicSunset
    case landscape
    case livingCreature
    case portraitSelfie
    case vehicle
    case object
}

struct DeviceOrientationState: Equatable {
    var azimuthRad: Double = 0
    var pitchRad: Double = 0
    var rollRad: Double = 0
    var rollDegrees: Double = 0
    var isStable: Bool = false
}

struct TargetComposition {
    var mode: InternalSceneMode
    var targetAzimuthRad: Double
    var targetPitchRad: Double
    var anchorX: CGFloat          // normalized 0..1 (left->right)
    var anchorY: CGFloat          // normalized 0..1 (top->bottom)
    var goalAnchorX: CGFloat      // closest golden/thirds intersection
    var goalAnchorY: CGFloat
    var recommendedUiZoom: CGFloat
    var recommendedEvBias: Float
    var supportsVisionTracking: Bool
}

struct CompositionGuideState: Equatable {
    var alignmentScore: CGFloat = 0
    var isAligned: Bool = false
    var isStable: Bool = false
    var isReadyToCapture: Bool = false
    var targetOffsetX: CGFloat = 0     // -0.72..+0.72 mapped to screen
    var targetOffsetY: CGFloat = 0
    var currentRollDegrees: Double = 0
}

@MainActor
final class AngleAnalyzer: ObservableObject {
    @Published private(set) var orientation = DeviceOrientationState()

    private let motionManager = CMMotionManager()
    private var recentPitches: [Double] = []
    private var recentRolls: [Double] = []
    private let stabilityWindow = 9

    private let horizontalHalfFovRad: Double = 30.0 * .pi / 180.0
    private let verticalHalfFovRad: Double = 36.0 * .pi / 180.0

    func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        recentPitches.removeAll()
        recentRolls.removeAll()
        motionManager.deviceMotionUpdateInterval = 1.0 / 40.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            let gz = motion.gravity.z

            // Portrait orientation: 0 when upright, + aiming up, 0 roll when horizon level
            let pitch = atan2(-gz, hypot(gx, gy))
            let roll = atan2(gx, -gy)
            let azimuth = motion.attitude.yaw

            self.recentPitches.append(pitch)
            self.recentRolls.append(roll)
            if self.recentPitches.count > self.stabilityWindow {
                self.recentPitches.removeFirst()
                self.recentRolls.removeFirst()
            }

            let isStable = self.checkStability()
            self.orientation = DeviceOrientationState(
                azimuthRad: azimuth,
                pitchRad: pitch,
                rollRad: roll,
                rollDegrees: roll * 180.0 / .pi,
                isStable: isStable
            )
        }
    }

    func stopMotion() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    /// Runs on-device Apple Vision scene & subject detection (never leaves UI text clutter)
    func computeBestTarget(
        from image: UIImage?,
        isFrontCamera: Bool,
        minUiZoom: CGFloat,
        maxUiZoom: CGFloat
    ) async -> TargetComposition {
        let current = orientation

        guard let cgImage = image?.cgImage else {
            return TargetComposition(
                mode: isFrontCamera ? .portraitSelfie : .object,
                targetAzimuthRad: current.azimuthRad,
                targetPitchRad: current.pitchRad,
                anchorX: 0.5,
                anchorY: 0.5,
                goalAnchorX: 0.5,
                goalAnchorY: 0.382,
                recommendedUiZoom: min(max(1.0, minUiZoom), maxUiZoom),
                recommendedEvBias: 0,
                supportsVisionTracking: !isFrontCamera
            )
        }

        let detected = await analyzeVision(cgImage: cgImage, isFrontCamera: isFrontCamera)

        let clampedAnchorX = min(max(detected.anchorX, 0.14), 0.86)
        let clampedAnchorY = min(max(detected.anchorY, 0.16), 0.80)

        // Choose closest Golden Ratio / thirds anchor so camera never guides away from framed subject
        let (goalX, goalY) = pickClosestCompositionAnchor(
            mode: detected.mode,
            anchorX: clampedAnchorX,
            anchorY: clampedAnchorY
        )

        // Ensure subject bbox stays clear of 8% edge margin even after applying recommended zoom
        let baseSafeZoom: CGFloat
        switch detected.mode {
        case .cinematicSunset, .landscape:
            baseSafeZoom = max(minUiZoom, min(1.3, maxUiZoom))
        case .portraitSelfie, .livingCreature:
            baseSafeZoom = max(minUiZoom, min(1.2, maxUiZoom))
        case .vehicle, .object:
            baseSafeZoom = max(minUiZoom, min(1.15, maxUiZoom))
        }

        let boxW = max(detected.boxWidth, 0.08)
        let boxH = max(detected.boxHeight, 0.08)
        let maxEdgeZoom = min(0.84 / boxW, 0.84 / boxH)
        let safeZoom = min(max(minUiZoom, min(baseSafeZoom, maxEdgeZoom)), maxUiZoom)

        // Clamp goal anchor within ±12% of screen center (0.38...0.62) so guide never leaves frame
        let safeGoalX = goalX.clamped(to: 0.38...0.62)
        let safeGoalY = goalY.clamped(to: 0.38...0.62)

        // Offset from current anchor to desired Golden Ratio goal (bounded to ±12% FOV)
        let deltaXNorm = (clampedAnchorX - safeGoalX).clamped(to: -0.12...0.12)
        let deltaYNorm = (safeGoalY - clampedAnchorY).clamped(to: -0.12...0.12)
        let targetAzimuth = normalizeAngle(current.azimuthRad + Double(deltaXNorm) * horizontalHalfFovRad * 0.65)
        let targetPitch = min(max(current.pitchRad + Double(deltaYNorm) * verticalHalfFovRad * 0.65, -0.75), 0.85)

        let evBias: Float = (detected.mode == .cinematicSunset) ? -0.35 : 0.0

        return TargetComposition(
            mode: detected.mode,
            targetAzimuthRad: targetAzimuth,
            targetPitchRad: targetPitch,
            anchorX: clampedAnchorX,
            anchorY: clampedAnchorY,
            goalAnchorX: safeGoalX,
            goalAnchorY: safeGoalY,
            recommendedUiZoom: safeZoom,
            recommendedEvBias: evBias,
            supportsVisionTracking: detected.hasSubjectBox
        )
    }

    func updateGuidance(
        orientation: DeviceOrientationState,
        target: TargetComposition
    ) -> CompositionGuideState {
        let yawDiff = normalizeAngle(target.targetAzimuthRad - orientation.azimuthRad)
        let pitchDiff = target.targetPitchRad - orientation.pitchRad

        // Keep target point strictly within ±12% of screen center (normalized 0.38...0.62)
        let offsetX = CGFloat((yawDiff / horizontalHalfFovRad)).clamped(to: -0.12...0.12)
        let offsetY = CGFloat((-pitchDiff / verticalHalfFovRad)).clamped(to: -0.12...0.12)

        let dist = hypot(offsetX, offsetY)
        let rollPenalty = CGFloat(min(abs(orientation.rollDegrees) / 18.0, 0.35))
        let rawScore = max(0, min(1, 1.0 - (dist / 0.16) - rollPenalty))

        let isAligned = dist < 0.045 && abs(orientation.rollDegrees) < 2.2
        return CompositionGuideState(
            alignmentScore: isAligned ? max(rawScore, 0.92) : rawScore,
            isAligned: isAligned,
            isStable: orientation.isStable,
            isReadyToCapture: isAligned && orientation.isStable,
            targetOffsetX: offsetX,
            targetOffsetY: offsetY,
            currentRollDegrees: orientation.rollDegrees
        )
    }

    // MARK: - Private Vision & Geometry Helpers

    private struct VisionSummary {
        var mode: InternalSceneMode
        var anchorX: CGFloat
        var anchorY: CGFloat
        var boxWidth: CGFloat
        var boxHeight: CGFloat
        var hasSubjectBox: Bool
    }

    private func analyzeVision(cgImage: CGImage, isFrontCamera: Bool) async -> VisionSummary {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let faceReq = VNDetectFaceRectanglesRequest()
                let animalReq = VNRecognizeAnimalsRequest()
                let classifyReq = VNClassifyImageRequest()
                let saliencyReq = VNGenerateAttentionBasedSaliencyImageRequest()

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                try? handler.perform([faceReq, animalReq, classifyReq, saliencyReq])

                if let face = (faceReq.results)?.first {
                    let b = Self.uiRect(fromVision: face.boundingBox)
                    continuation.resume(returning: VisionSummary(
                        mode: .portraitSelfie,
                        anchorX: b.midX,
                        anchorY: b.minY + b.height * 0.34,
                        boxWidth: b.width,
                        boxHeight: b.height,
                        hasSubjectBox: true
                    ))
                    return
                }

                if isFrontCamera {
                    continuation.resume(returning: VisionSummary(
                        mode: .portraitSelfie,
                        anchorX: 0.5,
                        anchorY: 0.42,
                        boxWidth: 0.35,
                        boxHeight: 0.45,
                        hasSubjectBox: false
                    ))
                    return
                }

                if let animal = (animalReq.results)?.first {
                    let b = Self.uiRect(fromVision: animal.boundingBox)
                    continuation.resume(returning: VisionSummary(
                        mode: .livingCreature,
                        anchorX: b.midX,
                        anchorY: b.minY + b.height * 0.32,
                        boxWidth: b.width,
                        boxHeight: b.height,
                        hasSubjectBox: true
                    ))
                    return
                }

                let topLabels = (classifyReq.results ?? []).prefix(8).map { $0.identifier.lowercased() }
                let isSunset = topLabels.contains { $0.contains("sunset") || $0.contains("sunrise") || $0.contains("dusk") }
                let isVehicle = topLabels.contains {
                    $0.contains("car") || $0.contains("vehicle") || $0.contains("motorcycle") || $0.contains("bicycle")
                }
                let isLandscape = topLabels.contains {
                    $0.contains("landscape") || $0.contains("sky") || $0.contains("mountain") || $0.contains("ocean") || $0.contains("beach")
                }

                if let salient = saliencyReq.results?.first?.salientObjects?.first {
                    let b = Self.uiRect(fromVision: salient.boundingBox)
                    let mode: InternalSceneMode = isSunset ? .cinematicSunset : (isVehicle ? .vehicle : (isLandscape ? .landscape : .object))
                    continuation.resume(returning: VisionSummary(
                        mode: mode,
                        anchorX: b.midX,
                        anchorY: b.midY,
                        boxWidth: b.width,
                        boxHeight: b.height,
                        hasSubjectBox: true
                    ))
                    return
                }

                let fallbackMode: InternalSceneMode = isSunset ? .cinematicSunset : (isLandscape ? .landscape : .object)
                continuation.resume(returning: VisionSummary(
                    mode: fallbackMode,
                    anchorX: 0.5,
                    anchorY: isLandscape ? 0.38 : 0.5,
                    boxWidth: 0.4,
                    boxHeight: 0.4,
                    hasSubjectBox: false
                ))
            }
        }
    }

    private func pickClosestCompositionAnchor(
        mode: InternalSceneMode,
        anchorX: CGFloat,
        anchorY: CGFloat
    ) -> (CGFloat, CGFloat) {
        switch mode {
        case .portraitSelfie, .livingCreature:
            let gx: CGFloat = anchorX < 0.44 ? 0.382 : (anchorX > 0.56 ? 0.618 : 0.5)
            return (gx, 0.36)
        case .vehicle:
            let gx: CGFloat = anchorX < 0.44 ? 0.382 : (anchorX > 0.56 ? 0.618 : 0.5)
            return (gx, 0.58)
        case .cinematicSunset, .landscape:
            let gy: CGFloat = anchorY < 0.45 ? 0.333 : 0.618
            return (0.5, gy)
        case .object:
            let candidatesX: [CGFloat] = [0.382, 0.5, 0.618]
            let candidatesY: [CGFloat] = [0.382, 0.5, 0.618]
            let bestX = candidatesX.min { abs($0 - anchorX) < abs($1 - anchorX) } ?? 0.5
            let bestY = candidatesY.min { abs($0 - anchorY) < abs($1 - anchorY) } ?? 0.5
            return (bestX, bestY)
        }
    }

    private nonisolated static func uiRect(fromVision rect: CGRect) -> CGRect {
        // Vision bottom-left origin -> UIKit top-left origin
        CGRect(
            x: rect.origin.x,
            y: 1.0 - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func checkStability() -> Bool {
        guard recentPitches.count >= stabilityWindow else { return false }
        return variance(recentPitches) < 0.0018 && variance(recentRolls) < 0.0018
    }

    private func variance(_ vals: [Double]) -> Double {
        let mean = vals.reduce(0, +) / Double(vals.count)
        return vals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(vals.count)
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
