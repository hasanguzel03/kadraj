import SwiftUI
import AVKit

struct VideoEditorView: View {
    @ObservedObject var viewModel: KadrajViewModel

    @State private var player = AVPlayer()
    @State private var isPlaying = true
    @State private var loopObserver: Any?

    private var hasEdits: Bool {
        viewModel.selectedVideoProfile != .original || viewModel.videoAutoHdr
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
                .disabled(viewModel.isSaving)

                Spacer()

                // One-tap Auto HDR
                Button {
                    viewModel.toggleVideoAutoHdr()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .semibold))
                        Text("AUTO HDR")
                            .font(KadrajTheme.textFont(size: 10, weight: .bold).monospacedDigit())
                    }
                    .foregroundColor(viewModel.videoAutoHdr ? KadrajTheme.black : KadrajTheme.label)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(viewModel.videoAutoHdr ? KadrajTheme.yellow : KadrajTheme.capsuleDark)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(viewModel.videoAutoHdr ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: 0.6))
                }
                .disabled(viewModel.isSaving)

                Spacer()

                HStack(spacing: 10) {
                    if hasEdits && !viewModel.isSaving {
                        Button("Reset") {
                            viewModel.resetVideoEdits()
                        }
                        .font(KadrajTheme.textFont(size: 13, weight: .medium))
                        .foregroundColor(KadrajTheme.red)
                    }

                    Button {
                        viewModel.saveProcessedVideo()
                    } label: {
                        let title = viewModel.isSaving
                            ? (viewModel.videoExportProgress.map { "\(Int(($0 * 100).rounded()))%" } ?? "...")
                            : "Save"
                        Text(title)
                            .font(KadrajTheme.textFont(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(viewModel.isSaving ? KadrajTheme.yellow : KadrajTheme.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(viewModel.isSaving ? KadrajTheme.secondarySurface : KadrajTheme.yellow)
                            .clipShape(Capsule())
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Video Player Viewport
            ZStack {
                VideoPlayerLayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture {
                        guard !viewModel.isSaving else { return }
                        if isPlaying {
                            player.pause()
                            isPlaying = false
                        } else {
                            player.play()
                            isPlaying = true
                        }
                    }

                if !isPlaying && !viewModel.isSaving {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26))
                        .foregroundColor(KadrajTheme.label)
                        .frame(width: 56, height: 56)
                        .background(KadrajTheme.capsuleDark)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(KadrajTheme.hairline, lineWidth: 0.8))
                        .allowsHitTesting(false)
                }

                if viewModel.isSaving {
                    VStack(spacing: 10) {
                        ProgressView().tint(KadrajTheme.yellow)
                        let pct = Int(((viewModel.videoExportProgress ?? 0) * 100).rounded())
                        Text("Exporting \(pct)%")
                            .font(KadrajTheme.textFont(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(KadrajTheme.label)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(KadrajTheme.capsuleDark)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(KadrajTheme.yellow.opacity(0.5), lineWidth: 0.6))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let video = viewModel.recordedVideo {
                    HStack(spacing: 6) {
                        Text("\(video.specLabel) · \(video.dynamicRangeLabel)")
                            .font(KadrajTheme.textFont(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(video.isHdr ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(KadrajTheme.capsuleDark)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(video.isHdr ? KadrajTheme.yellow.opacity(0.55) : KadrajTheme.hairline, lineWidth: 0.5))

                        if hasEdits {
                            let badge = viewModel.selectedVideoProfile == .original
                                ? "AUTO HDR"
                                : "\(viewModel.selectedVideoProfile.displayName.uppercased()) · \(Int((viewModel.videoFilterStrength * 100).rounded()))%"
                            Text(badge)
                                .font(KadrajTheme.textFont(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(KadrajTheme.label)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(KadrajTheme.capsuleDark)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(KadrajTheme.hairline, lineWidth: 0.5))
                        }
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)

            // Film Emulation Carousel + Intensity Slider
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(FilmProfile.allCases) { profile in
                            let thumb = viewModel.videoThumbnails.first(where: { $0.0 == profile })?.1
                            let isSelected = profile == viewModel.selectedVideoProfile
                            Button {
                                guard !viewModel.isSaving else { return }
                                viewModel.selectVideoProfile(profile)
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
                                            .overlay(
                                                Image(systemName: "film")
                                                    .foregroundColor(isSelected ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? KadrajTheme.yellow : KadrajTheme.hairline, lineWidth: isSelected ? 2 : 0.6)
                                            )
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

                if viewModel.selectedVideoProfile != .original {
                    IosSlimSliderView(
                        label: "Intensity",
                        valueText: "\(Int((viewModel.videoFilterStrength * 100).rounded()))%",
                        value: $viewModel.videoFilterStrength,
                        range: 0...1,
                        neutralValue: nil,
                        onNeutralCross: {}
                    )
                } else {
                    Text(viewModel.videoAutoHdr ? "Auto HDR tone-mapping active" : "Select a film look or enable Auto HDR")
                        .font(KadrajTheme.textFont(size: 11, weight: .medium))
                        .foregroundColor(viewModel.videoAutoHdr ? KadrajTheme.yellow : KadrajTheme.secondaryLabel)
                        .frame(height: 44)
                }
            }
            .frame(height: 158)
            .padding(.horizontal, 10)
        }
        .background(KadrajTheme.black.ignoresSafeArea())
        .task(id: "\(viewModel.selectedVideoProfile.rawValue)-\(Int((viewModel.videoFilterStrength * 50).rounded()))-\(viewModel.videoAutoHdr)") {
            await rebuildPlayerComposition()
        }
        .onDisappear {
            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
            }
            player.pause()
        }
    }

    private func rebuildPlayerComposition() async {
        guard let video = viewModel.recordedVideo else { return }
        let asset = AVURLAsset(url: video.url)
        _ = try? await asset.load(.tracks, .duration)

        let resumeTime = player.currentTime()
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = viewModel.filmEngine.makeVideoComposition(
            for: asset,
            profile: viewModel.selectedVideoProfile,
            strength: viewModel.videoFilterStrength,
            autoHdr: viewModel.videoAutoHdr
        )

        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        player.replaceCurrentItem(with: item)
        if resumeTime.isValid && resumeTime.seconds > 0.05 {
            await player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if isPlaying {
            player.play()
        }
    }
}

private struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
