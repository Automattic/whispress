import Foundation

enum WPLocalProjectKind: String, Codable, CaseIterable, Equatable {
    case theme
    case plugin
    case other

    var label: String {
        switch self {
        case .theme:
            return "Theme"
        case .plugin:
            return "Plugin"
        case .other:
            return "Project"
        }
    }
}

enum WPLocalWorkspaceWritePolicy: String, Codable, CaseIterable, Equatable {
    case readOnly = "read_only"
    case requireApproval = "require_approval"
    case allowEdits = "allow_edits"

    var label: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .requireApproval:
            return "Ask Before Edits"
        case .allowEdits:
            return "YOLO Edits"
        }
    }
}

enum WPLocalProjectHealthState: Equatable {
    case checking
    case ready
    case failed
}

struct WPLocalProjectHealthCheck: Equatable {
    var state: WPLocalProjectHealthState
    var message: String
    var checkedAt: Date?

    static let checking = WPLocalProjectHealthCheck(
        state: .checking,
        message: "Checking Claude Code...",
        checkedAt: nil
    )
}

struct WPLocalProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var rootPath: String
    var rootBookmarkData: Data?
    var kind: WPLocalProjectKind
    var writePolicy: WPLocalWorkspaceWritePolicy

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        rootBookmarkData: Data? = nil,
        kind: WPLocalProjectKind,
        writePolicy: WPLocalWorkspaceWritePolicy = .readOnly
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.rootBookmarkData = rootBookmarkData
        self.kind = kind
        self.writePolicy = writePolicy
    }

    var rootDisplayName: String {
        URL(fileURLWithPath: rootPath).lastPathComponent
    }

    func resolvedRootURL() -> URL? {
        if let rootBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: rootBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        guard !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rootPath)
    }
}

struct WPSiteLocalWorkspace: Codable, Identifiable, Equatable {
    let id: UUID
    let siteID: Int
    var name: String
    var isEnabled: Bool
    var projects: [WPLocalProject]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: Int,
        name: String,
        isEnabled: Bool = true,
        projects: [WPLocalProject] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.isEnabled = isEnabled
        self.projects = projects
        self.updatedAt = updatedAt
    }
}
