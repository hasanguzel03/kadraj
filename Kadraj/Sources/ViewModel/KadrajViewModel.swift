import Foundation
import SwiftUI
import Combine
import AVFoundation

enum AppRoute {
    case camera
    case photoEditor
    case videoEditor
}

enum CameraCaptureState {
    case ready
    case analyzingScene
    case guiding
    case capturing
}

enum CameraCaptureMode: String, CaseIterable, Identifiable {
    case level = "LEVEL"
    case photo = "PHOTO"
    case video = "VIDEO"
    case timer3s = "3S"
    case timer10s = "10S"

    var id: String { rawValue }
}

@MainActor
final class KadrajViewModel: ObservableObject {
    let settingsStore = CameraSettingsStore()
    let cameraService = CameraService()
    let angleAnalyzer = AngleAnalyzer()
    let haptics = HapticAndSoundHelper.shared
    let filmEngine = FilmEngine.shared

    @Published var route: AppRoute = .camera
    @Published var captureState: CameraCaptureState = .ready
    @Published var selectedMode: CameraCaptureMode = .photo
    @Published var guideState = CompositionGuideState()
    @Published var toastMessage: String?

    // Photo Editor State
    @Published var capturedPhoto: UIImage?
    @Published var photoProxyBase: UIImage?
    @Published var photoPreviewRendered: UIImage?
    @Published var photoThumbnails: [(FilmProfile, UIImage)] = []
    @Published var selectedPhotoProfile: FilmProfile = .original
    @Published var photoAdjustments = ImageAdjustments()

    // Video Editor State
    @Published var recordedVideo: RecordedVideoResult?
    @Published var videoThumbnails: [(FilmProfile, UIImage)] = []
    @Published var selectedVideoProfile: FilmProfile = .original
    @Published var videoFilterStrength: Double = 1.0
    @Published var videoAutoHdr: Bool = false
    @Published var videoExportProgress: Double?
    @Published var isSaving: Bool = false

    private var activeTarget: TargetComposition?
    private var orientationSub: AnyCancellable?
    private var settingsSub: AnyCancellable?
    private var settleTask: Task<Void, Never>?
    private var previewRenderTask: Task<Void, Never>?

    init() {
        syncFeedbackAndCameraSettings(settingsStore.settings)
        settingsSub = settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] newSettings in
                self?.syncFeedbackAndCameraSettings(newSettings)
            }
    }

    private func syncFeedbackAndCameraSettings(_ s: CameraSettings) {
        haptics.hapticsEnabled = s.hapticsEnabled
        haptics.shutterSoundEnabled = s.shutterSoundEnabled
        cameraService.updateSettings(s)
    }

    func onAppear() async {
        await cameraService.checkPermissionsAndStart()
        angleAnalyzer.startMotion()
    }

    func selectCaptureMode(_ mode: CameraCaptureMode) {
        guard captureState == .ready, !cameraService.isRecording else { return }
        haptics.triggerModeSwitch()
        let wasVideo = selectedMode == .video
        let nowVideo = mode == .video
        selectedMode = mode
        if wasVideo != nowVideo {
            cameraService.setVideoMode(nowVideo)
        }
    }

    // MARK: - Smart Composition Analysis & Auto-Capture

    func startSceneAnalysis() {
        guard captureState == .ready, selectedMode != .video else { return }
        haptics.triggerModeSwitch()
        settleTask?.cancel()
        orientationSub?.cancel()
        captureState = .analyzingScene
        angleAnalyzer.startMotion()

        let snapshot = cameraService.currentSnapshotImage()
        let isFront = cameraService.isFrontCamera
        let minZ = cameraService.minUiZoom
        let maxZ = cameraService.maxUiZoom

        Task {
            let target = await angleAnalyzer.computeBestTarget(
                from: snapshot,
                isFrontCamera: isFront,
                minUiZoom: minZ,
                maxUiZoom: maxZ
            )
            guard self.captureState == .analyzingScene else { return }

            self.activeTarget = target
            self.cameraService.animateZoom(to: target.recommendedUiZoom)
            if abs(target.recommendedEvBias) > 0.05 {
                self.cameraService.setManualExposureBias(target.recommendedEvBias)
            }

            self.captureState = .guiding
            self.processOrientation(self.angleAnalyzer.orientation)

            self.orientationSub = self.angleAnalyzer.$orientation
                .receive(on: RunLoop.main)
                .sink { [weak self] ori in
                    self?.processOrientation(ori)
                }
        }
    }

    func cancelAnalysis() {
        haptics.triggerModeSwitch()
        settleTask?.cancel()
        orientationSub?.cancel()
        activeTarget = nil
        guideState = CompositionGuideState()
        captureState = .ready
        cameraService.resetZoomAndExposure()
    }

    private func processOrientation(_ ori: DeviceOrientationState) {
        guard captureState == .guiding, let target = activeTarget else { return }
        let updated = angleAnalyzer.updateGuidance(orientation: ori, target: target)
        guideState = updated

        if updated.isReadyToCapture {
            if settleTask == nil {
                settleTask = Task {
                    try? await Task.sleep(nanoseconds: 380_000_000)
                    guard !Task.isCancelled,
                          self.captureState == .guiding,
                          self.guideState.isAligned else { return }
                    self.cameraService.animateZoom(to: target.recommendedUiZoom)
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled, self.captureState == .guiding else { return }
                    await self.executePhotoCapture(evOverride: target.recommendedEvBias)
                }
            }
        } else {
            settleTask?.cancel()
            settleTask = nil
        }
    }

    func capturePhotoNow() {
        guard captureState == .ready || captureState == .guiding else { return }
        Task {
            await executePhotoCapture(evOverride: nil)
        }
    }

    private func executePhotoCapture(evOverride: Float?) async {
        settleTask?.cancel()
        orientationSub?.cancel()
        captureState = .capturing
        haptics.triggerCaptureConfirmation()
        haptics.playShutterClick()

        do {
            let photo = try await cameraService.capturePhoto(evBias: evOverride)
            onPhotoCaptured(photo)
        } catch {
            toastMessage = "Capture failed: \(error.localizedDescription)"
            captureState = .ready
        }
    }

    private func onPhotoCaptured(_ photo: UIImage) {
        angleAnalyzer.stopMotion()
        capturedPhoto = photo
        let proxy = filmEngine.makeProxyImage(photo, maxDimension: 1080)
        photoProxyBase = proxy

        let s = settingsStore.settings
        let autoHdr: Bool
        switch s.hdrMode {
        case .on:
            autoHdr = true
        case .off:
            autoHdr = s.autoEnhancePostHdr
        case .auto:
            autoHdr = s.autoEnhancePostHdr || filmEngine.isHighDynamicRangeScene(photo)
        }

        selectedPhotoProfile = .original
        photoAdjustments = ImageAdjustments(filterStrength: 1.0, autoHdrEnabled: autoHdr)
        photoThumbnails = []
        route = .photoEditor
        captureState = .ready

        refreshPhotoPreview()
        Task.detached(priority: .userInitiated) { [filmEngine, photo] in
            let thumbs = filmEngine.generateThumbnails(for: photo)
            await MainActor.run {
                self.photoThumbnails = thumbs
            }
        }
    }

    func selectPhotoProfile(_ profile: FilmProfile) {
        haptics.triggerModeSwitch()
        selectedPhotoProfile = profile
        refreshPhotoPreview()
    }

    func togglePhotoAutoHdr() {
        haptics.triggerModeSwitch()
        photoAdjustments.autoHdrEnabled.toggle()
        refreshPhotoPreview()
    }

    func updatePhotoAdjustments(_ next: ImageAdjustments) {
        photoAdjustments = next
        refreshPhotoPreview()
    }

    func resetPhotoEdits() {
        haptics.triggerModeSwitch()
        selectedPhotoProfile = .original
        photoAdjustments = ImageAdjustments()
        refreshPhotoPreview()
    }

    private func refreshPhotoPreview() {
        guard let proxy = photoProxyBase else { return }
        let profile = selectedPhotoProfile
        let adj = photoAdjustments
        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [filmEngine] in
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }
            let rendered = filmEngine.renderUIImage(from: proxy, profile: profile, adjustments: adj)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.photoPreviewRendered = rendered
            }
        }
    }

    func savePhoto() {
        guard !isSaving, let source = capturedPhoto else { return }
        isSaving = true
        haptics.triggerCaptureConfirmation()
        let profile = selectedPhotoProfile
        let adj = photoAdjustments
        let quality = settingsStore.settings.captureQuality.jpegQuality

        Task {
            do {
                let finalImage = await Task.detached(priority: .userInitiated) { [filmEngine] in
                    filmEngine.renderUIImage(from: source, profile: profile, adjustments: adj)
                }.value
                try await filmEngine.savePhotoToLibrary(finalImage, jpegQuality: quality)
                toastMessage = "Saved to Photos"
            } catch {
                toastMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Video Capture & Post-Processing

    func toggleVideoRecording() {
        haptics.triggerCaptureConfirmation()
        if cameraService.isRecording {
            haptics.playRecordStop()
        } else {
            haptics.playRecordStart()
        }

        cameraService.toggleVideoRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let res):
                self.onVideoRecorded(res)
            case .failure(let err):
                self.toastMessage = "Video error: \(err.localizedDescription)"
            }
        }
    }

    private func onVideoRecorded(_ res: RecordedVideoResult) {
        angleAnalyzer.stopMotion()
        recordedVideo = res
        let s = settingsStore.settings
        selectedVideoProfile = .original
        videoFilterStrength = 1.0
        videoAutoHdr = s.autoEnhancePostHdr || s.hdrMode == .on
        videoExportProgress = nil
        videoThumbnails = []
        route = .videoEditor

        Task.detached(priority: .userInitiated) { [filmEngine] in
            let asset = AVURLAsset(url: res.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let ui = UIImage(cgImage: cg)
                let thumbs = filmEngine.generateThumbnails(for: ui)
                await MainActor.run {
                    self.videoThumbnails = thumbs
                }
            }
        }
    }

    func selectVideoProfile(_ profile: FilmProfile) {
        haptics.triggerModeSwitch()
        selectedVideoProfile = profile
    }

    func toggleVideoAutoHdr() {
        haptics.triggerModeSwitch()
        videoAutoHdr.toggle()
    }

    func resetVideoEdits() {
        haptics.triggerModeSwitch()
        selectedVideoProfile = .original
        videoFilterStrength = 1.0
        videoAutoHdr = false
    }

    func saveProcessedVideo() {
        guard !isSaving, let video = recordedVideo else { return }
        isSaving = true
        videoExportProgress = 0
        haptics.triggerCaptureConfirmation()

        let profile = selectedVideoProfile
        let strength = videoFilterStrength
        let autoHdr = videoAutoHdr

        Task {
            do {
                let exportedURL = try await filmEngine.exportVideo(
                    sourceURL: video.url,
                    profile: profile,
                    strength: strength,
                    autoHdr: autoHdr,
                    progressHandler: { pct in
                        Task { @MainActor in
                            self.videoExportProgress = pct
                        }
                    }
                )
                try await filmEngine.saveVideoToLibrary(exportedURL)
                if exportedURL != video.url {
                    try? FileManager.default.removeItem(at: exportedURL)
                }
                toastMessage = "Video saved to Photos"
            } catch {
                toastMessage = error.localizedDescription
            }
            isSaving = false
            videoExportProgress = nil
        }
    }

    func returnToCamera() {
        if let rawURL = recordedVideo?.url {
            try? FileManager.default.removeItem(at: rawURL)
        }
        capturedPhoto = nil
        photoProxyBase = nil
        photoPreviewRendered = nil
        photoThumbnails = []
        recordedVideo = nil
        videoThumbnails = []
        activeTarget = nil
        guideState = CompositionGuideState()
        captureState = .ready
        route = .camera
        cameraService.resetZoomAndExposure()
        angleAnalyzer.startMotion()
    }
}
