import AppKit
import AuthenticationServices
import Foundation

enum WPCOMClientError: LocalizedError {
    case missingOAuthCredentials
    case invalidAuthorizationCallback
    case authorizationCancelled
    case missingAuthorizationCode
    case missingRefreshToken
    case missingSelectedSite
    case requestFailed(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingOAuthCredentials:
            return "WordPress.com OAuth client secret is not configured."
        case .invalidAuthorizationCallback:
            return "WordPress.com returned an invalid authorization callback."
        case .authorizationCancelled:
            return "WordPress.com sign-in was cancelled."
        case .missingAuthorizationCode:
            return "WordPress.com did not return an authorization code."
        case .missingRefreshToken:
            return "WordPress.com session expired. Sign in again."
        case .missingSelectedSite:
            return "Choose a WordPress.com workspace before transcribing."
        case .requestFailed(let statusCode, let details):
            return "WordPress.com request failed with status \(statusCode): \(details)"
        case .invalidResponse(let details):
            return "Invalid WordPress.com response: \(details)"
        }
    }
}

struct WPCOMAuthState: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expirationDate: Date?

    var authorizationHeaderValue: String {
        "\(tokenType.isEmpty ? "Bearer" : tokenType) \(accessToken)"
    }

    var needsRefresh: Bool {
        guard let expirationDate else { return false }
        return expirationDate <= Date().addingTimeInterval(90)
    }
}

struct WPCOMSite: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let url: String?
    let slug: String?
    let icon: WPCOMSiteIcon?

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return slug ?? url ?? "\(id)"
    }

    var editorSitePath: String {
        slug ?? url?.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") ?? "\(id)"
    }

    var iconURL: URL? {
        guard let iconURLString = icon?.bestURLString else { return nil }
        return URL(string: iconURLString)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name
        case url = "URL"
        case slug
        case icon
    }

    init(id: Int, name: String, url: String?, slug: String?, icon: WPCOMSiteIcon? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.slug = slug
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else if let stringID = try? container.decode(String.self, forKey: .id), let intID = Int(stringID) {
            id = intID
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing site ID")
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        url = try? container.decode(String.self, forKey: .url)
        slug = try? container.decode(String.self, forKey: .slug)
        icon = try? container.decode(WPCOMSiteIcon.self, forKey: .icon)
    }
}

struct WPCOMSiteIcon: Codable, Equatable {
    let img: String?
    let ico: String?

    var bestURLString: String? {
        [img, ico]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct WPCOMUser: Codable, Equatable {
    let id: Int
    let displayName: String
    let username: String
    let email: String?
    let avatarURLString: String?
    let profileURLString: String?

    var avatarURL: URL? {
        guard let avatarURLString,
              !avatarURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: avatarURLString)
    }

    var displayLabel: String {
        if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        return email ?? "WordPress.com"
    }

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case displayName = "display_name"
        case username
        case email
        case avatarURLString = "avatar_URL"
        case profileURLString = "profile_URL"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else if let stringID = try? container.decode(String.self, forKey: .id), let intID = Int(stringID) {
            id = intID
        } else {
            id = 0
        }
        displayName = (try? container.decode(String.self, forKey: .displayName)) ?? ""
        username = (try? container.decode(String.self, forKey: .username)) ?? ""
        email = try? container.decode(String.self, forKey: .email)
        avatarURLString = try? container.decode(String.self, forKey: .avatarURLString)
        profileURLString = try? container.decode(String.self, forKey: .profileURLString)
    }
}

struct WPCOMGuideline: Codable, Equatable {
    let id: Int
    let slug: String
    let modified: String?
    let link: String?
}

struct WPCOMTranscribeResponse: Codable, Equatable {
    let rawTranscript: String
    let text: String
    let status: String
    let siteID: Int?
    let skillID: Int?
    let skillCreated: Bool
    let skillModified: String?
    let warnings: [String]
    let detectedIntent: String?
    let artifactID: Int?
    let agent: WPCOMTranscribeAgent?

    private enum CodingKeys: String, CodingKey {
        case rawTranscript = "raw_transcript"
        case text
        case status
        case siteID = "site_id"
        case skillID = "skill_id"
        case skillCreated = "skill_created"
        case skillModified = "skill_modified"
        case warnings
        case detectedIntent = "detected_intent"
        case artifactID = "artifact_id"
        case agent
    }
}

struct WPCOMTranscribeAgent: Codable, Equatable {
    let id: String
    let message: String
    let endpoint: String?
}

struct WPCOMAppContextPayload: Encodable {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String

    private enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleIdentifier = "bundle_identifier"
        case windowTitle = "window_title"
        case selectedText = "selected_text"
        case currentActivity = "current_activity"
    }
}

struct WPCOMAgentClientContextPayload: Encodable {
    let selectedSiteID: Int
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String
    let client: String
    let clientVersion: String
    let uploadedFiles: [WPCOMAgentUploadedFileContext]

    private enum CodingKeys: String, CodingKey {
        case selectedSiteID = "selectedSiteId"
        case appName
        case bundleIdentifier
        case windowTitle
        case selectedText
        case currentActivity
        case client
        case clientVersion
        case uploadedFiles
    }
}

struct WPCOMAgentResponse: Equatable {
    let text: String
    let state: String
    let sessionID: String?
}

struct WPCOMUploadedMedia: Decodable, Equatable {
    let id: Int
    let urlString: String
    let file: String?
    let mimeType: String?
    let title: String?

    var url: URL? {
        URL(string: urlString)
    }

    var resolvedMimeType: String {
        if let mimeType, !mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mimeType
        }
        return Self.mimeType(forFileName: file ?? url?.lastPathComponent)
    }

    var displayName: String? {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if let file, !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: file).lastPathComponent
        }
        return url?.lastPathComponent
    }

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case lowercaseID = "id"
        case urlString = "URL"
        case lowercaseURL = "url"
        case file
        case title
        case name
        case mimeType = "mime_type"
        case mimeTypeCamel = "mimeType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleInt(container, forKey: .id)
            ?? Self.decodeFlexibleInt(container, forKey: .lowercaseID)
            ?? 0
        urlString = (try? container.decode(String.self, forKey: .urlString))
            ?? (try? container.decode(String.self, forKey: .lowercaseURL))
            ?? ""
        file = try? container.decode(String.self, forKey: .file)
        title = (try? container.decode(String.self, forKey: .title))
            ?? (try? container.decode(String.self, forKey: .name))
        mimeType = (try? container.decode(String.self, forKey: .mimeType))
            ?? (try? container.decode(String.self, forKey: .mimeTypeCamel))
    }

    private static func decodeFlexibleInt<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    private static func mimeType(forFileName fileName: String?) -> String {
        guard let fileName else { return "image/jpeg" }
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "tif", "tiff": return "image/tiff"
        default: return "image/jpeg"
        }
    }
}

struct WPCOMAgentUploadedFileContext: Encodable, Equatable {
    let id: Int
    let url: String
    let title: String?
    let fileName: String?
    let fileType: String
    let mimeType: String
    let name: String?

    init(media: WPCOMUploadedMedia) {
        id = media.id
        url = media.urlString
        title = media.title ?? media.displayName
        fileName = media.file
        fileType = media.resolvedMimeType
        mimeType = media.resolvedMimeType
        name = media.displayName
    }
}

struct WPCOMAgentHistoryMessage: Decodable, Equatable {
    let messageID: Int?
    let content: String
    let role: String
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case content
        case role
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intMessageID = try? container.decode(Int.self, forKey: .messageID) {
            messageID = intMessageID
        } else if let stringMessageID = try? container.decode(String.self, forKey: .messageID) {
            messageID = Int(stringMessageID)
        } else {
            messageID = nil
        }
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        role = (try? container.decode(String.self, forKey: .role)) ?? ""
        createdAt = try? container.decode(String.self, forKey: .createdAt)
    }
}

struct WPCOMAgentConversationSummary: Decodable, Equatable {
    let chatID: Int
    let sessionID: String?
    let createdAt: String?
    let siteID: Int?
    let firstMessage: WPCOMAgentHistoryMessage?
    let lastMessage: WPCOMAgentHistoryMessage?

    private enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case sessionID = "session_id"
        case createdAt = "created_at"
        case siteID = "site_id"
        case blogID = "blog_id"
        case selectedSiteID = "selected_site_id"
        case selectedSiteIDCamel = "selectedSiteId"
        case firstMessage = "first_message"
        case lastMessage = "last_message"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intChatID = try? container.decode(Int.self, forKey: .chatID) {
            chatID = intChatID
        } else if let stringChatID = try? container.decode(String.self, forKey: .chatID),
                  let intChatID = Int(stringChatID) {
            chatID = intChatID
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .chatID,
                in: container,
                debugDescription: "Missing chat ID"
            )
        }
        sessionID = try? container.decode(String.self, forKey: .sessionID)
        createdAt = try? container.decode(String.self, forKey: .createdAt)
        siteID = Self.decodeFlexibleInt(container, forKey: .siteID)
            ?? Self.decodeFlexibleInt(container, forKey: .blogID)
            ?? Self.decodeFlexibleInt(container, forKey: .selectedSiteID)
            ?? Self.decodeFlexibleInt(container, forKey: .selectedSiteIDCamel)
        firstMessage = try? container.decode(WPCOMAgentHistoryMessage.self, forKey: .firstMessage)
        lastMessage = try? container.decode(WPCOMAgentHistoryMessage.self, forKey: .lastMessage)
    }

    private static func decodeFlexibleInt<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

struct WPCOMAgentChat: Decodable, Equatable {
    let chatID: Int
    let sessionID: String?
    let createdAt: String?
    let siteID: Int?
    let messages: [WPCOMAgentHistoryMessage]

    private enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case sessionID = "session_id"
        case createdAt = "created_at"
        case siteID = "site_id"
        case blogID = "blog_id"
        case selectedSiteID = "selected_site_id"
        case selectedSiteIDCamel = "selectedSiteId"
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intChatID = try? container.decode(Int.self, forKey: .chatID) {
            chatID = intChatID
        } else if let stringChatID = try? container.decode(String.self, forKey: .chatID),
                  let intChatID = Int(stringChatID) {
            chatID = intChatID
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .chatID,
                in: container,
                debugDescription: "Missing chat ID"
            )
        }
        sessionID = try? container.decode(String.self, forKey: .sessionID)
        createdAt = try? container.decode(String.self, forKey: .createdAt)
        siteID = Self.decodeFlexibleInt(container, forKey: .siteID)
            ?? Self.decodeFlexibleInt(container, forKey: .blogID)
            ?? Self.decodeFlexibleInt(container, forKey: .selectedSiteID)
            ?? Self.decodeFlexibleInt(container, forKey: .selectedSiteIDCamel)
        messages = (try? container.decode([WPCOMAgentHistoryMessage].self, forKey: .messages)) ?? []
    }

    private static func decodeFlexibleInt<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

final class WPCOMClient: NSObject {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let tokenType: String?
        let expiresIn: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }

    private struct SitesResponse: Decodable {
        let sites: [WPCOMSite]
    }

    private struct AgentRPCRequest: Encodable {
        let jsonrpc: String
        let id: String
        let method: String
        let params: AgentRPCParams
    }

    private struct AgentRPCParams: Encodable {
        let id: String
        let sessionID: String?
        let message: AgentA2AMessage

        private enum CodingKeys: String, CodingKey {
            case id
            case sessionID = "sessionId"
            case message
        }
    }

    private struct AgentA2AMessage: Encodable {
        let role: String
        let parts: [AgentRequestPart]
    }

    private struct AgentRequestPart: Encodable {
        let type: String
        let text: String?
        let data: AgentRequestPartData?
        let file: AgentRequestFile?
        let metadata: AgentRequestFileMetadata?

        static func text(_ text: String) -> AgentRequestPart {
            AgentRequestPart(type: "text", text: text, data: nil, file: nil, metadata: nil)
        }

        static func clientContext(_ context: WPCOMAgentClientContextPayload) -> AgentRequestPart {
            AgentRequestPart(type: "data", text: nil, data: AgentRequestPartData(clientContext: context), file: nil, metadata: nil)
        }

        static func file(_ media: WPCOMUploadedMedia) -> AgentRequestPart {
            let mimeType = media.resolvedMimeType
            return AgentRequestPart(
                type: "file",
                text: nil,
                data: nil,
                file: AgentRequestFile(
                    uri: media.urlString,
                    mimeType: mimeType,
                    name: media.displayName
                ),
                metadata: AgentRequestFileMetadata(
                    id: media.id,
                    url: media.urlString,
                    mimeType: mimeType,
                    name: media.displayName,
                    title: media.title ?? media.displayName,
                    fileName: media.file,
                    fileType: mimeType
                )
            )
        }
    }

    private struct AgentRequestPartData: Encodable {
        let clientContext: WPCOMAgentClientContextPayload
    }

    private struct AgentRequestFile: Encodable {
        let uri: String
        let mimeType: String
        let name: String?
    }

    private struct AgentRequestFileMetadata: Encodable {
        let id: Int
        let url: String
        let mimeType: String
        let name: String?
        let title: String?
        let fileName: String?
        let fileType: String
    }

    private struct AgentRPCResponse: Decodable {
        let result: AgentTaskResult?
        let error: AgentRPCError?
    }

    private struct AgentRPCError: Decodable {
        let code: Int?
        let message: String
    }

    private struct AgentTaskResult: Decodable {
        let status: AgentTaskStatus
        let sessionID: String?

        private enum CodingKeys: String, CodingKey {
            case status
            case sessionID = "sessionId"
        }
    }

    private struct AgentTaskStatus: Decodable {
        let state: String
        let message: AgentResponseMessage?
    }

    private struct AgentResponseMessage: Decodable {
        let parts: [AgentResponsePart]
    }

    private struct AgentResponsePart: Decodable {
        let type: String
        let text: String?
    }

    private struct MediaUploadResponse: Decodable {
        let media: [WPCOMUploadedMedia]
        let errors: [MediaUploadError]?
    }

    private struct MediaUploadError: Decodable {
        let error: String?
        let message: String?
    }

    private struct MultipartFilePart {
        let fieldName: String
        let fileURL: URL
        let contentType: String
    }

    private let apiBaseURL = URL(string: "https://public-api.wordpress.com")!
    private let oauthAuthorizeURL = URL(string: "https://public-api.wordpress.com/oauth2/authorize")!
    private let oauthTokenURL = URL(string: "https://public-api.wordpress.com/oauth2/token")!
    private let redirectURI = "whispress://oauth/callback"
    private let callbackScheme = "whispress"
    private let tokenStorageAccount = "wpcom_oauth_state"
    private let session = URLSession(configuration: .ephemeral)
    private var authSession: ASWebAuthenticationSession?

    private var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "WPCOMOAuthClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var clientSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "WPCOMOAuthClientSecret") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private(set) var authState: WPCOMAuthState? {
        didSet {
            persistAuthState()
        }
    }

    override init() {
        if let stored = AppSettingsStorage.loadSecure(account: tokenStorageAccount),
           let data = stored.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WPCOMAuthState.self, from: data) {
            authState = decoded
        }
        super.init()
    }

    var isSignedIn: Bool {
        authState?.refreshToken != nil || authState?.accessToken.isEmpty == false
    }

    func signIn() async throws -> WPCOMAuthState {
        let clientID = self.clientID
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw WPCOMClientError.missingOAuthCredentials
        }

        let state = Self.randomURLSafeString(byteCount: 24)
        var components = URLComponents(url: oauthAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "global"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizationURL = components.url else {
            throw WPCOMClientError.invalidAuthorizationCallback
        }

        let callbackURL = try await authorize(url: authorizationURL)
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw WPCOMClientError.invalidAuthorizationCallback
        }

        let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw WPCOMClientError.invalidAuthorizationCallback
        }

        if let error = callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value {
            throw WPCOMClientError.requestFailed(401, error)
        }

        guard let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WPCOMClientError.missingAuthorizationCode
        }

        let token = try await exchangeCode(code, clientID: clientID, clientSecret: clientSecret)
        authState = token
        return token
    }

    func signOut() {
        authSession?.cancel()
        authSession = nil
        authState = nil
        AppSettingsStorage.deleteSecure(account: tokenStorageAccount)
    }

    func fetchSites() async throws -> [WPCOMSite] {
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/me/sites")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "ID,name,URL,slug,icon")
        ]
        let data = try await authenticatedData(for: components.url!)
        let response = try JSONDecoder().decode(SitesResponse.self, from: data)
        return response.sites
    }

    func fetchCurrentUser() async throws -> WPCOMUser {
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/me")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "ID,display_name,username,email,avatar_URL,profile_URL")
        ]
        let data = try await authenticatedData(for: components.url!)
        return try JSONDecoder().decode(WPCOMUser.self, from: data)
    }

    func fetchAgentConversationSummaries(agentID: String = "dolly") async throws -> [WPCOMAgentConversationSummary] {
        let historyBotID = Self.historyBotID(for: agentID)
        var components = URLComponents(string: "https://public-api.wordpress.com/wpcom/v2/ai/chats/\(historyBotID)")!
        components.queryItems = [
            URLQueryItem(name: "truncation_method", value: "last_message")
        ]
        let data = try await authenticatedData(for: components.url!)
        return try JSONDecoder().decode([WPCOMAgentConversationSummary].self, from: data)
    }

    func fetchAgentChat(
        agentID: String = "dolly",
        chatID: Int,
        itemsPerPage: Int = 100
    ) async throws -> WPCOMAgentChat {
        let historyBotID = Self.historyBotID(for: agentID)
        var components = URLComponents(string: "https://public-api.wordpress.com/wpcom/v2/ai/chat/\(historyBotID)/\(chatID)")!
        components.queryItems = [
            URLQueryItem(name: "page_number", value: "1"),
            URLQueryItem(name: "items_per_page", value: "\(itemsPerPage)")
        ]
        let data = try await authenticatedData(for: components.url!)
        return try JSONDecoder().decode(WPCOMAgentChat.self, from: data)
    }

    func discoverTranscribeSkill(siteID: Int) async throws -> WPCOMGuideline? {
        var components = URLComponents(string: "https://public-api.wordpress.com/wp/v2/sites/\(siteID)/guidelines")!
        components.queryItems = [
            URLQueryItem(name: "slug", value: "transcribe"),
            URLQueryItem(name: "context", value: "edit")
        ]
        let data = try await authenticatedData(for: components.url!)
        let guidelines = try JSONDecoder().decode([WPCOMGuideline].self, from: data)
        return guidelines.first
    }

    func transcribe(
        audioFileURL: URL,
        siteID: Int,
        intent: String,
        selectedText: String?,
        appContext: WPCOMAppContextPayload,
        clientVersion: String,
        saveArtifact: Bool
    ) async throws -> WPCOMTranscribeResponse {
        let boundary = UUID().uuidString
        let url = URL(string: "https://public-api.wordpress.com/wpcom/v2/sites/\(siteID)/ai/transcription")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(try await authorizationHeaderValue(), forHTTPHeaderField: "Authorization")

        let contextData = try JSONEncoder().encode(appContext)
        let contextString = String(data: contextData, encoding: .utf8) ?? "{}"
        var fields: [String: String] = [
            "intent": intent,
            "app_context": contextString,
            "client": "whispress",
            "client_version": clientVersion,
            "save_artifact": saveArtifact ? "true" : "false"
        ]
        if let selectedText, !selectedText.isEmpty {
            fields["selected_text"] = selectedText
        }

        let body = try makeMultipartBody(
            fileURL: audioFileURL,
            fileFieldName: "audio_file",
            fields: fields,
            boundary: boundary
        )

        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(WPCOMTranscribeResponse.self, from: data)
    }

    func sendAgentMessage(
        siteID: Int,
        agentID: String,
        message: String,
        clientContext: WPCOMAgentClientContextPayload,
        sessionID: String?,
        uploadedMedia: [WPCOMUploadedMedia] = []
    ) async throws -> WPCOMAgentResponse {
        let normalizedAgentID = Self.normalizedAgentID(agentID)
        let url = URL(string: "https://public-api.wordpress.com/wpcom/v2/sites/\(siteID)/ai/agent/\(normalizedAgentID)")!
        let rpcID = UUID().uuidString
        let taskID = UUID().uuidString
        let parts = [AgentRequestPart.text(message)]
            + uploadedMedia.map(AgentRequestPart.file)
            + [AgentRequestPart.clientContext(clientContext)]
        let body = AgentRPCRequest(
            jsonrpc: "2.0",
            id: rpcID,
            method: "message/send",
            params: AgentRPCParams(
                id: taskID,
                sessionID: sessionID,
                message: AgentA2AMessage(
                    role: "user",
                    parts: parts
                )
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(try await authorizationHeaderValue(), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(AgentRPCResponse.self, from: data)
        if let error = decoded.error {
            throw WPCOMClientError.requestFailed(error.code ?? -32000, error.message)
        }
        guard let result = decoded.result else {
            throw WPCOMClientError.invalidResponse("Missing agent result")
        }
        let text = result.status.message?.parts.compactMap { part in
            part.type == "text" ? part.text : nil
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return WPCOMAgentResponse(
            text: text,
            state: result.status.state,
            sessionID: result.sessionID
        )
    }

    func uploadMedia(siteID: Int, fileURLs: [URL]) async throws -> [WPCOMUploadedMedia] {
        guard !fileURLs.isEmpty else { return [] }

        let url = URL(string: "https://public-api.wordpress.com/rest/v1.1/sites/\(siteID)/media/new")!
        let boundary = "WhisPress-\(UUID().uuidString)"
        let files = fileURLs.map {
            MultipartFilePart(
                fieldName: "media[]",
                fileURL: $0,
                contentType: Self.mediaContentType(for: $0)
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(try await authorizationHeaderValue(), forHTTPHeaderField: "Authorization")

        let body = try makeMultipartBody(fields: [:], files: files, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(MediaUploadResponse.self, from: data)
        if let errorMessage = decoded.errors?.compactMap(\.message).first {
            throw WPCOMClientError.invalidResponse(errorMessage)
        }
        guard !decoded.media.isEmpty else {
            throw WPCOMClientError.invalidResponse("No media was uploaded.")
        }
        let uploadedMedia = decoded.media.filter {
            $0.id > 0 && !$0.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard uploadedMedia.count == decoded.media.count else {
            throw WPCOMClientError.invalidResponse("Uploaded media response was missing attachment metadata.")
        }
        return uploadedMedia
    }

    func editURL(for guideline: WPCOMGuideline, site: WPCOMSite) -> URL {
        if let link = guideline.link, let url = URL(string: link) {
            return url
        }
        return URL(string: "https://wordpress.com/post/\(site.editorSitePath)/\(guideline.id)")!
    }

    private func authorize(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: WPCOMClientError.authorizationCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WPCOMClientError.invalidAuthorizationCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: WPCOMClientError.authorizationCancelled)
            }
        }
    }

    private func exchangeCode(_ code: String, clientID: String, clientSecret: String) async throws -> WPCOMAuthState {
        let fields = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI
        ]
        return try await requestToken(fields: fields, existingRefreshToken: nil)
    }

    private func refreshToken() async throws -> WPCOMAuthState {
        guard let refreshToken = authState?.refreshToken else {
            throw WPCOMClientError.missingRefreshToken
        }
        let clientID = self.clientID
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw WPCOMClientError.missingOAuthCredentials
        }
        let fields = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken
        ]
        let token = try await requestToken(fields: fields, existingRefreshToken: refreshToken)
        authState = token
        return token
    }

    private func requestToken(fields: [String: String], existingRefreshToken: String?) async throws -> WPCOMAuthState {
        var request = URLRequest(url: oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(fields)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expirationDate = tokenResponse.expiresIn.map { Date().addingTimeInterval($0) }
        return WPCOMAuthState(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? existingRefreshToken,
            tokenType: tokenResponse.tokenType ?? "Bearer",
            expirationDate: expirationDate
        )
    }

    private func authenticatedData(for url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(try await authorizationHeaderValue(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func authorizationHeaderValue() async throws -> String {
        guard var state = authState else {
            throw WPCOMClientError.authorizationCancelled
        }
        if state.needsRefresh {
            state = try await refreshToken()
        }
        return state.authorizationHeaderValue
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WPCOMClientError.invalidResponse("No HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WPCOMClientError.requestFailed(httpResponse.statusCode, body)
        }
    }

    private func persistAuthState() {
        guard let authState,
              let data = try? JSONEncoder().encode(authState),
              let value = String(data: data, encoding: .utf8) else {
            AppSettingsStorage.deleteSecure(account: tokenStorageAccount)
            return
        }
        AppSettingsStorage.saveSecure(value, account: tokenStorageAccount)
    }

    private func makeMultipartBody(
        fileURL: URL,
        fileFieldName: String,
        fields: [String: String],
        boundary: String
    ) throws -> Data {
        try makeMultipartBody(
            fields: fields,
            files: [
                MultipartFilePart(
                    fieldName: fileFieldName,
                    fileURL: fileURL,
                    contentType: Self.audioContentType(for: fileURL)
                )
            ],
            boundary: boundary
        )
    }

    private func makeMultipartBody(
        fields: [String: String],
        files: [MultipartFilePart],
        boundary: String
    ) throws -> Data {
        var body = Data()

        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        for file in files {
            let fileData = try Data(contentsOf: file.fileURL)
            let fileName = Self.multipartEscaped(file.fileURL.lastPathComponent)
            let fieldName = Self.multipartEscaped(file.fieldName)
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
            append("Content-Type: \(file.contentType)\r\n\r\n")
            body.append(fileData)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")

        return body
    }

    private static func audioContentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        default: return "audio/mp4"
        }
    }

    private static func mediaContentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }

    private static func multipartEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func formURLEncoded(_ fields: [String: String]) -> Data {
        let encoded = fields
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static func normalizedAgentID(_ agentID: String) -> String {
        let trimmedAgentID = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAgentID.isEmpty ? "dolly" : trimmedAgentID
    }

    private static func historyBotID(for agentID: String) -> String {
        let normalizedAgentID = normalizedAgentID(agentID)
        if normalizedAgentID.hasPrefix("wpcom-agent-") {
            return normalizedAgentID
        }
        return "wpcom-agent-\(normalizedAgentID.replacingOccurrences(of: "-", with: "_"))"
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension WPCOMClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
