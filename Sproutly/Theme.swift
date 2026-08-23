import SwiftUI

enum GardenFontWeight {
    case medium
    case bold

    var postScriptName: String {
        switch self {
        case .medium:
            "ZQKNNY-Medium"
        case .bold:
            "ZQKNNY-Bold"
        }
    }
}

enum GardenFont {
    static let mediumName = GardenFontWeight.medium.postScriptName
    static let boldName = GardenFontWeight.bold.postScriptName

    static func medium(_ size: CGFloat) -> Font {
        .custom(mediumName, fixedSize: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom(boldName, fixedSize: size)
    }

    static func font(size: CGFloat, weight: GardenFontWeight = .medium) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}

extension View {
    func gardenFont(size: CGFloat, weight: GardenFontWeight = .medium) -> some View {
        font(GardenFont.font(size: size, weight: weight))
    }
}

enum GardenTheme {
    static let mint = Color(red: 0.13, green: 0.79, blue: 0.78)
    static let deepMint = Color(red: 0.02, green: 0.64, blue: 0.65)
    static let sky = Color(red: 0.85, green: 1.0, blue: 0.99)
    static let homeGradientTop = Color(
        red: 195 / 255,
        green: 1,
        blue: 249 / 255
    )
    static let ink = Color(red: 0.12, green: 0.28, blue: 0.29)
    static let cream = Color(red: 1.0, green: 0.98, blue: 0.91)
}

/// 所有一级首页统一使用：linear-gradient(180deg, #C3FFF9 0%, #FFFFFF 100%)。
struct SproutlyHomeGradient: View {
    var body: some View {
        LinearGradient(
            colors: [GardenTheme.homeGradientTop, .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// 从 402 × 746 的 Figma 首页背景中取出一段，保证局部遮盖与整页渐变连续。
struct SproutlyHomeGradientSlice: View {
    let sourceY: CGFloat
    let sourceHeight: CGFloat
    let scale: CGFloat

    var body: some View {
        SproutlyHomeGradient()
            .frame(width: 402 * scale, height: 746 * scale)
            .offset(y: (373 - sourceY - sourceHeight / 2) * scale)
            .frame(width: 402 * scale, height: sourceHeight * scale)
            .clipped()
    }
}

struct SoftBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white, GardenTheme.sky, Color(red: 0.93, green: 1, blue: 0.97)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.cyan.opacity(0.09)).frame(width: 280).blur(radius: 4).offset(x: 150, y: -270)
            Circle().fill(Color.yellow.opacity(0.10)).frame(width: 220).blur(radius: 6).offset(x: -170, y: 280)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.95), lineWidth: 1))
            .shadow(color: GardenTheme.deepMint.opacity(0.10), radius: 16, y: 8)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

struct MascotView: View {
    var size: CGFloat = 72
    var expression = "•ᴗ•"

    var body: some View {
        ZStack {
            Ellipse().fill(Color.orange.opacity(0.2)).frame(width: size * 1.08, height: size * 0.24).offset(y: size * 0.48)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.87, blue: 0.35), .orange], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(Text(expression).gardenFont(size: size * 0.22, weight: .bold).foregroundStyle(.brown))
            Capsule().fill(Color.green).frame(width: size * 0.26, height: size * 0.12).rotationEffect(.degrees(-28)).offset(x: -size * 0.11, y: -size * 0.49)
        }
        .frame(width: size * 1.2, height: size * 1.25)
    }
}
