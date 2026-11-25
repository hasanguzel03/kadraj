import SwiftUI

enum KadrajTheme {
    static let black = Color(red: 0, green: 0, blue: 0)
    static let elevated = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255) // #1C1C1E
    static let capsuleDark = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.65)
    static let secondarySurface = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let yellow = Color(red: 1.0, green: 214 / 255, blue: 10 / 255) // #FFD60A
    static let yellowDim = yellow.opacity(0.20)
    static let red = Color(red: 1.0, green: 69 / 255, blue: 58 / 255)
    static let hairline = Color.white.opacity(0.18)
    static let label = Color.white
    static let secondaryLabel = Color(red: 152 / 255, green: 152 / 255, blue: 159 / 255)
    static let tertiaryLabel = Color(red: 99 / 255, green: 99 / 255, blue: 102 / 255)
    static let gridLine = Color.white.opacity(0.25)
    static let gridShadow = Color.black.opacity(0.16)

    static func displayFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let postscript: String
        switch weight {
        case .bold, .heavy:
            postscript = "InterDisplay-Bold"
        case .medium, .regular:
            postscript = "InterDisplay-Medium"
        default:
            postscript = "InterDisplay-SemiBold"
        }
        return Font.custom(postscript, size: size)
    }

    static func textFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let postscript: String
        switch weight {
        case .bold, .heavy:
            postscript = "Inter-Bold"
        case .semibold:
            postscript = "Inter-SemiBold"
        case .regular:
            postscript = "Inter-Regular"
        default:
            postscript = "Inter-Medium"
        }
        return Font.custom(postscript, size: size)
    }
}
