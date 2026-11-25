import Foundation
import AVFoundation
import UIKit

struct RecordedVideoResult {
    let url: URL
    let isHdr: Bool
    let dynamicRangeLabel: String
    let specLabel: String
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    @Published var isAuthorized = false
    @Published var isFrontCamera = false
    @Published var isFlashEnabled = false
    @Published var currentUiZoom: CGFloat = 1.0
    @Published var minUiZoom: CGFloat = 1.0
    @Published var maxUiZoom: CGFloat = 6.0
    @Published var currentEvBias: Float = 0.0
    @Published var minEvBias: Float = -2.0
    @Published var maxEvBias: Float = 2.0

    @Published var isVideoMode = false
    @Published var isRecording = false
    @Published var recordingDurationSec: TimeInterval = 0
    @Published var isVideoHdrActive = false
    @Published var videoDynamicRangeLabel = "SDR"
    @Published var videoSpecLabel = "1080p·30"

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoBufferQueue = DispatchQueue(label: "com.kadraj.camera.frames", qos: .userInitiated)
    private let frameLock = NSLock()
    private nonisolated(unsafe) var latestSnapshotBuffer: CVPixelBuffer?

    private var activeSettings = CameraSettings()
    private var switchOverFactor: CGFloat = 1.0
    private var pendingPhotoContinuation: CheckedContinuation<UIImage, Error>?
    private var pendingVideoCompletion: ((Result<RecordedVideoResult, Error>) -> Void)?
    private var recordingTimer: Timer?
    private var recordStartDate: Date?

    private let sessionQueue = DispatchQueue(label: "com.kadraj.camera.session", qos: .userInitiated)

    func checkPermissionsAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            isAuthorized = true
            configureSession()
            return
        }
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            if granted { configureSession() }
            return
        }
        isAuthorized = false
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = layer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
    }

    func updateSettings(_ newSettings: CameraSettings) {
        let old = activeSettings
        activeSettings = newSettings

        let needsReconfig = (old.videoResolution != newSettings.videoResolution ||
                             old.videoFps != newSettings.videoFps ||
                             old.hdrMode != newSettings.hdrMode ||
                             old.aspectRatio != newSettings.aspectRatio) && !isRecording
        if needsReconfig && isAuthorized {
            configureSession()
        }
    }

    func setVideoMode(_ enabled: Bool) {
        guard isVideoMode != enabled else { return }
        if isRecording { stopRecording() }
        isVideoMode = enabled
        configureSession()
    }

    func switchCamera() {
        guard !isRecording else { return }
        isFrontCamera.toggle()
        configureSession()
    }

    func toggleFlash() {
        isFlashEnabled.toggle()
        guard isVideoMode, let device = videoInput?.device, device.hasTorch else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.torchMode = (self.isFlashEnabled && !self.isFrontCamera) ? .on : .off
            device.unlockForConfiguration()
        }
    }

    // MARK: - Smooth Ease-Out Ramp Zoom (Starts at Widest Lens)

    func animateZoom(to uiZoom: CGFloat) {
        guard let device = videoInput?.device else { return }
        let clampedUi = min(max(uiZoom, minUiZoom), maxUiZoom)
        let hardwareZoom = clampedUi * switchOverFactor
        let hwMin = device.minAvailableVideoZoomFactor
        let hwMax = min(device.maxAvailableVideoZoomFactor, 8.0 * switchOverFactor)
        let targetHw = min(max(hardwareZoom, hwMin), hwMax)

        DispatchQueue.main.async {
            self.currentUiZoom = targetHw / self.switchOverFactor
        }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.ramp(toVideoZoomFactor: targetHw, withRate: 4.5)
                device.unlockForConfiguration()
            } catch {
                // ignore
            }
        }
    }

    func resetZoomAndExposure() {
        animateZoom(to: minUiZoom)
        setManualExposureBias(0)
    }

    // MARK: - Tap-to-Focus + Vertical Sun EV

    func tapToFocusAndMeter(at layerPoint: CGPoint, completion: @escaping (Bool) -> Void) {
        guard let previewLayer, let device = videoInput?.device else {
            completion(false)
            return
        }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        currentEvBias = 0

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.setExposureTargetBias(0, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func setManualExposureBias(_ bias: Float) {
        guard let device = videoInput?.device else { return }
        let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
        currentEvBias = clamped
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    // MARK: - Photo & Video Capture

    func currentSnapshotImage() -> UIImage? {
        frameLock.lock()
        let buffer = latestSnapshotBuffer
        frameLock.unlock()
        guard let buffer else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = FilmEngine.shared.ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func capturePhoto(evBias: Float? = nil) async throws -> UIImage {
        if let ev = evBias {
            setManualExposureBias(ev)
            try? await Task.sleep(nanoseconds: 160_000_000)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingPhotoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            if !isFrontCamera, let dev = videoInput?.device, dev.hasFlash {
                settings.flashMode = isFlashEnabled ? .on : .off
            }
            settings.photoQualityPrioritization = activeSettings.captureQuality == .highEfficiency ? .speed : .quality
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleVideoRecording(onFinished: @escaping (Result<RecordedVideoResult, Error>) -> Void) {
        if isRecording {
            stopRecording()
            return
        }
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            self.startRecordingInternal(onFinished: onFinished)
        }
    }

    private func startRecordingInternal(onFinished: @escaping (Result<RecordedVideoResult, Error>) -> Void) {
        guard !movieOutput.isRecording else { return }
        pendingVideoCompletion = onFinished
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kadraj_raw_\(Int(Date().timeIntervalSince1970)).mov")
        if FileManager.default.fileExists(atPath: outURL.path) {
            try? FileManager.default.removeItem(at: outURL)
        }

        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if isVideoHdrActive && movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }

        movieOutput.startRecording(to: outURL, recordingDelegate: self)
        isRecording = true
        recordingDurationSec = 0
        recordStartDate = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordStartDate else { return }
            Task { @MainActor in
                self.recordingDurationSec = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        isRecording = false
    }

    // MARK: - Session Configuration

    private func configureSession() {
        let settingsSnapshot = activeSettings
        let videoMode = isVideoMode
        let front = isFrontCamera

        sessionQueue.async {
            self.session.beginConfiguration()

            if let existing = self.videoInput {
                self.session.removeInput(existing)
                self.videoInput = nil
            }
            if let existingAudio = self.audioInput {
                self.session.removeInput(existingAudio)
                self.audioInput = nil
            }

            let device = self.bestCaptureDevice(front: front, videoMode: videoMode)
            guard let device, let newInput = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(newInput)
            self.videoInput = newInput

            if videoMode {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                   let audioDev = AVCaptureDevice.default(for: .audio),
                   let aInput = try? AVCaptureDeviceInput(device: audioDev),
                   self.session.canAddInput(aInput) {
                    self.session.addInput(aInput)
                    self.audioInput = aInput
                }

                self.session.removeOutput(self.photoOutput)
                self.session.removeOutput(self.videoDataOutput)
                if !self.session.outputs.contains(self.movieOutput), self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
                self.configureVideoHDRFormat(device: device, settings: settingsSnapshot)
            } else {
                self.session.removeOutput(self.movieOutput)
                if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                if !self.session.outputs.contains(self.videoDataOutput), self.session.canAddOutput(self.videoDataOutput) {
                    self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoBufferQueue)
                    self.session.addOutput(self.videoDataOutput)
                }
                if let conn = self.videoDataOutput.connection(with: .video), conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
                self.session.sessionPreset = .photo
                DispatchQueue.main.async {
                    self.isVideoHdrActive = false
                    self.videoDynamicRangeLabel = "SDR"
                }
            }

            self.session.commitConfiguration()

            // Determine optical zoom bounds & always start at widest focal length
            let switchOver = CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1.0)
            let hwMin = device.minAvailableVideoZoomFactor
            let hwMax = min(device.maxAvailableVideoZoomFactor, 8.0 * switchOver)

            try? device.lockForConfiguration()
            device.videoZoomFactor = hwMin
            device.setExposureTargetBias(0, completionHandler: nil)
            if device.hasTorch {
                device.torchMode = (videoMode && self.isFlashEnabled && !front) ? .on : .off
            }
            device.unlockForConfiguration()

            let minEv = max(device.minExposureTargetBias, -2.5)
            let maxEv = min(device.maxExposureTargetBias, 2.5)

            DispatchQueue.main.async {
                self.switchOverFactor = switchOver
                self.minUiZoom = hwMin / switchOver
                self.maxUiZoom = hwMax / switchOver
                self.currentUiZoom = hwMin / switchOver
                self.minEvBias = minEv
                self.maxEvBias = maxEv
                self.currentEvBias = 0
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureVideoHDRFormat(device: AVCaptureDevice, settings: CameraSettings) {
        let targetWidth = settings.videoResolution.targetWidth
        let targetFps = Double(settings.videoFps.rawValue)
        let wantsHdr = settings.hdrMode != .off

        // Search matching format: prefer exact Res + FPS + HLG_BT2020 HDR, cascade safely down to SDR 1080p 30fps
        let formats = device.formats.filter {
            CMFormatDescriptionGetMediaType($0.formatDescription) == kCMMediaType_Video
        }

        func findFormat(width: Int32, fps: Double, hdrOnly: Bool) -> AVCaptureDevice.Format? {
            formats.first { fmt in
                let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                let hasRes = dim.width == width
                let hasFps = fmt.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= fps && $0.maxFrameRate >= fps
                }
                let hasHdr = !hdrOnly || (fmt.isVideoHDRSupported && fmt.supportedColorSpaces.contains(.HLG_BT2020))
                return hasRes && hasFps && hasHdr
            }
        }

        var chosen: AVCaptureDevice.Format?
        var chosenHdr = false
        var chosenResLabel = settings.videoResolution.rawValue
        var chosenFps = targetFps

        if wantsHdr, let f = findFormat(width: targetWidth, fps: targetFps, hdrOnly: true) {
            chosen = f; chosenHdr = true
        } else if wantsHdr, let f = findFormat(width: 1920, fps: 30, hdrOnly: true) {
            chosen = f; chosenHdr = true; chosenResLabel = "1080p"; chosenFps = 30
        } else if let f = findFormat(width: targetWidth, fps: targetFps, hdrOnly: false) {
            chosen = f; chosenHdr = false
        } else if let f = findFormat(width: 1920, fps: 30, hdrOnly: false) {
            chosen = f; chosenHdr = false; chosenResLabel = "1080p"; chosenFps = 30
        }

        if let chosen {
            if session.canSetSessionPreset(.inputPriority) {
                session.sessionPreset = .inputPriority
            }
            do {
                try device.lockForConfiguration()
                device.activeFormat = chosen
                let frameDur = CMTime(value: 1, timescale: CMTimeScale(chosenFps))
                device.activeVideoMinFrameDuration = frameDur
                device.activeVideoMaxFrameDuration = frameDur
                if chosenHdr && chosen.supportedColorSpaces.contains(.HLG_BT2020) {
                    device.activeColorSpace = .HLG_BT2020
                }
                device.unlockForConfiguration()
            } catch {
                chosenHdr = false
            }
        } else {
            session.sessionPreset = .high
            chosenHdr = false
            chosenResLabel = "1080p"
            chosenFps = 30
        }

        DispatchQueue.main.async {
            self.isVideoHdrActive = chosenHdr
            self.videoDynamicRangeLabel = chosenHdr ? "HDR10" : "SDR"
            self.videoSpecLabel = "\(chosenResLabel)·\(Int(chosenFps))"
        }
    }

    private func bestCaptureDevice(front: Bool, videoMode: Bool) -> AVCaptureDevice? {
        let pos: AVCaptureDevice.Position = front ? .front : .back
        let types: [AVCaptureDevice.DeviceType] = front
            ? [.builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: pos)
        return discovery.devices.first
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.pendingPhotoContinuation?.resume(throwing: error)
                self.pendingPhotoContinuation = nil
            }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            Task { @MainActor in
                self.pendingPhotoContinuation?.resume(throwing: NSError(domain: "KadrajPhoto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed decoding photo"]))
                self.pendingPhotoContinuation = nil
            }
            return
        }

        Task { @MainActor in
            let aspect = self.activeSettings.aspectRatio
            let maxDim = self.activeSettings.captureQuality.maxPhotoDimension
            let processed = Self.orientAndCropPhoto(rawImage, aspectRatio: aspect, maxDim: maxDim)
            self.pendingPhotoContinuation?.resume(returning: processed)
            self.pendingPhotoContinuation = nil
        }
    }

    private static func orientAndCropPhoto(
        _ image: UIImage,
        aspectRatio: AspectRatioOption,
        maxDim: CGFloat
    ) -> UIImage {
        let rawSize = image.size
        let targetAspect = aspectRatio.previewRatio
        let currentAspect = rawSize.width / max(rawSize.height, 1)

        var cropRect = CGRect(origin: .zero, size: rawSize)
        if abs(currentAspect - targetAspect) > 0.02 {
            if currentAspect > targetAspect {
                let newW = rawSize.height * targetAspect
                cropRect = CGRect(x: (rawSize.width - newW) * 0.5, y: 0, width: newW, height: rawSize.height)
            } else {
                let newH = rawSize.width / targetAspect
                cropRect = CGRect(x: 0, y: (rawSize.height - newH) * 0.5, width: rawSize.width, height: newH)
            }
        }

        let maxCropSide = max(cropRect.width, cropRect.height)
        let scale = maxCropSide > maxDim ? (maxDim / maxCropSide) : 1.0
        let finalSize = CGSize(width: floor(cropRect.width * scale), height: floor(cropRect.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: finalSize, format: format).image { _ in
            let drawOrigin = CGPoint(x: -cropRect.origin.x * scale, y: -cropRect.origin.y * scale)
            image.draw(in: CGRect(origin: drawOrigin, size: CGSize(width: rawSize.width * scale, height: rawSize.height * scale)))
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil

            if let error {
                self.pendingVideoCompletion?(.failure(error))
            } else {
                let res = RecordedVideoResult(
                    url: outputFileURL,
                    isHdr: self.isVideoHdrActive,
                    dynamicRangeLabel: self.videoDynamicRangeLabel,
                    specLabel: self.videoSpecLabel
                )
                self.pendingVideoCompletion?(.success(res))
            }
            self.pendingVideoCompletion = nil
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestSnapshotBuffer = pixelBuffer
        frameLock.unlock()
    }
}

