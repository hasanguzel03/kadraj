import SwiftUI

@main
struct KadrajApp: App {
    @StateObject private var viewModel = KadrajViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch viewModel.route {
                case .camera:
                    CameraScreenView(
                        viewModel: viewModel,
                        cameraService: viewModel.cameraService,
                        angleAnalyzer: viewModel.angleAnalyzer,
                        settingsStore: viewModel.settingsStore
                    )
                case .photoEditor:
                    PhotoEditorView(viewModel: viewModel)
                case .videoEditor:
                    VideoEditorView(viewModel: viewModel)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await viewModel.onAppear()
            }
        }
    }
}
