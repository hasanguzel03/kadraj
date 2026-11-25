import Foundation
import AVFoundation

enum AspectRatioOption: String, CaseIterable, Codable, Identifiable {
    case ratio4_3 = "4:3"
    case ratio16_9 = "16:9"
    case ratio1_1 = "1:1"

    var id: String { rawValue }

    var previewRatio: CGFloat {
        switch self {
        case .ratio4_3: return 3.0 / 4.0
        case .ratio16_9: return 9.0 / 16.0
        case .ratio1_1: return 1.0
        }
    }
}

enum VideoResolutionOption: String, CaseIterable, Codable, Identifiable {
    case fhd1080p = "1080p"
    case uhd4K = "4K"

    var id: String { rawValue }

    var targetWidth: Int32 {
        switch self {
        case .fhd1080p: return 1920
        case .uhd4K: return 3840
        }
    }
}

enum VideoFpsOption: Int, CaseIterable, Codable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue)fps" }
}

enum HdrModeOption: String, CaseIterable, Codable, Identifiable {
    case auto = "Auto"
    case on = "On"
    case off = "Off"

    var id: String { rawValue }
}

enum CaptureQualityOption: String, CaseIterable, Codable, Identifiable {
    case highEfficiency = "High Efficiency"
    case maxQuality = "Max Quality"

    var id: String { rawValue }

    var jpegQuality: CGFloat {
        switch self {
        case .highEfficiency: return 0.95
        case .maxQuality: return 0.98
        }
    }

    var maxPhotoDimension: CGFloat {
        switch self {
        case .highEfficiency: return 2560
        case .maxQuality: return 4096
        }
    }
}

struct CameraSettings: Codable, Equatable {
    var aspectRatio: AspectRatioOption = .ratio16_9
    var videoResolution: VideoResolutionOption = .fhd1080p
    var videoFps: VideoFpsOption = .fps30
    var hdrMode: HdrModeOption = .auto
    var enableThirdsGrid: Bool = true
    var enableGoldenRatioGrid: Bool = false
    var enableHorizonLevel: Bool = true
    var captureQuality: CaptureQualityOption = .maxQuality
    var autoEnhancePostHdr: Bool = true
    var hapticsEnabled: Bool = true
    var shutterSoundEnabled: Bool = true
}

@MainActor
final class CameraSettingsStore: ObservableObject {
    @Published var settings: CameraSettings {
        didSet {
            save(settings)
        }
    }

    private let key = "kadraj_pro_settings_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(CameraSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = CameraSettings()
        }
    }

    private func save(_ value: CameraSettings) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
