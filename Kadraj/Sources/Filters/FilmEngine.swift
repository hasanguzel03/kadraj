import Foundation
import UIKit
import os
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

final class FilmEngine {
    static let shared = FilmEngine()

    let ciContext: CIContext = {
        CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .useSoftwareRenderer: false
        ])
    }()

    private init() {}

    /// Quickly checks image histogram spread to trigger Auto-HDR in HDR AUTO mode.
    func isHighDynamicRangeScene(_ image: UIImage) -> Bool {
        guard let cg = normalizedCGImage(image, maxDim: 160),
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }

        let bytesPerPixel = max(4, cg.bitsPerPixel / 8)
        let length = CFDataGetLength(data)
        var bright = 0
        var dark = 0
        var total = 0
        var minL = 255
        var maxL = 0

        var idx = 0
        while idx + 3 < length {
            let r = Int(ptr[idx])
            let g = Int(ptr[idx + 1])
            let b = Int(ptr[idx + 2])
            let luma = (77 * r + 150 * g + 29 * b) >> 8
            if luma < minL { minL = luma }
            if luma > maxL { maxL = luma }
            if luma >= 225 { bright += 1 }
            if luma <= 34 { dark += 1 }
            total += 1
            idx += bytesPerPixel * 2
        }

        guard total > 0 else { return false }
        let spread = maxL - minL
        return spread >= 165 || (Double(bright) / Double(total) >= 0.04 && Double(dark) / Double(total) >= 0.06)
    }

    /// CoreImage GPU pipeline: Auto-HDR (highlight/shadow + clarity) -> 3D LUT Film -> Manual edits -> Vignette
    func applyChain(
        to inputCI: CIImage,
        profile: FilmProfile,
        adjustments: ImageAdjustments,
        includeGrainAndVignette: Bool = true
    ) -> CIImage {
        let extent = inputCI.extent
        var current = inputCI

        // 1. Auto-HDR Highlight Recovery + Shadow Lift + Midtone Micro-Contrast (Clarity)
        if adjustments.autoHdrEnabled {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = current
            hs.highlightAmount = 0.72 // pulls highlights gently (default 1.0, <1.0 reduces bright clipping)
            hs.shadowAmount = 0.24    // opens shadows cleanly without mud
            if let out = hs.outputImage {
                current = out
            }

            let clarity = CIFilter.unsharpMask()
            clarity.inputImage = current
            clarity.radius = 6.5
            clarity.intensity = 0.34
            if let out = clarity.outputImage?.cropped(to: extent) {
                current = out
            }
        }

        // 2. Non-linear 3D Color Cube Film Profile (S-curve + split toning + lifted blacks)
        let strength = Float(min(max(adjustments.filterStrength, 0), 1))
        if profile != .original && strength > 0.005 {
            let cubeSize = 17
            let cubeData = buildColorCubeData(profile: profile, strength: strength, size: cubeSize)
            let cube = CIFilter.colorCube()
            cube.inputImage = current
            cube.cubeDimension = Float(cubeSize)
            cube.cubeData = cubeData
            if let out = cube.outputImage {
                current = out
            }

            // Subtle analog organic grain overlay
            if includeGrainAndVignette && profile.recipe.grainAmount > 0.005 {
                let grainScale = profile.recipe.grainAmount * strength
                current = applySubtleFilmGrain(to: current, extent: extent, amount: grainScale)
            }
        }

        // 3. Manual ColorControls (Brightness, Contrast, Saturation)
        if abs(adjustments.brightness) > 0.5 ||
            abs(adjustments.contrast - 1.0) > 0.01 ||
            abs(adjustments.saturation - 1.0) > 0.01 {
            let cc = CIFilter.colorControls()
            cc.inputImage = current
            cc.brightness = Float(adjustments.brightness / 255.0)
            cc.contrast = Float(adjustments.contrast)
            cc.saturation = Float(adjustments.saturation)
            if let out = cc.outputImage {
                current = out
            }
        }

        // 4. Warmth temperature tint
        if abs(adjustments.warmth) > 0.5 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = current
            temp.neutral = CIVector(x: 6500, y: 0)
            let shiftK = 6500.0 - (adjustments.warmth * 35.0)
            temp.targetNeutral = CIVector(x: CGFloat(shiftK), y: 0)
            if let out = temp.outputImage {
                current = out
            }
        }

        // 5. Combined Optical Vignette
        if includeGrainAndVignette {
            let filmVig = profile == .original ? 0.0 : Double(profile.recipe.vignetteStrength) * Double(strength)
            let totalVig = min(filmVig + adjustments.vignette, 0.90)
            if totalVig > 0.01 {
                let vig = CIFilter.vignette()
                vig.inputImage = current
                vig.intensity = Float(totalVig * 1.45)
                vig.radius = 1.6
                if let out = vig.outputImage {
                    current = out
                }
            }
        }

        return current.cropped(to: extent)
    }

    func renderUIImage(
        from source: UIImage,
        profile: FilmProfile,
        adjustments: ImageAdjustments
    ) -> UIImage {
        guard let ciIn = CIImage(image: source)?.oriented(forExifOrientation: exifOrientation(for: source.imageOrientation)) else {
            return source
        }
        let ciOut = applyChain(to: ciIn, profile: profile, adjustments: adjustments, includeGrainAndVignette: true)
        guard let cgOut = ciContext.createCGImage(ciOut, from: ciOut.extent) else {
            return source
        }
        return UIImage(cgImage: cgOut)
    }

    func makeProxyImage(_ source: UIImage, maxDimension: CGFloat = 1080) -> UIImage {
        let size = source.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return source }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func generateThumbnails(for source: UIImage) -> [(FilmProfile, UIImage)] {
        let thumbSource = makeProxyImage(source, maxDimension: 180)
        return FilmProfile.allCases.map { profile in
            let rendered = profile == .original
                ? thumbSource
                : renderUIImage(from: thumbSource, profile: profile, adjustments: ImageAdjustments())
            return (profile, rendered)
        }
    }

    func makeVideoComposition(
        for asset: AVAsset,
        profile: FilmProfile,
        strength: Double,
        autoHdr: Bool
    ) -> AVVideoComposition? {
        guard profile != .original || autoHdr else { return nil }
        let adj = ImageAdjustments(filterStrength: strength, autoHdrEnabled: autoHdr)
        return AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            let out = self.applyChain(
                to: request.sourceImage.clampingToExtent(),
                profile: profile,
                adjustments: adj,
                includeGrainAndVignette: true
            ).cropped(to: request.sourceImage.extent)
            request.finish(with: out, context: self.ciContext)
        })
    }

    func exportVideo(
        sourceURL: URL,
        profile: FilmProfile,
        strength: Double,
        autoHdr: Bool,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        _ = try await asset.load(.tracks, .duration)

        if profile == .original && !autoHdr {
            await MainActor.run { progressHandler(1.0) }
            return sourceURL
        }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kadraj_export_\(Int(Date().timeIntervalSince1970)).mp4")
        if FileManager.default.fileExists(atPath: exportURL.path) {
            try? FileManager.default.removeItem(at: exportURL)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "KadrajExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
        }
        session.outputURL = exportURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = makeVideoComposition(
            for: asset,
            profile: profile,
            strength: strength,
            autoHdr: autoHdr
        )

        let isDone = OSAllocatedUnfairLock(initialState: false)
        let timerTask = Task {
            while !Task.isCancelled {
                let prog = Double(session.progress)
                await MainActor.run { progressHandler(prog) }
                if isDone.withLock({ $0 }) { break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                isDone.withLock { $0 = true }
                switch session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: session.error ?? NSError(domain: "KadrajExport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video export failed"]))
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "KadrajExport", code: -3, userInfo: [NSLocalizedDescriptionKey: "Video export cancelled"]))
                default:
                    continuation.resume(throwing: NSError(domain: "KadrajExport", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unexpected export status"]))
                }
            }
        }
        timerTask.cancel()
        await MainActor.run { progressHandler(1.0) }
        return exportURL
    }

    func savePhotoToLibrary(_ image: UIImage, jpegQuality: CGFloat) async throws {
        guard let jpegData = image.jpegData(compressionQuality: min(max(jpegQuality, 0.95), 1.0)) else {
            throw NSError(domain: "KadrajSave", code: -1, userInfo: [NSLocalizedDescriptionKey: "JPEG encoding failed"])
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "KadrajSave", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photos permission required"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: jpegData, options: nil)
        }
    }

    func saveVideoToLibrary(_ videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "KadrajSave", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photos permission required"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }
    }

    // MARK: - 3D LUT Color Cube Construction (Blue outer -> Green middle -> Red inner)

    private func buildColorCubeData(profile: FilmProfile, strength: Float, size: Int) -> Data {
        let recipe = profile.recipe
        let toneLut = buildToneCurve(recipe: recipe)
        var floats: [Float] = []
        floats.reserveCapacity(size * size * size * 4)

        for bi in 0..<size {
            let b0 = Float(bi) / Float(size - 1)
            for gi in 0..<size {
                let g0 = Float(gi) / Float(size - 1)
                for ri in 0..<size {
                    let r0 = Float(ri) / Float(size - 1)

                    var r: Float
                    var g: Float
                    var b: Float
                    if recipe.isMonochrome {
                        let mono = min(max(0.33 * r0 + 0.54 * g0 + 0.13 * b0, 0), 1)
                        r = mono
                        g = mono
                        b = mono
                    } else if abs(recipe.saturation - 1.0) > 0.005 {
                        let luma = 0.299 * r0 + 0.587 * g0 + 0.114 * b0
                        r = min(max(luma + (r0 - luma) * recipe.saturation, 0), 1)
                        g = min(max(luma + (g0 - luma) * recipe.saturation, 0), 1)
                        b = min(max(luma + (b0 - luma) * recipe.saturation, 0), 1)
                    } else {
                        r = r0
                        g = g0
                        b = b0
                    }

                    r = sampleLut(toneLut, value: r)
                    g = sampleLut(toneLut, value: g)
                    b = sampleLut(toneLut, value: b)

                    if !recipe.isMonochrome {
                        let postLuma = min(max(0.299 * r + 0.587 * g + 0.114 * b, 0), 1)
                        let shadowW = pow(1.0 - postLuma, 1.6)
                        let highlightW = pow(postLuma, 1.4)
                        r = min(max(r + (recipe.shadowRed * shadowW + recipe.highlightRed * highlightW) / 255.0, 0), 1)
                        g = min(max(g + (recipe.shadowGreen * shadowW + recipe.highlightGreen * highlightW) / 255.0, 0), 1)
                        b = min(max(b + (recipe.shadowBlue * shadowW + recipe.highlightBlue * highlightW) / 255.0, 0), 1)
                    }

                    let outR = r0 + (r - r0) * strength
                    let outG = g0 + (g - g0) * strength
                    let outB = b0 + (b - b0) * strength
                    floats.append(outR)
                    floats.append(outG)
                    floats.append(outB)
                    floats.append(1.0)
                }
            }
        }
        return floats.withUnsafeBytes { Data($0) }
    }

    private func buildToneCurve(recipe: FilmRecipe) -> [Float] {
        let lift = min(max(recipe.blackLift, 0), 0.25)
        let ceiling = min(max(recipe.whiteCeiling, lift + 0.35), 1.0)
        let curve = min(max(recipe.contrastCurve, 0), 0.44)
        let expNorm = recipe.exposureShift / 255.0

        return (0..<256).map { idx in
            let x = Float(idx) / 255.0
            let smooth = x * x * (3.0 - 2.0 * x)
            let sCurved = min(max(x + curve * (smooth - x) * 2.2, 0), 1)
            let shifted = min(max(sCurved + expNorm, 0), 1)
            return min(max(lift + shifted * (ceiling - lift), 0), 1)
        }
    }

    private func sampleLut(_ lut: [Float], value: Float) -> Float {
        let pos = min(max(value, 0), 1) * 255.0
        let i0 = Int(pos)
        let i1 = min(i0 + 1, 255)
        let frac = pos - Float(i0)
        return lut[i0] + (lut[i1] - lut[i0]) * frac
    }

    private func applySubtleFilmGrain(to image: CIImage, extent: CGRect, amount: Float) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) else {
            return image
        }
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        let weight = CGFloat(min(max(amount * 1.4, 0.01), 0.12))
        mono.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: weight)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        guard let grained = mono.outputImage else { return image }
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = grained
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private func normalizedCGImage(_ image: UIImage, maxDim: CGFloat) -> CGImage? {
        let scaled = makeProxyImage(image, maxDimension: maxDim)
        return scaled.cgImage
    }

    private func exifOrientation(for uiOrientation: UIImage.Orientation) -> Int32 {
        switch uiOrientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}
