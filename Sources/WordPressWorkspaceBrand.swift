import SwiftUI
import CoreText

enum WordPressWorkspaceBrand {
    static let blue = Color(red: 0.220, green: 0.345, blue: 0.914)
    static let blueDark = Color(red: 0.071, green: 0.137, blue: 0.667)
    static let ink = Color.primary

    static func displayFont(size: CGFloat) -> Font {
        semiboldFont(size: size)
    }

    static func bodyFont(size: CGFloat) -> Font {
        .custom("Inter-Regular", size: size)
    }

    static func mediumFont(size: CGFloat) -> Font {
        .custom("Inter-Medium", size: size)
    }

    static func semiboldFont(size: CGFloat) -> Font {
        .custom("Inter-SemiBold", size: size)
    }

    static func boldFont(size: CGFloat) -> Font {
        .custom("Inter-Bold", size: size)
    }

    static func registerFonts() {
        for fontName in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts") else {
                continue
            }

            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            error?.release()
        }
    }
}

struct WordPressWorkspaceWelcomeMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            WordPressWorkspaceBrand.blue,
                            WordPressWorkspaceBrand.blueDark
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(WordPressWorkspacePlusPattern().opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: WordPressWorkspaceBrand.blue.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)

                    WordPressComLogoMark()
                        .padding(14)
                }
                .frame(width: 82, height: 82)

                HStack(spacing: 8) {
                    WelcomeMarkCard(width: 82, height: 54)
                    WelcomeMarkCard(width: 108, height: 70, opacity: 0.94)
                    WelcomeMarkCard(width: 72, height: 46)
                }
                .offset(y: 2)
            }
        }
        .frame(width: 232, height: 232)
        .accessibilityHidden(true)
    }
}

private struct WordPressWorkspacePlusPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            for x in stride(from: CGFloat(14), through: size.width, by: spacing) {
                for y in stride(from: CGFloat(14), through: size.height, by: spacing) {
                    var path = Path()
                    path.move(to: CGPoint(x: x - 2.5, y: y))
                    path.addLine(to: CGPoint(x: x + 2.5, y: y))
                    path.move(to: CGPoint(x: x, y: y - 2.5))
                    path.addLine(to: CGPoint(x: x, y: y + 2.5))
                    context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
    }
}

private struct WelcomeMarkCard: View {
    let width: CGFloat
    let height: CGFloat
    var opacity: Double = 0.86

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(WordPressWorkspaceBrand.blue.opacity(0.22))
                        .frame(width: width * 0.46, height: 5)
                    Capsule()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: width * 0.62, height: 4)
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: width * 0.5, height: 4)
                }
                .padding(10)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 12, y: 6)
    }
}
