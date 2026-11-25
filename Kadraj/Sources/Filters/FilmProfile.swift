import Foundation

struct FilmRecipe: Equatable {
    var contrastCurve: Float = 0
    var blackLift: Float = 0
    var whiteCeiling: Float = 1
    var exposureShift: Float = 0
    var saturation: Float = 1
    var isMonochrome: Bool = false
    var shadowRed: Float = 0
    var shadowGreen: Float = 0
    var shadowBlue: Float = 0
    var highlightRed: Float = 0
    var highlightGreen: Float = 0
    var highlightBlue: Float = 0
    var grainAmount: Float = 0
    var vignetteStrength: Float = 0
}

enum FilmProfile: String, CaseIterable, Identifiable {
    case original = "Original"
    case tealOrange = "Teal & Orange"
    case kodakGold = "Kodak Gold"
    case classicChrome = "Classic Chrome"
    case moodyMatte = "Moody Matte"
    case noirBW = "Noir B&W"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var recipe: FilmRecipe {
        switch self {
        case .original:
            return FilmRecipe()
        case .tealOrange:
            return FilmRecipe(
                contrastCurve: 0.22,
                blackLift: 0.02,
                whiteCeiling: 0.97,
                exposureShift: 2,
                saturation: 1.12,
                shadowRed: -18,
                shadowGreen: 7,
                shadowBlue: 22,
                highlightRed: 22,
                highlightGreen: 9,
                highlightBlue: -18,
                grainAmount: 0.025,
                vignetteStrength: 0.16
            )
        case .kodakGold:
            return FilmRecipe(
                contrastCurve: 0.16,
                blackLift: 0.065,
                whiteCeiling: 0.96,
                exposureShift: 5,
                saturation: 1.08,
                shadowRed: 11,
                shadowGreen: 4,
                shadowBlue: -2,
                highlightRed: 24,
                highlightGreen: 15,
                highlightBlue: -20,
                grainAmount: 0.040,
                vignetteStrength: 0.18
            )
        case .classicChrome:
            return FilmRecipe(
                contrastCurve: 0.30,
                blackLift: 0.015,
                whiteCeiling: 0.95,
                exposureShift: -2,
                saturation: 0.78,
                shadowRed: -9,
                shadowGreen: 2,
                shadowBlue: 10,
                highlightRed: 6,
                highlightGreen: 4,
                highlightBlue: -5,
                grainAmount: 0.028,
                vignetteStrength: 0.14
            )
        case .moodyMatte:
            return FilmRecipe(
                contrastCurve: 0.22,
                blackLift: 0.085,
                whiteCeiling: 0.87,
                exposureShift: -10,
                saturation: 0.72,
                shadowRed: -6,
                shadowGreen: 5,
                shadowBlue: 7,
                highlightRed: 9,
                highlightGreen: 5,
                highlightBlue: -9,
                grainAmount: 0.045,
                vignetteStrength: 0.26
            )
        case .noirBW:
            return FilmRecipe(
                contrastCurve: 0.38,
                blackLift: 0.022,
                whiteCeiling: 0.97,
                exposureShift: -4,
                saturation: 0,
                isMonochrome: true,
                grainAmount: 0.055,
                vignetteStrength: 0.28
            )
        }
    }
}

struct ImageAdjustments: Equatable {
    var filterStrength: Double = 1.0
    var autoHdrEnabled: Bool = false
    var brightness: Double = 0.0      // -80 ... +80
    var contrast: Double = 1.0        // 0.5 ... 1.8
    var saturation: Double = 1.0      // 0.0 ... 2.0
    var warmth: Double = 0.0          // -40 ... +40
    var vignette: Double = 0.0        // 0.0 ... 0.85

    var hasManualEdits: Bool {
        autoHdrEnabled ||
        abs(brightness) > 0.5 ||
        abs(contrast - 1.0) > 0.01 ||
        abs(saturation - 1.0) > 0.01 ||
        abs(warmth) > 0.5 ||
        vignette > 0.01
    }
}
