import Foundation

struct AvailableAppUpdate: Equatable {
    let version: String
    let releaseURL: URL
}

enum GitHubReleaseUpdateChecker {
    static let releasesPageURL = URL(string: "https://github.com/Automattic/workspace/releases")!

    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/Automattic/workspace/releases?per_page=20")!

    static func availableUpdate(currentVersion: String) async throws -> AvailableAppUpdate? {
        guard let currentComponents = VersionComponents(currentVersion) else {
            return nil
        }

        var request = URLRequest(url: releasesAPIURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WP Workspace", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases
            .compactMap { release -> (components: VersionComponents, url: URL)? in
                guard !release.draft,
                      !release.prerelease,
                      let releaseURL = URL(string: release.htmlURL),
                      let components = VersionComponents(release.tagName)
                        ?? release.name.flatMap(VersionComponents.init),
                      components > currentComponents else {
                    return nil
                }
                return (components, releaseURL)
            }
            .max { $0.components < $1.components }
            .map { AvailableAppUpdate(version: $0.components.displayString, releaseURL: $0.url) }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

private struct VersionComponents: Comparable {
    let numbers: [Int]

    var displayString: String {
        numbers.map(String.init).joined(separator: ".")
    }

    init?(_ value: String) {
        var token = ""
        var hasStartedVersion = false

        for character in value {
            if character.isNumber {
                hasStartedVersion = true
                token.append(character)
            } else if hasStartedVersion && character == "." {
                token.append(character)
            } else if hasStartedVersion {
                break
            }
        }

        let numbers = token
            .split(separator: ".")
            .compactMap { Int($0) }
        guard !numbers.isEmpty else { return nil }
        self.numbers = numbers
    }

    static func < (lhs: VersionComponents, rhs: VersionComponents) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let lhsValue = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let rhsValue = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if lhsValue != rhsValue {
                return lhsValue < rhsValue
            }
        }
        return false
    }
}
