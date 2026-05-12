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
        return rewrittenWordPressAdminPostURL(for: url)
            ?? rewrittenWordPressPostQueryURL(for: url)
            ?? url
    }

    static func previewURL(for url: URL, sitePreviewOptions: WPCOMSitePreviewOptions?) -> URL? {
        guard var previewURL = previewURL(for: url),
              hasPreviewQuery(previewURL),
              let sitePreviewOptions else {
            return previewURL(for: url)
        }

        previewURL = unmappedURL(for: previewURL, unmappedURLString: sitePreviewOptions.unmappedURL) ?? previewURL
        previewURL = addingFrameNonceIfNeeded(to: previewURL, frameNonce: sitePreviewOptions.frameNonce) ?? previewURL
        return previewURL
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
            URLQueryItem(name: "p", value: postID),
            URLQueryItem(name: "preview", value: "true")
        ]

        return rewrittenComponents.url
    }

    private static func rewrittenWordPressPostQueryURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard queryItems.contains(where: { isWordPressPostIDQueryItem($0) }),
              !queryItems.contains(where: { $0.name == "preview" }) else {
            return nil
        }

        components.queryItems = queryItems + [URLQueryItem(name: "preview", value: "true")]
        return components.url
    }

    private static func isWordPressPostIDQueryItem(_ item: URLQueryItem) -> Bool {
        guard ["p", "page_id", "attachment_id"].contains(item.name),
              let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.allSatisfy(\.isNumber) else {
            return false
        }

        return true
    }

    private static func hasPreviewQuery(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        return components.queryItems?.contains(where: { $0.name == "preview" }) == true
    }

    private static func unmappedURL(for url: URL, unmappedURLString: String?) -> URL? {
        guard let unmappedURLString,
              let unmappedURL = URL(string: unmappedURLString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = unmappedURL.scheme
        components.host = unmappedURL.host
        components.port = unmappedURL.port
        return components.url
    }

    private static func addingFrameNonceIfNeeded(to url: URL, frameNonce: String?) -> URL? {
        guard let frameNonce,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "frame-nonce" }) else {
            return url
        }

        components.queryItems = queryItems + [URLQueryItem(name: "frame-nonce", value: frameNonce)]
        return components.url
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
            options: .regularExpression
        ) != nil
    }
}
