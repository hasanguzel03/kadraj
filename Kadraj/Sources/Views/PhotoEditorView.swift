import SwiftUI

private enum PhotoEditorTab {
    case filters
    case adjust
}

private enum PhotoAdjustParam: String, CaseIterable, Identifiable {
    case brightness = "Brightness"
    case contrast = "Contrast"
    case saturation = "Saturation"
    case warmth = "Warmth"
    case vignette = "Vignette"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .warmth: return "thermometer.medium"
        case .vignette: return "camera.aperture"
        }
    }
}

struct PhotoEditorView: View {
    @ObservedObject var viewModel: KadrajViewModel

    @State private var activeTab: PhotoEditorTab = .filters
    @State private var selectedParam: PhotoAdjustParam = .brightness
    @State private var isComparing = false

    private var hasEdits: Bool {
        viewModel.selectedPhotoProfile != .original || viewModel.photoAdjustments.hasManualEdits
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button {
                    viewModel.haptics.triggerModeSwitch()
                    viewModel.returnToCamera()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Camera")
                    }
                    .font(KadrajTheme.textFont(size: 15, weight: .semibold))
                    .foregroundColor(KadrajTheme.yellow)
                }

                Spacer()

                Text("Edit")
                    .font(KadrajTheme.displayFont(size: 18, weight: .semibold))
                    .foregroundColor(KadrajTheme.label)

                Spacer()

                HStack(spacing: 10) {
                    if hasEdits {
                        Button("Reset") {
                            viewModel.resetPhotoEdits()
                        }
                        .font(KadrajTheme.textFont(size: 13, weight: .medium))
                        .foregroundColor(KadrajTheme.red)
                    }

                    Button {
                        viewModel.savePhoto()
                    } label: {
                        Text(viewModel.isSaving ? "Saving..." : "Done")
                            .font(KadrajTheme.textFont(size: 13, weight: .semibold))
                            .foregroundColor(viewModel.isSaving ? KadrajTheme.secondaryLabel : KadrajTheme.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(viewModel.isSaving ? KadrajTheme.secondarySurface : KadrajTheme.yellow)
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.isSaving || viewModel.capturedPhoto == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Preview Canvas
            ZStack {
                let displayImg = isComparing
                    ? (viewModel.photoProxyBase ?? viewModel.capturedPhoto)
                    : (viewModel.photoPreviewRendered ?? viewModel.photoProxyBase ?? viewModel.capturedPhoto)

                if let uiImg = displayImg {
                    ZStack {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            viewModel.togglePhotoAutoHdr()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("AUTO HDR")
                                    .font(KadrajTheme.textFont(size: 10, weight: .bold).monospacedDigit())
                            }
                            .foregroundColor(!isComparing && viewModel.photoAdjustments.autoHdrEnabled ? KadrajTheme.black : KadrajTheme.label)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(!isComparing && viewModel.photoAdjustments.autoHdrEnabled ? KadrajTheme.yellow : KadrajTheme.capsuleDark)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(activeProfileBadge)
                            .font(KadrajTheme.textFont(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(isComparing ? KadrajTheme.yellow : KadrajTheme.label)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(KadrajTheme.capsuleDark)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))
                            .padding(10)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.split.2x1")
                                .font(.system(size: 11))
                            Text("Compare")
                                .font(KadrajTheme.textFont(size: 10, weight: .semibold))
                        }
                        .foregroundColor(KadrajTheme.label)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(KadrajTheme.capsuleDark)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))
                        .padding(10)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in isComparing = true }
                                .onEnded { _ in isComparing = false }
                        )
                    }
                } else {
                    ProgressView().tint(KadrajTheme.yellow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)

            // Controls Area
            VStack(spacing: 8) {
                if activeTab == .filters {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FilmProfile.allCases) { profile in
                                let thumb = viewModel.photoThumbnails.first(where: { $0.0 == profile })?.1
                                let isSelected = profile == viewModel.selectedPhotoProfile
                                Button {
                                    viewModel.selectPhotoProfile(profile)
                                } label: {
                                    VStack(spacing: 5) {
                                        if let img = thumb {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 66, height: 66)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(isSelected ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: isSelected ? 2 : 0.6)
                                                )
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(KadrajTheme.capsuleDark)
                                                .frame(width: 66, height: 66)
                                        }
                                        Text(profile.displayName)
                                            .font(KadrajTheme.textFont(size: 10, weight: .medium))
                                            .foregroundColor(isSelected ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 78)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 94)

                    if viewModel.selectedPhotoProfile != .original {
                        IosSlimSliderView(
                            label: "Intensity",
                            valueText: "\(Int((viewModel.photoAdjustments.filterStrength * 100).rounded()))%",
                            value: Binding(
                                get: { viewModel.photoAdjustments.filterStrength },
                                set: { v in
                                    var copy = viewModel.photoAdjustments
                                    copy.filterStrength = v
                                    viewModel.updatePhotoAdjustments(copy)
                                }
                            ),
                            range: 0...1,
                            neutralValue: nil,
                            onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
                        )
                    } else {
                        Text("Select a film emulation profile")
                            .font(KadrajTheme.textFont(size: 11, weight: .medium))
                            .foregroundColor(KadrajTheme.secondaryLabel)
                            .frame(height: 44)
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(PhotoAdjustParam.allCases) { param in
                            let isSelected = param == selectedParam
                            let prog = normalizedDelta(param)
                            Button {
                                viewModel.haptics.triggerModeSwitch()
                                selectedParam = param
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? KadrajTheme.secondarySurface : KadrajTheme.elevated)
                                            .frame(width: 46, height: 46)
                                            .overlay(Circle().stroke(isSelected ? Color.white.opacity(0.5) : KadrajTheme.hairline, lineWidth: 1))
                                        if abs(prog) > 0.02 {
                                            Circle()
                                                .trim(from: prog > 0 ? 0 : (1 + prog * 0.5), to: prog > 0 ? prog * 0.5 : 1)
                                                .stroke(KadrajTheme.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                                .rotationEffect(.degrees(-90))
                                                .frame(width: 46, height: 46)
                                        }
                                        Image(systemName: param.symbol)
                                            .font(.system(size: 16))
                                            .foregroundColor(isSelected ? KadrajTheme.yellow : KadrajTheme.label)
                                    }
                                    Text(param.rawValue)
                                        .font(KadrajTheme.textFont(size: 10, weight: .medium))
                                        .foregroundColor(isSelected ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 80)

                    sliderForSelectedParam
                }
            }
            .frame(height: 158)
            .padding(.horizontal, 10)

            // Bottom Tabs
            HStack(spacing: 48) {
                tabButton(title: "Filters", icon: "wand.and.rays", selected: activeTab == .filters) {
                    if activeTab != .filters {
                        viewModel.haptics.triggerModeSwitch()
                        activeTab = .filters
                    }
                }
                tabButton(title: "Adjust", icon: "slider.horizontal.3", selected: activeTab == .adjust) {
                    if activeTab != .adjust {
                        viewModel.haptics.triggerModeSwitch()
                        activeTab = .adjust
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(KadrajTheme.black.ignoresSafeArea())
    }

    private var activeProfileBadge: String {
        if isComparing { return "ORIGINAL" }
        if viewModel.selectedPhotoProfile == .original {
            return viewModel.photoAdjustments.autoHdrEnabled ? "AUTO HDR" : "ORIGINAL"
        }
        let pct = Int((viewModel.photoAdjustments.filterStrength * 100).rounded())
        return viewModel.photoAdjustments.autoHdrEnabled
            ? "HDR · \(viewModel.selectedPhotoProfile.displayName.uppercased()) · \(pct)%"
            : "\(viewModel.selectedPhotoProfile.displayName.uppercased()) · \(pct)%"
    }

    @ViewBuilder
    private var sliderForSelectedParam: some View {
        switch selectedParam {
        case .brightness:
            IosSlimSliderView(
                label: "Brightness",
                valueText: "\(Int(viewModel.photoAdjustments.brightness.rounded()))",
                value: Binding(
                    get: { viewModel.photoAdjustments.brightness },
                    set: { v in var c = viewModel.photoAdjustments; c.brightness = v; viewModel.updatePhotoAdjustments(c) }
                ),
                range: -80...80,
                neutralValue: 0,
                onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
            )
        case .contrast:
            IosSlimSliderView(
                label: "Contrast",
                valueText: String(format: "%.2f×", viewModel.photoAdjustments.contrast),
                value: Binding(
                    get: { viewModel.photoAdjustments.contrast },
                    set: { v in var c = viewModel.photoAdjustments; c.contrast = v; viewModel.updatePhotoAdjustments(c) }
                ),
                range: 0.5...1.8,
                neutralValue: 1.0,
                onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
            )
        case .saturation:
            IosSlimSliderView(
                label: "Saturation",
                valueText: "\(Int((viewModel.photoAdjustments.saturation * 100).rounded()))%",
                value: Binding(
                    get: { viewModel.photoAdjustments.saturation },
                    set: { v in var c = viewModel.photoAdjustments; c.saturation = v; viewModel.updatePhotoAdjustments(c) }
                ),
                range: 0...2.0,
                neutralValue: 1.0,
                onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
            )
        case .warmth:
            IosSlimSliderView(
                label: "Warmth",
                valueText: "\(Int(viewModel.photoAdjustments.warmth.rounded()))",
                value: Binding(
                    get: { viewModel.photoAdjustments.warmth },
                    set: { v in var c = viewModel.photoAdjustments; c.warmth = v; viewModel.updatePhotoAdjustments(c) }
                ),
                range: -40...40,
                neutralValue: 0,
                onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
            )
        case .vignette:
            IosSlimSliderView(
                label: "Vignette",
                valueText: "\(Int((viewModel.photoAdjustments.vignette * 100).rounded()))%",
                value: Binding(
                    get: { viewModel.photoAdjustments.vignette },
                    set: { v in var c = viewModel.photoAdjustments; c.vignette = v; viewModel.updatePhotoAdjustments(c) }
                ),
                range: 0...0.85,
                neutralValue: nil,
                onNeutralCross: { viewModel.haptics.triggerNeutralSnapTick() }
            )
        }
    }

    private func normalizedDelta(_ param: PhotoAdjustParam) -> CGFloat {
        switch param {
        case .brightness: return CGFloat(viewModel.photoAdjustments.brightness / 80.0)
        case .contrast: return CGFloat((viewModel.photoAdjustments.contrast - 1.0) / 0.8)
        case .saturation: return CGFloat(viewModel.photoAdjustments.saturation - 1.0)
        case .warmth: return CGFloat(viewModel.photoAdjustments.warmth / 40.0)
        case .vignette: return CGFloat(viewModel.photoAdjustments.vignette / 0.85)
        }
    }

    private func tabButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(KadrajTheme.textFont(size: 10, weight: .semibold))
            }
            .foregroundColor(selected ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
        }
    }
}

struct IosSlimSliderView: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutralValue: Double?
    let onNeutralCross: () -> Void

    @State private var wasNearNeutral = true

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(KadrajTheme.textFont(size: 11, weight: .semibold))
                    .foregroundColor(KadrajTheme.secondaryLabel)
                Spacer()
                Text(valueText)
                    .font(KadrajTheme.textFont(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(KadrajTheme.yellow)
            }

            GeometryReader { geo in
                let pad: CGFloat = 8
                let usable = max(geo.size.width - pad * 2, 1)
                let span = max(range.upperBound - range.lowerBound, 0.0001)
                let frac = CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
                let thumbX = pad + frac * usable
                let anchorX: CGFloat = {
                    if let neutral = neutralValue {
                        let nf = CGFloat(min(max((neutral - range.lowerBound) / span, 0), 1))
                        return pad + nf * usable
                    }
                    return pad
                }()

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(KadrajTheme.secondarySurface)
                        .frame(height: 2.5)
                        .padding(.horizontal, pad)

                    Capsule()
                        .fill(KadrajTheme.yellow)
                        .frame(width: abs(thumbX - anchorX), height: 2.5)
                        .offset(x: min(thumbX, anchorX))

                    if neutralValue != nil {
                        Capsule()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 1.5, height: 10)
                            .offset(x: anchorX - 0.75)
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .offset(x: thumbX - 7)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let f = Double(min(max((gesture.location.x - pad) / usable, 0), 1))
                            let next = range.lowerBound + f * span
                            if let neutral = neutralValue {
                                let isNear = abs(next - neutral) <= span * 0.025
                                if isNear && !wasNearNeutral { onNeutralCross() }
                                wasNearNeutral = isNear
                            }
                            value = next
                        }
                )
            }
            .frame(height: 26)
        }
        .padding(.horizontal, 10)
    }
}
