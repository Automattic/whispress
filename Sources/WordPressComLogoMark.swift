import SwiftUI

struct WordPressComLogoMark: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "WPCOM-Blueberry-Pill-Logo", withExtension: "svg") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "w.circle.fill")
                    .resizable()
                    .foregroundStyle(.blue)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("WordPress.com")
    }
}
