import Foundation

enum WordPressAgentPreviewViewMode: Equatable {
    case preview
    case edit
}

struct WordPressAgentPreviewPostURLs: Equatable {
    let previewURL: URL
    let editURL: URL

    func url(for mode: WordPressAgentPreviewViewMode) -> URL {
        switch mode {
        case .preview:
            return previewURL
        case .edit:
            return editURL
        }
    }
}

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

        return panelURL(for: url)
    }

    static func panelURL(forPossiblyBare url: URL) -> URL? {
        if let panelURL = panelURL(for: url) {
            return panelURL
        }

        guard url.scheme == nil else { return nil }
        return normalizedURL(from: url.absoluteString)
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

    static func panelURL(for url: URL) -> URL? {
        guard isPreviewable(url) else { return nil }
        if postID(fromAdminPostURL: url) != nil {
            return url
        }
        return rewrittenWordPressPostQueryURL(for: url) ?? url
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

        // WordPress.com preview frames are usually served from the site's
        // unmapped URL, even when the agent gave us a mapped-domain link. Apply
        // that host rewrite before appending the frame nonce so simple
        // WordPress.com and Jetpack/Atomic previews both enter the authenticated
        // preview shell instead of the public post route.
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

    static func previewPostURLs(for url: URL) -> WordPressAgentPreviewPostURLs? {
        guard isPreviewable(url) else { return nil }

        if let postID = postID(fromAdminPostURL: url),
           let previewURL = rewrittenWordPressAdminPostURL(for: url),
           let editURL = adminPostEditURL(for: url, postID: postID) {
            return WordPressAgentPreviewPostURLs(previewURL: previewURL, editURL: editURL)
        }

        if let postID = postID(fromWordPressPostQueryURL: url),
           let editURL = adminPostEditURL(for: url, postID: postID) {
            return WordPressAgentPreviewPostURLs(
                previewURL: rewrittenWordPressPostQueryURL(for: url) ?? url,
                editURL: editURL
            )
        }

        return nil
    }

    static func viewMode(for url: URL) -> WordPressAgentPreviewViewMode? {
        if postID(fromAdminPostURL: url) != nil {
            return .edit
        }
        if postID(fromWordPressPostQueryURL: url) != nil {
            return .preview
        }
        return nil
    }

    private static func rewrittenWordPressAdminPostURL(for url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let postID = postID(fromAdminPostComponents: components) else {
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
        guard postID(fromWordPressPostQueryItems: queryItems) != nil,
              !queryItems.contains(where: { $0.name == "preview" }) else {
            return nil
        }

        components.queryItems = queryItems + [URLQueryItem(name: "preview", value: "true")]
        return components.url
    }

    private static func postID(fromAdminPostURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return postID(fromAdminPostComponents: components)
    }

    private static func postID(fromAdminPostComponents components: URLComponents) -> String? {
        guard components.path.lowercased() == "/wp-admin/post.php" else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "post" })?.value.flatMap(normalizedPostID)
    }

    private static func postID(fromWordPressPostQueryURL url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return postID(fromWordPressPostQueryItems: components.queryItems ?? [])
    }

    private static func postID(fromWordPressPostQueryItems queryItems: [URLQueryItem]) -> String? {
        queryItems
            .first { ["p", "page_id", "attachment_id"].contains($0.name) }?
            .value
            .flatMap(normalizedPostID)
    }

    private static func normalizedPostID(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue.allSatisfy(\.isNumber) else {
            return nil
        }
        return trimmedValue
    }

    private static func adminPostEditURL(for url: URL, postID: String) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var editComponents = URLComponents()
        editComponents.scheme = components.scheme
        editComponents.host = components.host
        editComponents.port = components.port
        editComponents.path = "/wp-admin/post.php"
        editComponents.queryItems = [
            URLQueryItem(name: "post", value: postID),
            URLQueryItem(name: "action", value: "edit")
        ]
        return editComponents.url
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
