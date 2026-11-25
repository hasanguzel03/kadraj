import SwiftUI

struct ProSettingsView: View {
    @Binding var settings: CameraSettings
    let haptics: HapticAndSoundHelper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader("FRAMING & COMPOSITION")
                    cardContainer {
                        segmentedRow(
                            title: "Aspect Ratio",
                            subtitle: "Viewfinder and captured photo crop",
                            options: AspectRatioOption.allCases,
                            selection: $settings.aspectRatio,
                            label: { $0.rawValue }
                        )
                        rowDivider
                        toggleRow(
                            title: "3×3 Grid",
                            subtitle: "Rule-of-thirds alignment lines",
                            isOn: $settings.enableThirdsGrid
                        )
                        rowDivider
                        toggleRow(
                            title: "Golden Ratio (Φ)",
                            subtitle: "Classic 0.382 / 0.618 visual guides",
                            isOn: $settings.enableGoldenRatioGrid
                        )
                        rowDivider
                        toggleRow(
                            title: "Horizon Level",
                            subtitle: "Precision CoreMotion tilt indicator",
                            isOn: $settings.enableHorizonLevel
                        )
                    }

                    sectionHeader("VIDEO RECORDING")
                    cardContainer {
                        segmentedRow(
                            title: "Video Resolution",
                            subtitle: "Falls back safely if hardware limits resolution",
                            options: VideoResolutionOption.allCases,
                            selection: $settings.videoResolution,
                            label: { $0.rawValue }
                        )
                        rowDivider
                        segmentedRow(
                            title: "Frame Rate",
                            subtitle: "Smooth 30fps or high-motion 60fps capture",
                            options: VideoFpsOption.allCases,
                            selection: $settings.videoFps,
                            label: { $0.label }
                        )
                    }

                    sectionHeader("HDR & FORMAT QUALITY")
                    cardContainer {
                        segmentedRow(
                            title: "HDR Mode",
                            subtitle: "10-bit HLG Video & Photo dynamic tone mapping",
                            options: HdrModeOption.allCases,
                            selection: $settings.hdrMode,
                            label: { $0.rawValue }
                        )
                        rowDivider
                        segmentedRow(
                            title: "Capture Format & Quality",
                            subtitle: "High Efficiency (95%) vs Max Quality (98% Full-Res)",
                            options: CaptureQualityOption.allCases,
                            selection: $settings.captureQuality,
                            label: { $0.rawValue }
                        )
                        rowDivider
                        toggleRow(
                            title: "Auto-Enhance / Post-HDR",
                            subtitle: "Highlight recovery, shadow lift & clarity after capture",
                            isOn: $settings.autoEnhancePostHdr
                        )
                    }

                    sectionHeader("TACTILE & AUDIO")
                    cardContainer {
                        toggleRow(
                            title: "Haptic Feedback",
                            subtitle: "Focus lock, level ticks & shutter impulse",
                            isOn: $settings.hapticsEnabled
                        )
                        rowDivider
                        toggleRow(
                            title: "Shutter Sound",
                            subtitle: "Acoustic click on capture & record start/stop",
                            isOn: $settings.shutterSoundEnabled
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(KadrajTheme.black.ignoresSafeArea())
            .navigationTitle("Pro Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        haptics.triggerModeSwitch()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(KadrajTheme.label)
                            .frame(width: 32, height: 32)
                            .background(KadrajTheme.capsuleDark)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(KadrajTheme.hairline, lineWidth: 0.6))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        haptics.triggerModeSwitch()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(KadrajTheme.textFont(size: 13, weight: .semibold))
                            .foregroundColor(KadrajTheme.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(KadrajTheme.yellow)
                            .clipShape(Capsule())
                    }
                }
            }
            .toolbarBackground(KadrajTheme.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(KadrajTheme.textFont(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(KadrajTheme.secondaryLabel)
            .padding(.horizontal, 8)
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(KadrajTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KadrajTheme.hairline, lineWidth: 0.5)
        )
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.leading, 16)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KadrajTheme.textFont(size: 15, weight: .medium))
                    .foregroundColor(KadrajTheme.label)
                Text(subtitle)
                    .font(KadrajTheme.textFont(size: 12, weight: .regular))
                    .foregroundColor(KadrajTheme.secondaryLabel)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newVal in
                    haptics.triggerModeSwitch()
                    isOn.wrappedValue = newVal
                }
            ))
            .labelsHidden()
            .tint(KadrajTheme.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func segmentedRow<T: Hashable & Identifiable>(
        title: String,
        subtitle: String,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KadrajTheme.textFont(size: 15, weight: .medium))
                    .foregroundColor(KadrajTheme.label)
                Text(subtitle)
                    .font(KadrajTheme.textFont(size: 12, weight: .regular))
                    .foregroundColor(KadrajTheme.secondaryLabel)
            }
            HStack(spacing: 4) {
                ForEach(options) { opt in
                    let isSelected = opt == selection.wrappedValue
                    Button {
                        haptics.triggerModeSwitch()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection.wrappedValue = opt
                        }
                    } label: {
                        Text(label(opt))
                            .font(KadrajTheme.textFont(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundColor(isSelected ? KadrajTheme.black : KadrajTheme.secondaryLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? KadrajTheme.yellow : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(KadrajTheme.hairline, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
