import Foundation

enum WordPressAgentPreviewURLResolver {
    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if hasExplicitScheme(trimmed) {
            candidate = trimmed
        } else if trimmed.hasPrefix("//") {
            candidate = "https:\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }
        guard let url = URLComponents(string: candidate)?.url else {
            return nil
        }

        return previewURL(for: url)
    }

    static func previewURL(forPossiblyBare url: URL) -> URL? {
        if let previewURL = previewURL(for: url) {
            return previewURL
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
    }

    static func defaultOpenURL(forPossiblyBare url: URL) -> URL? {
        if isPreviewable(url) {
            return url
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
    }

    static func previewURL(for url: URL) -> URL? {
        guard isPreviewable(url) else { return nil }
        return rewrittenWordPressAdminPostURL(for: url) ?? url
    }

    static func isPreviewable(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host?.isEmpty == false else {
            return false
        }

        return true
    }

    private static func rewrittenWordPressAdminPostURL(for url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.lowercased() == "/wp-admin/post.php",
              let postID = components.queryItems?.first(where: { $0.name == "post" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !postID.isEmpty,
              postID.allSatisfy(\.isNumber) else {
            return nil
        }

        var rewrittenComponents = URLComponents()
        rewrittenComponents.scheme = components.scheme
        rewrittenComponents.host = components.host
        rewrittenComponents.port = components.port
        rewrittenComponents.path = "/"
        rewrittenComponents.queryItems = [
            URLQueryItem(name: "p", value: postID)
        ]

        return rewrittenComponents.url
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
            options: .regularExpression
        ) != nil
    }
}
