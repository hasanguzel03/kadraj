import SwiftUI
import AVFoundation

struct CameraScreenView: View {
    @ObservedObject var viewModel: KadrajViewModel
    @ObservedObject var cameraService: CameraService
    @ObservedObject var angleAnalyzer: AngleAnalyzer
    @ObservedObject var settingsStore: CameraSettingsStore

    @State private var showProSettings = false
    @State private var countdownSecondsLeft = 0
    @State private var countdownTask: Task<Void, Never>?

    // Tap-to-Focus + Vertical Sun EV Drag state
    @State private var touchFocusPoint: CGPoint?
    @State private var tapVersion = 0
    @State private var isFocusLocked = false
    @State private var isFocusVisible = false
    @State private var isDraggingEv = false
    @State private var dragStartEv: Float = 0
    @State private var hideFocusTask: Task<Void, Never>?
    @State private var wasNearZeroEv = true

    // Horizon haptic hysteresis
    @State private var wasHorizonLevel = false
    @State private var lastHorizonTick = Date.distantPast

    // Shutter press animation
    @State private var isShutterPressed = false

    private var camera: CameraService { cameraService }
    private var settings: CameraSettings { settingsStore.settings }

    var body: some View {
        ZStack {
            KadrajTheme.black.ignoresSafeArea()

            if cameraService.isAuthorized {
                VStack(spacing: 0) {
                    topBar

                    // Dynamic Aspect Ratio Viewfinder
                    GeometryReader { geo in
                        let targetRatio: CGFloat = viewModel.selectedMode == .video ? (9.0 / 16.0) : settings.aspectRatio.previewRatio
                        let containerRatio = geo.size.height > 0 ? (geo.size.width / geo.size.height) : 0.5625
                        let fittedSize: CGSize = {
                            if targetRatio > containerRatio {
                                return CGSize(width: geo.size.width, height: geo.size.width / targetRatio)
                            } else {
                                return CGSize(width: geo.size.height * targetRatio, height: geo.size.height)
                            }
                        }()

                        ZStack {
                            CameraPreviewRepresentable(cameraService: viewModel.cameraService)

                            if viewModel.captureState == .ready {
                                GridAndHorizonView(
                                    showThirds: settings.enableThirdsGrid,
                                    showGoldenRatio: settings.enableGoldenRatioGrid,
                                    showHorizon: viewModel.selectedMode == .level || settings.enableHorizonLevel,
                                    alwaysShowHorizon: viewModel.selectedMode == .level,
                                    showCrosshair: viewModel.selectedMode == .level,
                                    rollDegrees: viewModel.angleAnalyzer.orientation.rollDegrees
                                )
                            }

                            if viewModel.captureState != .ready {
                                AngleGuideOverlay(
                                    guideState: viewModel.captureState == .capturing
                                        ? CompositionGuideState(alignmentScore: 1.0, isAligned: true, isStable: true, isReadyToCapture: true, currentRollDegrees: viewModel.angleAnalyzer.orientation.rollDegrees)
                                        : viewModel.guideState,
                                    isScanning: viewModel.captureState == .analyzingScene
                                )
                            }

                            if viewModel.captureState == .ready {
                                TouchFocusEvOverlay(
                                    focusPoint: touchFocusPoint,
                                    tapVersion: tapVersion,
                                    isFocusLocked: isFocusLocked,
                                    evBias: viewModel.cameraService.currentEvBias,
                                    minEv: viewModel.cameraService.minEvBias,
                                    maxEv: viewModel.cameraService.maxEvBias,
                                    isDraggingEv: isDraggingEv,
                                    isVisible: isFocusVisible
                                )
                            }

                            // EV Pill HUD (#1C1C1E @ 65%, tabular digits)
                            if viewModel.captureState == .ready && (isDraggingEv || abs(viewModel.cameraService.currentEvBias) > 0.05) {
                                evBadge
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(.top, 12)
                            }

                            // Video Timer + Spec + HDR Badge
                            if viewModel.selectedMode == .video && viewModel.captureState == .ready {
                                videoStatusCapsule
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(.top, (isDraggingEv || abs(viewModel.cameraService.currentEvBias) > 0.05) ? 46 : 12)
                            }

                            // Self-Timer Countdown
                            if countdownSecondsLeft > 0 {
                                Text("\(countdownSecondsLeft)")
                                    .font(KadrajTheme.displayFont(size: 40, weight: .bold).monospacedDigit())
                                    .foregroundColor(KadrajTheme.yellow)
                                    .frame(width: 84, height: 84)
                                    .background(KadrajTheme.capsuleDark)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(KadrajTheme.yellow.opacity(0.7), lineWidth: 1.2))
                            }

                            // Interactive Apple Zoom Dial
                            zoomControlBar
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, 14)
                        }
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(Rectangle())
                        .gesture(tapFocusGesture)
                        .simultaneousGesture(evVerticalDragGesture)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .animation(.easeInOut(duration: 0.22), value: targetRatio)
                    }

                    bottomShutterDock
                }
            } else {
                permissionView
            }

            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(KadrajTheme.textFont(size: 13, weight: .medium))
                        .foregroundColor(KadrajTheme.label)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(KadrajTheme.capsuleDark)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))
                        .padding(.bottom, 160)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        viewModel.toastMessage = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showProSettings) {
            ProSettingsView(
                settings: $settingsStore.settings,
                haptics: viewModel.haptics
            )
        }
        .onChange(of: angleAnalyzer.orientation.rollDegrees) { roll in
            checkHorizonHaptic(roll: roll)
        }
        .onChange(of: viewModel.captureState) { newState in
            if newState != .ready {
                isFocusVisible = false
                isDraggingEv = false
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.haptics.triggerModeSwitch()
                viewModel.cameraService.toggleFlash()
            } label: {
                let flashActive = viewModel.cameraService.isFlashEnabled && !viewModel.cameraService.isFrontCamera
                Image(systemName: flashActive ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(
                        viewModel.cameraService.isFrontCamera ? KadrajTheme.tertiaryLabel
                        : (flashActive ? KadrajTheme.black : KadrajTheme.label)
                    )
                    .frame(width: 36, height: 36)
                    .background(flashActive ? KadrajTheme.yellow : KadrajTheme.capsuleDark)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(flashActive ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: 0.6))
            }
            .disabled(viewModel.cameraService.isFrontCamera)

            Spacer()

            // Quick Horizon + Aspect / HDR Capsule
            let isLevelActive = viewModel.selectedMode == .level || settings.enableHorizonLevel
            Button {
                guard viewModel.selectedMode != .level else { return }
                viewModel.haptics.triggerModeSwitch()
                viewModel.settingsStore.settings.enableHorizonLevel.toggle()
            } label: {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Capsule().frame(width: 4, height: 1.6)
                        Capsule().frame(width: 8, height: 2.0)
                        Capsule().frame(width: 4, height: 1.6)
                    }
                    Text(viewModel.selectedMode == .video ? settings.hdrMode.rawValue.uppercased() : settings.aspectRatio.rawValue)
                        .font(KadrajTheme.textFont(size: 10, weight: .semibold).monospacedDigit())
                }
                .foregroundColor(isLevelActive ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(KadrajTheme.capsuleDark)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isLevelActive ? KadrajTheme.yellow.opacity(0.55) : KadrajTheme.hairline, lineWidth: 0.6))
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    viewModel.haptics.triggerModeSwitch()
                    viewModel.settingsStore.settings.enableThirdsGrid.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(settings.enableThirdsGrid ? KadrajTheme.yellow : KadrajTheme.label)
                        .frame(width: 36, height: 36)
                        .background(settings.enableThirdsGrid ? KadrajTheme.yellowDim : KadrajTheme.capsuleDark)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(settings.enableThirdsGrid ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: 0.6))
                }

                Button {
                    viewModel.haptics.triggerModeSwitch()
                    showProSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KadrajTheme.label)
                        .frame(width: 36, height: 36)
                        .background(KadrajTheme.capsuleDark)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(KadrajTheme.hairline, lineWidth: 0.6))
                }
                .disabled(viewModel.cameraService.isRecording || viewModel.captureState != .ready)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - HUD Capsules

    private var evBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11))
            Text(formatEvLabel(viewModel.cameraService.currentEvBias))
                .font(KadrajTheme.displayFont(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundColor(KadrajTheme.yellow)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(KadrajTheme.capsuleDark)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(KadrajTheme.yellow.opacity(0.55), lineWidth: 0.6))
    }

    private var videoStatusCapsule: some View {
        HStack(spacing: 8) {
            if viewModel.cameraService.isRecording {
                Circle()
                    .fill(KadrajTheme.label)
                    .frame(width: 7, height: 7)
            }
            Text(formatDuration(viewModel.cameraService.recordingDurationSec))
                .font(KadrajTheme.displayFont(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(KadrajTheme.label)
            Text("\(viewModel.cameraService.videoSpecLabel) · \(viewModel.cameraService.videoDynamicRangeLabel)")
                .font(KadrajTheme.textFont(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(
                    viewModel.cameraService.isRecording ? KadrajTheme.label
                    : (viewModel.cameraService.isVideoHdrActive ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(viewModel.cameraService.isRecording ? KadrajTheme.red.opacity(0.85) : KadrajTheme.capsuleDark)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                viewModel.cameraService.isRecording ? KadrajTheme.red
                : (viewModel.cameraService.isVideoHdrActive ? KadrajTheme.yellow.opacity(0.55) : KadrajTheme.hairline),
                lineWidth: 0.6
            )
        )
    }

    private var zoomControlBar: some View {
        let minZ = viewModel.cameraService.minUiZoom
        let maxZ = viewModel.cameraService.maxUiZoom
        let curZ = viewModel.cameraService.currentUiZoom
        let stops: [CGFloat] = {
            var list: [CGFloat] = []
            if minZ < 0.85 { list.append(minZ) }
            if minZ <= 1.0 && maxZ >= 1.0 { list.append(1.0) } else if list.isEmpty { list.append(minZ) }
            if minZ >= 0.85 && maxZ >= 1.55 { list.append(1.5) }
            if maxZ >= 2.0 { list.append(2.0) }
            return list
        }()

        let activeIdx = stops.indices.min { abs(stops[$0] - curZ) < abs(stops[$1] - curZ) } ?? 0
        let highlighted = viewModel.captureState == .guiding || viewModel.captureState == .capturing

        return Group {
            if stops.count <= 1 {
                Text(formatZoomLabel(curZ))
                    .font(KadrajTheme.displayFont(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(KadrajTheme.yellow)
                    .frame(width: 38, height: 38)
                    .background(KadrajTheme.capsuleDark)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(highlighted ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: highlighted ? 1.0 : 0.6))
            } else {
                HStack(spacing: 4) {
                    ForEach(stops.indices, id: \.self) { idx in
                        let stop = stops[idx]
                        let selected = idx == activeIdx
                        let label = (selected && abs(curZ - stop) > 0.12) ? formatZoomLabel(curZ) : formatZoomLabel(stop)
                        Button {
                            viewModel.haptics.triggerModeSwitch()
                            viewModel.cameraService.animateZoom(to: stop)
                        } label: {
                            Text(label)
                                .font(KadrajTheme.displayFont(size: selected ? 11.5 : 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(selected ? KadrajTheme.yellow : Color.white.opacity(0.85))
                                .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                                .background(selected ? Color.white.opacity(0.12) : Color.clear)
                                .clipShape(Circle())
                        }
                        .disabled(viewModel.captureState != .ready || countdownSecondsLeft > 0)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(KadrajTheme.capsuleDark)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(highlighted ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: highlighted ? 1.0 : 0.6))
            }
        }
    }

    // MARK: - Bottom Shutter Dock

    private var bottomShutterDock: some View {
        let isCounting = countdownSecondsLeft > 0
        let isVideo = viewModel.selectedMode == .video
        let isRecording = viewModel.cameraService.isRecording
        let isGuiding = viewModel.captureState == .guiding
        let isStopShape = isCounting || isRecording

        let ringColor: Color = (isCounting || (isGuiding && viewModel.guideState.alignmentScore > 0.85) || viewModel.captureState == .capturing)
            ? KadrajTheme.yellow
            : .white
        let coreColor: Color = isVideo ? KadrajTheme.red : ringColor

        return VStack(spacing: 14) {
            // Mode Strip
            HStack(spacing: 2) {
                ForEach(CameraCaptureMode.allCases) { mode in
                    let isSelected = mode == viewModel.selectedMode
                    Button {
                        viewModel.selectCaptureMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(KadrajTheme.textFont(size: 11, weight: .semibold).monospacedDigit())
                            .tracking(0.8)
                            .foregroundColor(isSelected ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.captureState != .ready || isCounting || isRecording)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(KadrajTheme.capsuleDark)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))

            // Action Row: Analyze | Shutter | Flip
            HStack {
                // Left: Analyze / Cancel
                Button {
                    if isGuiding { viewModel.cancelAnalysis() } else { viewModel.startSceneAnalysis() }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: isGuiding ? "xmark" : "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isGuiding ? KadrajTheme.black : KadrajTheme.label)
                            .frame(width: 48, height: 48)
                            .background(isGuiding ? KadrajTheme.yellow : KadrajTheme.capsuleDark)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(isGuiding ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: 0.6))
                        Text(isGuiding ? "Cancel" : "Analyze")
                            .font(KadrajTheme.textFont(size: 10, weight: .medium))
                            .foregroundColor(isGuiding ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                    }
                }
                .opacity(isVideo ? 0 : 1)
                .disabled(isVideo || isCounting || viewModel.captureState == .capturing || viewModel.captureState == .analyzingScene)

                Spacer()

                // Center: iPhone Thin White Outer Ring + Spring Press Core
                ZStack {
                    Circle()
                        .stroke(ringColor, lineWidth: 2.8)
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: isStopShape ? 7 : 32, style: .continuous)
                        .fill(coreColor)
                        .frame(width: isStopShape ? 32 : 64, height: isStopShape ? 32 : 64)
                        .scaleEffect(isShutterPressed ? 0.84 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isShutterPressed)
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isShutterPressed {
                                isShutterPressed = true
                                viewModel.haptics.triggerShutterPress()
                            }
                        }
                        .onEnded { _ in
                            isShutterPressed = false
                            handleShutterTap()
                        }
                )
                .disabled(viewModel.captureState == .capturing || viewModel.captureState == .analyzingScene)

                Spacer()

                // Right: Flip Camera
                Button {
                    viewModel.haptics.triggerModeSwitch()
                    isFocusVisible = false
                    viewModel.cameraService.switchCamera()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(KadrajTheme.label)
                            .frame(width: 48, height: 48)
                            .background(KadrajTheme.capsuleDark)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(KadrajTheme.hairline, lineWidth: 0.6))
                        Text("Flip")
                            .font(KadrajTheme.textFont(size: 10, weight: .medium))
                            .foregroundColor(KadrajTheme.secondaryLabel)
                    }
                }
                .opacity(isRecording ? 0.4 : 1)
                .disabled(isRecording || isCounting || viewModel.captureState != .ready)
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(KadrajTheme.black)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Text("Camera Access")
                .font(KadrajTheme.displayFont(size: 28, weight: .bold))
                .foregroundColor(KadrajTheme.label)
            Text("Allow camera access to use Kadraj.")
                .font(KadrajTheme.textFont(size: 15, weight: .regular))
                .foregroundColor(KadrajTheme.secondaryLabel)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(KadrajTheme.textFont(size: 15, weight: .semibold))
                    .foregroundColor(KadrajTheme.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(KadrajTheme.yellow)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
    }

    // MARK: - Gestures & Helpers

    private var tapFocusGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard viewModel.captureState == .ready, countdownSecondsLeft == 0 else { return }
                touchFocusPoint = value.location
                tapVersion += 1
                isFocusLocked = false
                isFocusVisible = true
                wasNearZeroEv = true
                scheduleFocusFade()

                viewModel.cameraService.tapToFocusAndMeter(at: value.location) { locked in
                    isFocusLocked = locked
                    viewModel.haptics.triggerFocusLock()
                }
            }
    }

    private var evVerticalDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard viewModel.captureState == .ready, isFocusVisible else { return }
                if !isDraggingEv {
                    isDraggingEv = true
                    dragStartEv = viewModel.cameraService.currentEvBias
                    hideFocusTask?.cancel()
                }
                let span = max(viewModel.cameraService.maxEvBias - viewModel.cameraService.minEvBias, 0.5)
                let delta = Float(-value.translation.height / 180.0) * span
                let nextEv = min(max(dragStartEv + delta, viewModel.cameraService.minEvBias), viewModel.cameraService.maxEvBias)
                let isNearZero = abs(nextEv) < 0.08
                if isNearZero && !wasNearZeroEv {
                    viewModel.haptics.triggerNeutralSnapTick()
                }
                wasNearZeroEv = isNearZero
                viewModel.cameraService.setManualExposureBias(nextEv)
            }
            .onEnded { _ in
                guard isDraggingEv else { return }
                isDraggingEv = false
                scheduleFocusFade()
            }
    }

    private func scheduleFocusFade() {
        hideFocusTask?.cancel()
        hideFocusTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, !isDraggingEv else { return }
            isFocusVisible = false
        }
    }

    private func handleShutterTap() {
        if countdownSecondsLeft > 0 {
            viewModel.haptics.triggerModeSwitch()
            countdownTask?.cancel()
            countdownSecondsLeft = 0
            return
        }
        if viewModel.selectedMode == .video {
            isFocusVisible = false
            viewModel.toggleVideoRecording()
            return
        }
        let timerSecs: Int
        switch viewModel.selectedMode {
        case .timer3s: timerSecs = 3
        case .timer10s: timerSecs = 10
        default: timerSecs = 0
        }
        if timerSecs == 0 || viewModel.captureState == .guiding {
            viewModel.capturePhotoNow()
        } else {
            isFocusVisible = false
            countdownTask?.cancel()
            countdownTask = Task {
                for sec in stride(from: timerSecs, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    countdownSecondsLeft = sec
                    viewModel.haptics.triggerHorizonLevelTick()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard !Task.isCancelled else { return }
                countdownSecondsLeft = 0
                viewModel.capturePhotoNow()
            }
        }
    }

    private func checkHorizonHaptic(roll: Double) {
        let levelActive = viewModel.captureState == .guiding || viewModel.selectedMode == .level || settings.enableHorizonLevel
        guard levelActive else {
            wasHorizonLevel = false
            return
        }
        let absRoll = abs(roll)
        let now = Date()
        if !wasHorizonLevel && absRoll < 1.5 {
            wasHorizonLevel = true
            if now.timeIntervalSince(lastHorizonTick) > 0.45 {
                lastHorizonTick = now
                viewModel.haptics.triggerHorizonLevelTick()
            }
        } else if wasHorizonLevel && absRoll >= 2.5 {
            wasHorizonLevel = false
        }
    }

    private func formatZoomLabel(_ z: CGFloat) -> String {
        let rounded = (z * 10).rounded() / 10
        let nearest = rounded.rounded()
        if abs(rounded - nearest) < 0.05 {
            return "\(Int(nearest))×"
        }
        return String(format: "%.1f×", Double(rounded))
    }

    private func formatEvLabel(_ ev: Float) -> String {
        let rounded = (ev * 10).rounded() / 10
        if abs(rounded) < 0.05 { return "0.0 EV" }
        return rounded > 0 ? String(format: "+%.1f EV", rounded) : String(format: "%.1f EV", rounded)
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = max(0, Int(sec))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        cameraService.attachPreviewLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        cameraService.attachPreviewLayer(uiView.previewLayer)
    }

    final class PreviewUIView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
