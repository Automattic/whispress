import Foundation
import Combine
import AppKit
import AVFoundation
import ServiceManagement
import ApplicationServices
import os.log
import UserNotifications
private let recordingLog = OSLog(subsystem: "com.automattic.wpworkspace", category: "Recording")
private let unknownWordPressAgentSiteID = -1

struct WPCOMAppSiteOverride: Codable, Identifiable, Equatable {
    let bundleIdentifier: String
    var appName: String
    var siteID: Int

    var id: String { bundleIdentifier }
}

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let languageCode: String

    var displayName: String {
        guard !languageCode.isEmpty else { return name }
        let languageName = Locale.current.localizedString(forIdentifier: languageCode) ?? languageCode
        return "\(name) (\(languageName))"
    }
}

private extension Dictionary where Key == String, Value == WPCOMAgentJSONValue {
    func stringValue(forPossibleKeys keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        var lowercasedValues: [String: WPCOMAgentJSONValue] = [:]
        for (key, value) in self where lowercasedValues[key.lowercased()] == nil {
            lowercasedValues[key.lowercased()] = value
        }
        for key in keys {
            if let value = lowercasedValues[key.lowercased()]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        return nil
    }
}

enum WordPressAgentSpeechProvider: String, CaseIterable, Hashable, Identifiable {
    case system
    case elevenLabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "macOS"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

struct WordPressAgentConversationKey: Codable, Hashable, Identifiable {
    let siteID: Int
    let agentID: String

    var id: String {
        "\(siteID)|\(agentID)"
    }

    init(siteID: Int, agentID: String) {
        self.siteID = siteID
        self.agentID = agentID
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let siteID = Int(parts[0]) else { return nil }
        self.siteID = siteID
        self.agentID = parts[1]
    }
}

enum WordPressAgentMessageRole: String, Codable, Equatable {
    case user
    case agent
    case system
}

struct WordPressAgentAttachment: Identifiable, Equatable, Codable {
    let id: UUID
    let fileURL: URL
    let displayName: String

    init(id: UUID = UUID(), fileURL: URL) {
        self.id = id
        self.fileURL = fileURL
        displayName = fileURL.lastPathComponent
    }
}

struct WordPressAgentPreview: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let currentURL: URL
    let title: String?
    let pageTitle: String?
    let siteID: Int?
    let isLoading: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        currentURL: URL? = nil,
        title: String? = nil,
        pageTitle: String? = nil,
        siteID: Int? = nil,
        isLoading: Bool = false
    ) {
        self.id = id
        self.url = url
        self.currentURL = currentURL ?? url
        self.siteID = siteID
        self.isLoading = isLoading
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        let trimmedPageTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageTitle = trimmedPageTitle?.isEmpty == false ? trimmedPageTitle : nil
    }

    var displayTitle: String {
        pageTitle ?? title ?? currentURL.host ?? currentURL.absoluteString
    }

    func updatingCurrentPage(url currentURL: URL?, title pageTitle: String?, isLoading: Bool) -> WordPressAgentPreview {
        let resolvedCurrentURL = currentURL ?? self.currentURL
        let trimmedPageTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPageTitle: String?
        if let trimmedPageTitle, !trimmedPageTitle.isEmpty {
            resolvedPageTitle = trimmedPageTitle
        } else if resolvedCurrentURL == self.currentURL {
            resolvedPageTitle = self.pageTitle
        } else {
            resolvedPageTitle = nil
        }

        return WordPressAgentPreview(
            id: id,
            url: url,
            currentURL: resolvedCurrentURL,
            title: title,
            pageTitle: resolvedPageTitle,
            siteID: siteID,
            isLoading: isLoading
        )
    }
}

struct WordPressAgentMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: WordPressAgentMessageRole
    let text: String
    let date: Date
    let state: String?
    let attachments: [WordPressAgentAttachment]

    init(
        id: UUID = UUID(),
        role: WordPressAgentMessageRole,
        text: String,
        date: Date = Date(),
        state: String? = nil,
        attachments: [WordPressAgentAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.state = state
        self.attachments = attachments
    }
}

struct WordPressAgentConversation: Identifiable, Equatable, Codable {
    let id: String
    let key: WordPressAgentConversationKey
    var remoteChatID: Int?
    var siteName: String?
    var sessionID: String?
    var messages: [WordPressAgentMessage]
    var pendingUploadedMedia: [WPCOMUploadedMedia]
    var isSending: Bool
    var errorMessage: String?
    var lastUpdated: Date

    var title: String {
        if let siteName, !siteName.isEmpty {
            return siteName
        }
        if key.siteID <= 0 {
            return "Unknown site"
        }
        return "Site \(key.siteID)"
    }

    var isEmptyLocalDraft: Bool {
        remoteChatID == nil
            && sessionID == nil
            && messages.isEmpty
            && pendingUploadedMedia.isEmpty
            && !isSending
            && errorMessage == nil
    }

    init(
        id: String = WordPressAgentConversation.localID(),
        key: WordPressAgentConversationKey,
        remoteChatID: Int? = nil,
        siteName: String?,
        sessionID: String?,
        messages: [WordPressAgentMessage],
        pendingUploadedMedia: [WPCOMUploadedMedia] = [],
        isSending: Bool,
        errorMessage: String?,
        lastUpdated: Date
    ) {
        self.id = id
        self.key = key
        self.remoteChatID = remoteChatID
        self.siteName = siteName
        self.sessionID = sessionID
        self.messages = messages
        self.pendingUploadedMedia = pendingUploadedMedia
        self.isSending = isSending
        self.errorMessage = errorMessage
        self.lastUpdated = lastUpdated
    }

    static func localID() -> String {
        "local:\(UUID().uuidString)"
    }

    static func remoteID(agentID: String, chatID: Int) -> String {
        "wpcom:\(agentID):\(chatID)"
    }
}

struct ImageImportUploadResult: Equatable {
    let conversationID: String?
    let attachmentPageURLs: [URL]
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case permissions
    case keyBindings
    case transcription
    case wordpressCom
    case network
    case wordpressAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .permissions: return "Permissions"
        case .keyBindings: return "Key Bindings"
        case .transcription: return "Transcription"
        case .wordpressCom: return "WordPress.com"
        case .network: return "Network"
        case .wordpressAgent: return "WordPress Agent"
        }
    }

    var icon: String {
        switch self {
        case .permissions: return "lock.shield"
        case .keyBindings: return "keyboard"
        case .transcription: return "waveform"
        case .wordpressCom: return "person.crop.circle.badge.checkmark"
        case .network: return "network"
        case .wordpressAgent: return "sparkles"
        }
    }
}

private struct PreservedPasteboardEntry {
    let type: NSPasteboard.PasteboardType
    let value: Value

    enum Value {
        case string(String)
        case propertyList(Any)
        case data(Data)
    }
}

private struct PreservedPasteboardItem {
    let entries: [PreservedPasteboardEntry]

    init(item: NSPasteboardItem) {
        self.entries = item.types.compactMap { type in
            if let string = item.string(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .string(string))
            }
            if let propertyList = item.propertyList(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .propertyList(propertyList))
            }
            if let data = item.data(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .data(data))
            }
            return nil
        }
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for entry in entries {
            switch entry.value {
            case .string(let string):
                item.setString(string, forType: entry.type)
            case .propertyList(let propertyList):
                item.setPropertyList(propertyList, forType: entry.type)
            case .data(let data):
                item.setData(data, forType: entry.type)
            }
        }
        return item
    }
}

private struct PreservedPasteboardSnapshot {
    let items: [PreservedPasteboardItem]

    init(pasteboard: NSPasteboard) {
        self.items = (pasteboard.pasteboardItems ?? []).map(PreservedPasteboardItem.init)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        _ = pasteboard.writeObjects(items.map { $0.makePasteboardItem() })
    }
}

private struct PendingClipboardRestore {
    let snapshot: PreservedPasteboardSnapshot
    let expectedChangeCount: Int
}

private enum CommandInvocation: String {
    case automatic
    case manual
}

private enum SessionIntent {
    case dictation
    case command(invocation: CommandInvocation, selectedText: String)

    var isCommandMode: Bool {
        switch self {
        case .dictation:
            return false
        case .command:
            return true
        }
    }

    var persistedSelectedText: String? {
        switch self {
        case .dictation:
            return nil
        case .command(_, let selectedText):
            return selectedText
        }
    }
}

final class AppState: ObservableObject, @unchecked Sendable {
    private let holdShortcutStorageKey = "hold_shortcut"
    private let toggleShortcutStorageKey = "toggle_shortcut"
    private let agentUtilityOverlayShortcutStorageKey = "agent_utility_overlay_shortcut"
    private let savedHoldCustomShortcutStorageKey = "saved_hold_custom_shortcut"
    private let savedToggleCustomShortcutStorageKey = "saved_toggle_custom_shortcut"
    private let savedAgentUtilityOverlayCustomShortcutStorageKey = "saved_agent_utility_overlay_custom_shortcut"
    private let selectedMicrophoneStorageKey = "selected_microphone_id"
    private let shortcutStartDelayStorageKey = "shortcut_start_delay"
    private let preserveClipboardStorageKey = "preserve_clipboard"
    private let alertSoundsEnabledStorageKey = "alert_sounds_enabled"
    private let soundVolumeStorageKey = "sound_volume"
    private let commandModeEnabledStorageKey = "command_mode_enabled"
    private let commandModeStyleStorageKey = "command_mode_style"
    private let commandModeManualModifierStorageKey = "command_mode_manual_modifier"
    private let saveTranscriptionArtifactsStorageKey = "save_transcription_artifacts"
    private let wordpressAgentEnabledStorageKey = "wordpress_agent_enabled"
    private let wordpressAgentSpeakRepliesStorageKey = "wordpress_agent_speak_replies"
    private let wordpressAgentSpeechProviderStorageKey = "wordpress_agent_speech_provider"
    private let wordpressAgentVoiceIdentifierStorageKey = "wordpress_agent_voice_identifier"
    private let elevenLabsAPIKeyStorageAccount = "elevenlabs_api_key"
    private let elevenLabsVoiceIdentifierStorageKey = "elevenlabs_voice_identifier"
    private let selectedWPCOMSiteIDStorageKey = "selected_wpcom_site_id"
    private let wpcomAppSiteOverridesStorageKey = "wpcom_app_site_overrides"
    private let wordpressAgentStarredSiteIDsStorageKey = "wordpress_agent_starred_site_ids"
    private let wordpressComSitesCacheStorageKey = "wordpress_com_sites_cache"
    private let wordpressAgentConversationsCacheStorageKey = "wordpress_agent_conversations_cache"
    private let networkRoutingSettingsStorageKey = "network_routing_settings"
    private let wordpressAgentConversationPageSize = 20
    private let wordpressAgentConversationsCacheDebounceNanoseconds: UInt64 = 350_000_000
    private static let wordpressAgentFrontendAbilities: [WPCOMAgentFrontendAbility] = [.preview]
    private let maxWordPressAgentFrontendToolIterations = 4
    private let transcribingIndicatorDelay: TimeInterval = 0.25
    private let clipboardRestoreDelay: TimeInterval = 0.15


    @Published var hasCompletedSetup: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup")
        }
    }

    @Published var holdShortcut: ShortcutBinding {
        didSet {
            persistShortcut(holdShortcut, key: holdShortcutStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var toggleShortcut: ShortcutBinding {
        didSet {
            persistShortcut(toggleShortcut, key: toggleShortcutStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var agentUtilityOverlayShortcut: ShortcutBinding {
        didSet {
            persistShortcut(agentUtilityOverlayShortcut, key: agentUtilityOverlayShortcutStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var savedHoldCustomShortcut: ShortcutBinding? {
        didSet {
            persistOptionalShortcut(savedHoldCustomShortcut, key: savedHoldCustomShortcutStorageKey)
        }
    }

    @Published private(set) var savedToggleCustomShortcut: ShortcutBinding? {
        didSet {
            persistOptionalShortcut(savedToggleCustomShortcut, key: savedToggleCustomShortcutStorageKey)
        }
    }

    @Published private(set) var savedAgentUtilityOverlayCustomShortcut: ShortcutBinding? {
        didSet {
            persistOptionalShortcut(
                savedAgentUtilityOverlayCustomShortcut,
                key: savedAgentUtilityOverlayCustomShortcutStorageKey
            )
        }
    }

    @Published var isCommandModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCommandModeEnabled, forKey: commandModeEnabledStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var commandModeStyle: CommandModeStyle {
        didSet {
            UserDefaults.standard.set(commandModeStyle.rawValue, forKey: commandModeStyleStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var commandModeManualModifier: CommandModeManualModifier {
        didSet {
            UserDefaults.standard.set(commandModeManualModifier.rawValue, forKey: commandModeManualModifierStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var shortcutStartDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(shortcutStartDelay, forKey: shortcutStartDelayStorageKey)
        }
    }

    @Published var preserveClipboard: Bool {
        didSet {
            UserDefaults.standard.set(preserveClipboard, forKey: preserveClipboardStorageKey)
        }
    }

    @Published var alertSoundsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertSoundsEnabled, forKey: alertSoundsEnabledStorageKey)
        }
    }

    @Published var soundVolume: Float {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: soundVolumeStorageKey)
        }
    }

    @Published var saveTranscriptionArtifacts: Bool {
        didSet {
            UserDefaults.standard.set(saveTranscriptionArtifacts, forKey: saveTranscriptionArtifactsStorageKey)
        }
    }

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastTranscript: String = ""
    @Published var lastAgentResponse: String = ""
    @Published private(set) var wordpressAgentConversations: [WordPressAgentConversation] = [] {
        didSet {
            scheduleCachedWordPressAgentConversationsPersistence()
        }
    }
    @Published var selectedWordPressAgentConversationID: String?
    @Published private(set) var isRefreshingWordPressAgentConversations = false
    @Published private(set) var isLoadingMoreWordPressAgentConversations = false
    @Published private(set) var canLoadMoreWordPressAgentConversations = true
    @Published private(set) var hasLoadedWordPressAgentConversations = false
    @Published private(set) var wordpressAgentHistoryStatusMessage: String?
    @Published private(set) var wordpressAgentPreview: WordPressAgentPreview?
    private var wordpressAgentPreviewsByConversationID: [String: WordPressAgentPreview] = [:]
    @Published private(set) var isWordPressAgentWindowFocused = false
    @Published private(set) var isWordPressAgentUtilityOverlayFocused = false
    @Published var errorMessage: String?
    @Published var statusText: String = "Ready"
    @Published var hasAccessibility = false
    @Published var hotkeyMonitoringErrorMessage: String?
    @Published var isDebugOverlayActive = false
    @Published var selectedSettingsTab: SettingsTab? = .permissions
    @Published var debugStatusMessage = "Idle"
    @Published var lastRawTranscript = ""
    @Published var lastPostProcessedTranscript = ""
    @Published var lastPostProcessingPrompt = ""
    @Published var lastContextSummary = ""
    @Published var lastPostProcessingStatus = ""
    @Published var lastContextScreenshotDataURL: String? = nil
    @Published var lastContextScreenshotStatus = "No screenshot"
    @Published var launchAtLogin: Bool {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    @Published var networkRoutingSettings: NetworkRoutingSettings {
        didSet {
            persistNetworkRoutingSettings()
            AppNetworkSessionProvider.shared.update(settings: networkRoutingSettings)
        }
    }

    @Published var isWordPressAgentEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWordPressAgentEnabled, forKey: wordpressAgentEnabledStorageKey)
        }
    }

    @Published var shouldSpeakWordPressAgentReplies: Bool {
        didSet {
            UserDefaults.standard.set(shouldSpeakWordPressAgentReplies, forKey: wordpressAgentSpeakRepliesStorageKey)
        }
    }

    @Published var wordpressAgentSpeechProvider: WordPressAgentSpeechProvider {
        didSet {
            UserDefaults.standard.set(wordpressAgentSpeechProvider.rawValue, forKey: wordpressAgentSpeechProviderStorageKey)
            stopCurrentWordPressAgentSpeech()
            if wordpressAgentSpeechProvider == .elevenLabs,
               hasElevenLabsAPIKey,
               availableElevenLabsVoices.isEmpty {
                refreshElevenLabsVoicesFromUI()
            }
        }
    }

    @Published var selectedWordPressAgentVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedWordPressAgentVoiceIdentifier, forKey: wordpressAgentVoiceIdentifierStorageKey)
        }
    }

    @Published var selectedElevenLabsVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedElevenLabsVoiceIdentifier, forKey: elevenLabsVoiceIdentifierStorageKey)
        }
    }

    @Published private(set) var hasElevenLabsAPIKey = false
    @Published private(set) var isRefreshingElevenLabsVoices = false
    @Published private(set) var availableElevenLabsVoices: [ElevenLabsVoiceOption] = []
    @Published var elevenLabsStatusMessage: String?

    @Published var selectedMicrophoneID: String {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: selectedMicrophoneStorageKey)
        }
    }
    @Published var availableMicrophones: [AudioDevice] = []
    @Published private(set) var availableSpeechVoices: [SpeechVoiceOption] = []
    @Published private(set) var isWordPressComSignedIn = false
    @Published private(set) var isSigningInToWordPressCom = false
    @Published private(set) var isRefreshingWordPressComSites = false
    @Published private(set) var wordpressComSites: [WPCOMSite] = [] {
        didSet {
            persistCachedWordPressComSites()
        }
    }
    @Published private(set) var wordpressComUser: WPCOMUser?
    @Published private(set) var transcribeSkill: WPCOMGuideline?
    @Published private(set) var starredWordPressAgentSiteIDs: [Int] = [] {
        didSet {
            persistWordPressAgentStarredSiteIDs()
        }
    }
    @Published var wordpressComStatusMessage: String?
    @Published var selectedWordPressComSiteID: Int? {
        didSet {
            if let selectedWordPressComSiteID {
                UserDefaults.standard.set(selectedWordPressComSiteID, forKey: selectedWPCOMSiteIDStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedWPCOMSiteIDStorageKey)
            }
            Task { await discoverTranscribeSkillForSelectedSite() }
        }
    }
    @Published var wordpressComAppSiteOverrides: [WPCOMAppSiteOverride] {
        didSet {
            persistWordPressComAppSiteOverrides()
        }
    }
    @Published private(set) var latestExternalAppSnapshot: AppSelectionSnapshot?

    var sortedWordPressAgentConversations: [WordPressAgentConversation] {
        wordpressAgentConversations.sorted { lhs, rhs in
            lhs.lastUpdated > rhs.lastUpdated
        }
    }

    var selectedWordPressAgentConversation: WordPressAgentConversation? {
        if let selectedWordPressAgentConversationID,
           let conversation = wordpressAgentConversations.first(where: { $0.id == selectedWordPressAgentConversationID }) {
            return conversation
        }
        return nil
    }

    var selectedWordPressComSite: WPCOMSite? {
        guard let selectedWordPressComSiteID else { return nil }
        return wordpressComSites.first(where: { $0.id == selectedWordPressComSiteID })
    }

    var wordpressComSitesSortedByStarred: [WPCOMSite] {
        sortedWordPressComSitesByStarred(wordpressComSites)
    }

    func sortedWordPressComSitesByStarred(_ sites: [WPCOMSite]) -> [WPCOMSite] {
        let starredOrder = Dictionary(uniqueKeysWithValues: starredWordPressAgentSiteIDs.enumerated().map { ($0.element, $0.offset) })
        let originalOrder = Dictionary(uniqueKeysWithValues: sites.enumerated().map { ($0.element.id, $0.offset) })

        return sites.sorted { lhs, rhs in
            let lhsStarredIndex = starredOrder[lhs.id]
            let rhsStarredIndex = starredOrder[rhs.id]
            if (lhsStarredIndex != nil) != (rhsStarredIndex != nil) {
                return lhsStarredIndex != nil
            }
            if let lhsStarredIndex,
               let rhsStarredIndex,
               lhsStarredIndex != rhsStarredIndex {
                return lhsStarredIndex < rhsStarredIndex
            }
            return (originalOrder[lhs.id] ?? Int.max) < (originalOrder[rhs.id] ?? Int.max)
        }
    }

    func setWordPressAgentWindowFocused(_ isFocused: Bool) {
        let shouldRefreshRecentConversations = isFocused && !isWordPressAgentWindowFocused
        isWordPressAgentWindowFocused = isFocused
        if shouldRefreshRecentConversations {
            refreshWordPressAgentConversationsFromUI()
        }
    }

    func setWordPressAgentUtilityOverlayFocused(_ isFocused: Bool) {
        isWordPressAgentUtilityOverlayFocused = isFocused
    }

    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let overlayManager = RecordingOverlayManager()
    private let wpcomClient = WPCOMClient()
    private let elevenLabsClient = ElevenLabsClient()
    private var accessibilityTimer: Timer?
    private var audioLevelCancellable: AnyCancellable?
    private var debugOverlayTimer: Timer?
    private var recordingInitializationTimer: DispatchSourceTimer?
    private var transcribingIndicatorTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var contextService: AppContextService
    private var contextCaptureTask: Task<AppContext?, Never>?
    private var capturedContext: AppContext?
    private var appActivationObserver: NSObjectProtocol?
    private var audioDeviceObservers: [NSObjectProtocol] = []
    private var needsMicrophoneRefreshAfterRecording = false
    private let shortcutSessionController = DictationShortcutSessionController()
    private var activeRecordingTriggerMode: RecordingTriggerMode?
    private var currentSessionIntent: SessionIntent = .dictation
    private var currentSessionWordPressComSiteID: Int?
    private var currentSessionWordPressAgentConversationKey: WordPressAgentConversationKey?
    private var currentSessionWordPressAgentConversationID: String?
    private var currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
    private var pendingSelectionSnapshot: AppSelectionSnapshot?
    private var pendingManualCommandInvocation = false
    private var pendingShortcutStartTask: Task<Void, Never>?
    private var pendingShortcutStartMode: RecordingTriggerMode?
    private var pendingOverlayDismissToken: UUID?
    private var pendingWordPressAgentConversationsCacheTask: Task<Void, Never>?
    private var wordpressAgentConversationsCacheGeneration = 0
    private var shouldPersistWordPressAgentConversationsCache = true
    private var shouldMonitorHotkeys = false
    private var isCapturingShortcut = false
    private var isAwaitingMicrophonePermission = false
    private var pendingMicrophonePermissionTriggerMode: RecordingTriggerMode?
    private var nextWordPressAgentConversationsPage = 1
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var elevenLabsSpeechTask: Task<Void, Never>?
    private var elevenLabsAudioPlayer: AVAudioPlayer?

    init() {
        UserDefaults.standard.removeObject(forKey: "force_http2_transcription")
        UserDefaults.standard.removeObject(forKey: "wordpress_agent_recent_site_ids")
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        let shortcuts = Self.loadShortcutConfiguration(
            holdKey: holdShortcutStorageKey,
            toggleKey: toggleShortcutStorageKey,
            agentUtilityOverlayKey: agentUtilityOverlayShortcutStorageKey
        )
        let savedHoldCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: savedHoldCustomShortcutStorageKey,
            fallback: shortcuts.hold.isCustom ? shortcuts.hold : nil
        )
        let savedToggleCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: savedToggleCustomShortcutStorageKey,
            fallback: shortcuts.toggle.isCustom ? shortcuts.toggle : nil
        )
        let savedAgentUtilityOverlayCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: savedAgentUtilityOverlayCustomShortcutStorageKey,
            fallback: shortcuts.agentUtilityOverlay.isCustom ? shortcuts.agentUtilityOverlay : nil
        )
        let shortcutStartDelay = max(0, UserDefaults.standard.double(forKey: shortcutStartDelayStorageKey))
        let isCommandModeEnabled = UserDefaults.standard.object(forKey: commandModeEnabledStorageKey) == nil
            ? false
            : UserDefaults.standard.bool(forKey: commandModeEnabledStorageKey)
        let commandModeStyle = CommandModeStyle(
            rawValue: UserDefaults.standard.string(forKey: commandModeStyleStorageKey) ?? ""
        ) ?? .automatic
        let commandModeManualModifier = CommandModeManualModifier(
            rawValue: UserDefaults.standard.string(forKey: commandModeManualModifierStorageKey) ?? ""
        ) ?? .option
        let preserveClipboard = UserDefaults.standard.object(forKey: preserveClipboardStorageKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: preserveClipboardStorageKey)
        let soundVolume: Float = UserDefaults.standard.object(forKey: soundVolumeStorageKey) != nil
            ? UserDefaults.standard.float(forKey: soundVolumeStorageKey) : 1.0
        let alertSoundsEnabled = UserDefaults.standard.object(forKey: alertSoundsEnabledStorageKey) != nil
            ? UserDefaults.standard.bool(forKey: alertSoundsEnabledStorageKey)
            : soundVolume > 0
        let saveTranscriptionArtifacts = UserDefaults.standard.object(forKey: saveTranscriptionArtifactsStorageKey) != nil
            ? UserDefaults.standard.bool(forKey: saveTranscriptionArtifactsStorageKey)
            : false
        let isWordPressAgentEnabled = UserDefaults.standard.object(forKey: wordpressAgentEnabledStorageKey) != nil
            ? UserDefaults.standard.bool(forKey: wordpressAgentEnabledStorageKey)
            : false
        let shouldSpeakWordPressAgentReplies = UserDefaults.standard.object(forKey: wordpressAgentSpeakRepliesStorageKey) != nil
            ? UserDefaults.standard.bool(forKey: wordpressAgentSpeakRepliesStorageKey)
            : false
        let wordpressAgentSpeechProvider = WordPressAgentSpeechProvider(
            rawValue: UserDefaults.standard.string(forKey: wordpressAgentSpeechProviderStorageKey) ?? ""
        ) ?? .system
        let selectedWordPressAgentVoiceIdentifier =
            UserDefaults.standard.string(forKey: wordpressAgentVoiceIdentifierStorageKey) ?? ""
        let selectedElevenLabsVoiceIdentifier =
            UserDefaults.standard.string(forKey: elevenLabsVoiceIdentifierStorageKey) ?? ""
        let hasElevenLabsAPIKey = AppSettingsStorage.loadSecure(account: elevenLabsAPIKeyStorageAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        let initialAccessibility = AXIsProcessTrusted()

        let selectedMicrophoneID = UserDefaults.standard.string(forKey: selectedMicrophoneStorageKey) ?? "default"
        let storedSiteID = UserDefaults.standard.object(forKey: selectedWPCOMSiteIDStorageKey) as? Int
        let storedAppSiteOverrides = Self.loadWordPressComAppSiteOverrides(forKey: wpcomAppSiteOverridesStorageKey)
        let storedWordPressAgentStarredSiteIDs = Self.loadWordPressAgentStarredSiteIDs(
            forKey: wordpressAgentStarredSiteIDsStorageKey
        )
        let networkRoutingSettings = Self.loadNetworkRoutingSettings(forKey: networkRoutingSettingsStorageKey)

        self.contextService = AppContextService()
        let isInitiallyWordPressComSignedIn = wpcomClient.isSignedIn
        let cachedWordPressComSites = isInitiallyWordPressComSignedIn
            ? Self.loadCachedWordPressComSites(forKey: wordpressComSitesCacheStorageKey)
            : []
        let cachedWordPressAgentConversations = isInitiallyWordPressComSignedIn
            ? Self.loadCachedWordPressAgentConversations(forKey: wordpressAgentConversationsCacheStorageKey)
            : []
        let cachedRemoteConversationCount = cachedWordPressAgentConversations.filter { $0.remoteChatID != nil }.count
        self.hasCompletedSetup = hasCompletedSetup
        self.holdShortcut = shortcuts.hold
        self.toggleShortcut = shortcuts.toggle
        self.agentUtilityOverlayShortcut = shortcuts.agentUtilityOverlay
        self.savedHoldCustomShortcut = savedHoldCustomShortcut.binding
        self.savedToggleCustomShortcut = savedToggleCustomShortcut.binding
        self.savedAgentUtilityOverlayCustomShortcut = savedAgentUtilityOverlayCustomShortcut.binding
        self.isCommandModeEnabled = isCommandModeEnabled
        self.commandModeStyle = commandModeStyle
        self.commandModeManualModifier = commandModeManualModifier
        self.shortcutStartDelay = shortcutStartDelay
        self.preserveClipboard = preserveClipboard
        self.alertSoundsEnabled = alertSoundsEnabled
        self.soundVolume = soundVolume
        self.saveTranscriptionArtifacts = saveTranscriptionArtifacts
        self.isWordPressAgentEnabled = isWordPressAgentEnabled
        self.shouldSpeakWordPressAgentReplies = shouldSpeakWordPressAgentReplies
        self.wordpressAgentSpeechProvider = wordpressAgentSpeechProvider
        self.selectedWordPressAgentVoiceIdentifier = selectedWordPressAgentVoiceIdentifier
        self.selectedElevenLabsVoiceIdentifier = selectedElevenLabsVoiceIdentifier
        self.hasElevenLabsAPIKey = hasElevenLabsAPIKey
        self.hasAccessibility = initialAccessibility
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.networkRoutingSettings = networkRoutingSettings
        self.selectedMicrophoneID = selectedMicrophoneID
        self.selectedWordPressComSiteID = storedSiteID
        self.wordpressComAppSiteOverrides = storedAppSiteOverrides
        self.starredWordPressAgentSiteIDs = storedWordPressAgentStarredSiteIDs
        self.wordpressComSites = cachedWordPressComSites
        self.wordpressAgentConversations = cachedWordPressAgentConversations
        self.hasLoadedWordPressAgentConversations = !cachedWordPressAgentConversations.isEmpty
        self.canLoadMoreWordPressAgentConversations = cachedRemoteConversationCount >= wordpressAgentConversationPageSize
            && cachedRemoteConversationCount % wordpressAgentConversationPageSize == 0
        self.nextWordPressAgentConversationsPage = max(
            1,
            ((cachedRemoteConversationCount + wordpressAgentConversationPageSize - 1)
                / wordpressAgentConversationPageSize) + 1
        )
        self.isWordPressComSignedIn = isInitiallyWordPressComSignedIn
        AppNetworkSessionProvider.shared.update(settings: networkRoutingSettings)

        refreshAvailableMicrophones()
        refreshAvailableSpeechVoices()
        installAudioDeviceObservers()
        installAppActivationObserver()
        refreshLatestExternalAppSnapshot()

        if shortcuts.didUpdateHoldStoredValue {
            persistShortcut(shortcuts.hold, key: holdShortcutStorageKey)
        }
        if shortcuts.didUpdateToggleStoredValue {
            persistShortcut(shortcuts.toggle, key: toggleShortcutStorageKey)
        }
        if shortcuts.didUpdateAgentUtilityOverlayStoredValue {
            persistShortcut(shortcuts.agentUtilityOverlay, key: agentUtilityOverlayShortcutStorageKey)
        }
        if savedHoldCustomShortcut.didUpdateStoredValue {
            persistOptionalShortcut(savedHoldCustomShortcut.binding, key: savedHoldCustomShortcutStorageKey)
        }
        if savedToggleCustomShortcut.didUpdateStoredValue {
            persistOptionalShortcut(savedToggleCustomShortcut.binding, key: savedToggleCustomShortcutStorageKey)
        }
        if savedAgentUtilityOverlayCustomShortcut.didUpdateStoredValue {
            persistOptionalShortcut(
                savedAgentUtilityOverlayCustomShortcut.binding,
                key: savedAgentUtilityOverlayCustomShortcutStorageKey
            )
        }

        overlayManager.onStopButtonPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handleOverlayStopButtonPressed()
            }
        }

        if isInitiallyWordPressComSignedIn {
            Task { await refreshWordPressComSites() }
        }
    }

    deinit {
        elevenLabsSpeechTask?.cancel()
        pendingWordPressAgentConversationsCacheTask?.cancel()
        removeAudioDeviceObservers()
        removeAppActivationObserver()
    }

    private func removeAudioDeviceObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in audioDeviceObservers {
            notificationCenter.removeObserver(observer)
        }
        audioDeviceObservers.removeAll()
    }

    private func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateLatestExternalAppSnapshot(from: app)
        }
    }

    private func removeAppActivationObserver() {
        guard let appActivationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        self.appActivationObserver = nil
    }

    private func updateLatestExternalAppSnapshot(from app: NSRunningApplication?) {
        guard let app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        let snapshot = contextService.collectSelectionSnapshot(for: app)
        guard snapshot.bundleIdentifier != nil else { return }
        latestExternalAppSnapshot = snapshot
    }

    private struct StoredShortcutConfiguration {
        let hold: ShortcutBinding
        let toggle: ShortcutBinding
        let agentUtilityOverlay: ShortcutBinding
        let didUpdateHoldStoredValue: Bool
        let didUpdateToggleStoredValue: Bool
        let didUpdateAgentUtilityOverlayStoredValue: Bool
    }

    private struct StoredOptionalShortcut {
        let binding: ShortcutBinding?
        let didUpdateStoredValue: Bool
    }

    private struct StoredShortcutLoadResult {
        let binding: ShortcutBinding?
        let hadStoredValue: Bool
        let didNormalize: Bool
    }

    private static func loadShortcutConfiguration(
        holdKey: String,
        toggleKey: String,
        agentUtilityOverlayKey: String
    ) -> StoredShortcutConfiguration {
        let legacyPreset = ShortcutPreset(
            rawValue: UserDefaults.standard.string(forKey: "hotkey_option") ?? ShortcutPreset.fnKey.rawValue
        ) ?? .fnKey
        let hold = legacyPreset.binding
        let toggle = hold.withAddedModifiers(.command)
        let storedHold = loadShortcut(forKey: holdKey)
        let storedToggle = loadShortcut(forKey: toggleKey)
        let storedAgentUtilityOverlay = loadShortcut(forKey: agentUtilityOverlayKey)
        return StoredShortcutConfiguration(
            hold: storedHold.binding ?? hold,
            toggle: storedToggle.binding ?? toggle,
            agentUtilityOverlay: storedAgentUtilityOverlay.binding ?? .defaultAgentUtilityOverlay,
            didUpdateHoldStoredValue: storedHold.binding == nil || storedHold.didNormalize,
            didUpdateToggleStoredValue: storedToggle.binding == nil || storedToggle.didNormalize,
            didUpdateAgentUtilityOverlayStoredValue: storedAgentUtilityOverlay.binding == nil
                || storedAgentUtilityOverlay.didNormalize
        )
    }

    private static func loadShortcut(forKey key: String) -> StoredShortcutLoadResult {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: false, didNormalize: false)
        }
        guard let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: true, didNormalize: false)
        }
        let normalized = decoded.normalizedForStorageMigration()
        return StoredShortcutLoadResult(
            binding: normalized,
            hadStoredValue: true,
            didNormalize: normalized != decoded
        )
    }

    private static func loadSavedCustomShortcut(
        forKey key: String,
        fallback: ShortcutBinding?
    ) -> StoredOptionalShortcut {
        let stored = loadShortcut(forKey: key)
        if let binding = stored.binding {
            return StoredOptionalShortcut(binding: binding, didUpdateStoredValue: stored.didNormalize)
        }

        return StoredOptionalShortcut(
            binding: fallback,
            didUpdateStoredValue: stored.hadStoredValue || fallback != nil
        )
    }

    private func persistShortcut(_ binding: ShortcutBinding, key: String) {
        let normalizedBinding = binding.normalizedForStorageMigration()
        guard let data = try? JSONEncoder().encode(normalizedBinding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func persistOptionalShortcut(_ binding: ShortcutBinding?, key: String) {
        guard let binding else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        persistShortcut(binding, key: key)
    }

    private static func loadWordPressComAppSiteOverrides(forKey key: String) -> [WPCOMAppSiteOverride] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WPCOMAppSiteOverride].self, from: data) else {
            return []
        }

        var seenBundleIdentifiers = Set<String>()
        return decoded
            .compactMap { override -> WPCOMAppSiteOverride? in
                let bundleIdentifier = override.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleIdentifier.isEmpty else { return nil }
                let appName = override.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                return WPCOMAppSiteOverride(
                    bundleIdentifier: bundleIdentifier,
                    appName: appName.isEmpty ? bundleIdentifier : appName,
                    siteID: override.siteID
                )
            }
            .filter { override in
                seenBundleIdentifiers.insert(override.bundleIdentifier).inserted
            }
            .sorted(by: Self.sortWordPressComAppSiteOverrides)
    }

    private func persistWordPressComAppSiteOverrides() {
        guard let data = try? JSONEncoder().encode(wordpressComAppSiteOverrides) else { return }
        UserDefaults.standard.set(data, forKey: wpcomAppSiteOverridesStorageKey)
    }

    private static func loadWordPressAgentStarredSiteIDs(forKey key: String) -> [Int] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }

        var seenSiteIDs = Set<Int>()
        return decoded.filter { siteID in
            siteID > 0 && seenSiteIDs.insert(siteID).inserted
        }
    }

    private func persistWordPressAgentStarredSiteIDs() {
        guard let data = try? JSONEncoder().encode(starredWordPressAgentSiteIDs) else { return }
        UserDefaults.standard.set(data, forKey: wordpressAgentStarredSiteIDsStorageKey)
    }

    private static func loadNetworkRoutingSettings(forKey key: String) -> NetworkRoutingSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(NetworkRoutingSettings.self, from: data) {
            return decoded
        }

        return .default
    }

    private func persistNetworkRoutingSettings() {
        guard let data = try? JSONEncoder().encode(networkRoutingSettings) else { return }
        UserDefaults.standard.set(data, forKey: networkRoutingSettingsStorageKey)
    }

    private static func loadCachedWordPressComSites(forKey key: String) -> [WPCOMSite] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WPCOMSite].self, from: data) else {
            return []
        }

        var seenSiteIDs = Set<Int>()
        return decoded.filter { site in
            site.id > 0 && seenSiteIDs.insert(site.id).inserted
        }
    }

    private func persistCachedWordPressComSites() {
        guard let data = try? JSONEncoder().encode(wordpressComSites) else { return }
        UserDefaults.standard.set(data, forKey: wordpressComSitesCacheStorageKey)
    }

    private static func loadCachedWordPressAgentConversations(forKey key: String) -> [WordPressAgentConversation] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WordPressAgentConversation].self, from: data) else {
            return []
        }

        let cacheableConversations: [WordPressAgentConversation] = decoded.compactMap { conversation in
            guard !conversation.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var cachedConversation = conversation
            cachedConversation.isSending = false
            cachedConversation.errorMessage = nil
            return cachedConversation
        }
        return deduplicatedWordPressAgentConversations(cacheableConversations)
    }

    private static func deduplicatedWordPressAgentConversations(
        _ conversations: [WordPressAgentConversation]
    ) -> [WordPressAgentConversation] {
        var seenConversationIDs = Set<String>()
        var seenRemoteChatIDs = Set<Int>()
        var seenSessionIDs = Set<String>()

        return conversations.filter { conversation in
            let conversationID = conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !conversationID.isEmpty,
                  seenConversationIDs.insert(conversationID).inserted else {
                return false
            }

            if let remoteChatID = conversation.remoteChatID,
               !seenRemoteChatIDs.insert(remoteChatID).inserted {
                return false
            }

            if let sessionID = normalizedWordPressAgentSessionID(conversation.sessionID),
               !seenSessionIDs.insert(sessionID).inserted {
                return false
            }

            return true
        }
    }

    private static func normalizedWordPressAgentSessionID(_ sessionID: String?) -> String? {
        let trimmedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSessionID.isEmpty ? nil : trimmedSessionID
    }

    private func scheduleCachedWordPressAgentConversationsPersistence() {
        guard shouldPersistWordPressAgentConversationsCache else { return }

        let cacheableConversations = Self.deduplicatedWordPressAgentConversations(
            wordpressAgentConversations.filter { !$0.isEmptyLocalDraft }
        )
        let storageKey = wordpressAgentConversationsCacheStorageKey
        let debounceNanoseconds = wordpressAgentConversationsCacheDebounceNanoseconds

        pendingWordPressAgentConversationsCacheTask?.cancel()
        wordpressAgentConversationsCacheGeneration += 1
        let generation = wordpressAgentConversationsCacheGeneration

        pendingWordPressAgentConversationsCacheTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

            let shouldPersist = await MainActor.run { [weak self] in
                self?.wordpressAgentConversationsCacheGeneration == generation
            }
            guard shouldPersist else { return }

            guard let data = Self.encodedCachedWordPressAgentConversations(cacheableConversations),
                  !Task.isCancelled else {
                return
            }

            let shouldStillPersist = await MainActor.run { [weak self] in
                self?.wordpressAgentConversationsCacheGeneration == generation
            }
            guard shouldStillPersist else { return }

            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func cancelPendingWordPressAgentConversationsCachePersistence() {
        pendingWordPressAgentConversationsCacheTask?.cancel()
        pendingWordPressAgentConversationsCacheTask = nil
        wordpressAgentConversationsCacheGeneration += 1
    }

    private static func encodedCachedWordPressAgentConversations(
        _ conversations: [WordPressAgentConversation]
    ) -> Data? {
        try? JSONEncoder().encode(conversations)
    }

    private static func sortWordPressComAppSiteOverrides(_ lhs: WPCOMAppSiteOverride, _ rhs: WPCOMAppSiteOverride) -> Bool {
        let nameComparison = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
    }

    func signInToWordPressCom() {
        guard !isSigningInToWordPressCom else { return }
        isSigningInToWordPressCom = true
        wordpressComStatusMessage = "Opening WordPress.com sign in..."
        Task {
            do {
                _ = try await wpcomClient.signIn()
                await MainActor.run {
                    self.isWordPressComSignedIn = true
                    self.wordpressComStatusMessage = "Signed in to WordPress.com"
                }
                await refreshWordPressComSites()
            } catch {
                await MainActor.run {
                    self.wordpressComStatusMessage = error.localizedDescription
                    self.errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                self.isSigningInToWordPressCom = false
            }
        }
    }

    func signOutOfWordPressCom() {
        wpcomClient.signOut()
        cancelPendingWordPressAgentConversationsCachePersistence()
        isWordPressComSignedIn = false
        wordpressComSites = []
        wordpressComUser = nil
        selectedWordPressComSiteID = nil
        wordpressComAppSiteOverrides = []
        shouldPersistWordPressAgentConversationsCache = false
        wordpressAgentConversations = []
        shouldPersistWordPressAgentConversationsCache = true
        selectedWordPressAgentConversationID = nil
        wordpressAgentPreview = nil
        wordpressAgentPreviewsByConversationID = [:]
        isRefreshingWordPressAgentConversations = false
        isLoadingMoreWordPressAgentConversations = false
        canLoadMoreWordPressAgentConversations = true
        nextWordPressAgentConversationsPage = 1
        hasLoadedWordPressAgentConversations = false
        wordpressAgentHistoryStatusMessage = nil
        transcribeSkill = nil
        UserDefaults.standard.removeObject(forKey: wordpressComSitesCacheStorageKey)
        UserDefaults.standard.removeObject(forKey: wordpressAgentConversationsCacheStorageKey)
        wordpressComStatusMessage = "Signed out"
    }

    func setNetworkBypassesSystemProxy(_ bypassesSystemProxy: Bool) {
        networkRoutingSettings = NetworkRoutingSettings(bypassesSystemProxy: bypassesSystemProxy)
    }

    func refreshWordPressComSites() async {
        await MainActor.run {
            self.isRefreshingWordPressComSites = true
            self.wordpressComStatusMessage = "Loading WordPress.com sites..."
        }

        do {
            async let sitesTask = wpcomClient.fetchSites()
            async let userTask = wpcomClient.fetchCurrentUser()
            let sites = try await sitesTask
            let currentUser = try? await userTask
            await MainActor.run {
                let siteIDs = Set(sites.map(\.id))
                self.wordpressComSites = sites
                self.wordpressComUser = currentUser
                if let selected = self.selectedWordPressComSiteID,
                   siteIDs.contains(selected) {
                    // Keep the user's selected site.
                } else {
                    self.selectedWordPressComSiteID = sites.first?.id
                }
                self.pruneWordPressComAppSiteOverrides(validSiteIDs: siteIDs)
                self.pruneWordPressAgentStarredSites(validSiteIDs: siteIDs)
                self.isWordPressComSignedIn = true
                self.wordpressComStatusMessage = sites.isEmpty
                    ? "No WordPress.com sites found"
                    : "Ready"
                self.isRefreshingWordPressComSites = false
            }
            await discoverTranscribeSkillForSelectedSite()
            await refreshWordPressAgentConversations()
        } catch {
            await MainActor.run {
                self.wordpressComStatusMessage = error.localizedDescription
                self.errorMessage = error.localizedDescription
                self.isRefreshingWordPressComSites = false
                if case WPCOMClientError.missingRefreshToken = error {
                    self.isWordPressComSignedIn = false
                }
            }
        }
    }

    func refreshWordPressComSitesFromUI() {
        Task { await refreshWordPressComSites() }
    }

    func refreshWordPressAgentConversationsIfNeeded() async {
        let shouldRefresh = await MainActor.run {
            isWordPressComSignedIn
                && !isRefreshingWordPressAgentConversations
                && !isLoadingMoreWordPressAgentConversations
                && !hasLoadedWordPressAgentConversations
        }
        guard shouldRefresh else { return }
        await refreshWordPressAgentConversations()
    }

    func refreshWordPressAgentConversationsFromUI() {
        Task { await refreshWordPressAgentConversations() }
    }

    func loadMoreWordPressAgentConversationsFromUI() {
        Task { await loadMoreWordPressAgentConversations() }
    }

    func refreshWordPressAgentConversations(agentID: String = "dolly") async {
        let pageSize = wordpressAgentConversationPageSize
        let canRefresh = await MainActor.run {
            isWordPressComSignedIn
                && !isRefreshingWordPressAgentConversations
                && !isLoadingMoreWordPressAgentConversations
        }
        guard canRefresh else { return }

        await MainActor.run {
            self.isRefreshingWordPressAgentConversations = true
            self.wordpressAgentHistoryStatusMessage = nil
        }

        do {
            let page = try await fetchWordPressAgentConversationPage(
                agentID: agentID,
                pageNumber: 1,
                itemsPerPage: pageSize
            )
            let pageMayHaveMore = page.summaries.count >= pageSize

            await MainActor.run {
                let shouldRemoveMissingRemoteConversations = !pageMayHaveMore && !page.summaries.isEmpty
                let mergedConversationCount = self.mergeWordPressAgentHistory(
                    agentID: self.normalizedWordPressAgentID(agentID),
                    summaries: page.summaries,
                    chatsByID: page.chatsByID,
                    removeMissingRemoteConversations: shouldRemoveMissingRemoteConversations
                )
                self.hasLoadedWordPressAgentConversations = true
                self.canLoadMoreWordPressAgentConversations = pageMayHaveMore && mergedConversationCount > 0
                self.nextWordPressAgentConversationsPage = 2
                self.isRefreshingWordPressAgentConversations = false
                let hasAnyConversation = self.wordpressAgentConversations.contains { !$0.isEmptyLocalDraft }
                self.wordpressAgentHistoryStatusMessage = hasAnyConversation ? nil : "No Dolly history found"
            }
        } catch {
            await MainActor.run {
                self.wordpressAgentHistoryStatusMessage = "Could not load Dolly history: \(error.localizedDescription)"
                self.errorMessage = error.localizedDescription
                self.isRefreshingWordPressAgentConversations = false
            }
        }
    }

    func loadMoreWordPressAgentConversations(agentID: String = "dolly") async {
        let request = await MainActor.run { () -> (pageNumber: Int, itemsPerPage: Int)? in
            guard isWordPressComSignedIn,
                  !isRefreshingWordPressAgentConversations,
                  !isLoadingMoreWordPressAgentConversations else {
                return nil
            }
            isLoadingMoreWordPressAgentConversations = true
            return (nextWordPressAgentConversationsPage, wordpressAgentConversationPageSize)
        }
        guard let request else { return }

        do {
            let page = try await fetchWordPressAgentConversationPage(
                agentID: agentID,
                pageNumber: request.pageNumber,
                itemsPerPage: request.itemsPerPage
            )
            let existingRemoteChatIDs = await MainActor.run {
                Set(self.wordpressAgentConversations.compactMap(\.remoteChatID))
            }
            let containsNewRemoteConversation = page.summaries.contains { summary in
                !existingRemoteChatIDs.contains(summary.chatID)
            }
            let hasMore = page.summaries.count >= request.itemsPerPage && containsNewRemoteConversation

            await MainActor.run {
                let mergedConversationCount: Int
                if containsNewRemoteConversation {
                    mergedConversationCount = self.mergeWordPressAgentHistory(
                        agentID: self.normalizedWordPressAgentID(agentID),
                        summaries: page.summaries,
                        chatsByID: page.chatsByID,
                        removeMissingRemoteConversations: false
                    )
                } else {
                    mergedConversationCount = 0
                }
                self.hasLoadedWordPressAgentConversations = true
                self.canLoadMoreWordPressAgentConversations = hasMore && mergedConversationCount > 0
                self.nextWordPressAgentConversationsPage = page.summaries.isEmpty
                    || !containsNewRemoteConversation
                    || mergedConversationCount == 0
                    ? request.pageNumber
                    : request.pageNumber + 1
                self.isLoadingMoreWordPressAgentConversations = false
            }
        } catch {
            await MainActor.run {
                self.wordpressAgentHistoryStatusMessage = "Could not load more Dolly history: \(error.localizedDescription)"
                self.errorMessage = error.localizedDescription
                self.isLoadingMoreWordPressAgentConversations = false
            }
        }
    }

    private func fetchWordPressAgentConversationPage(
        agentID: String,
        pageNumber: Int,
        itemsPerPage: Int
    ) async throws -> (summaries: [WPCOMAgentConversationSummary], chatsByID: [Int: WPCOMAgentChat]) {
        let summaries = try await wpcomClient.fetchAgentConversationSummaries(
            agentID: agentID,
            pageNumber: pageNumber,
            itemsPerPage: itemsPerPage
        )
        var chatsByID: [Int: WPCOMAgentChat] = [:]
        for summary in summaries {
            do {
                chatsByID[summary.chatID] = try await wpcomClient.fetchAgentChat(
                    agentID: agentID,
                    chatID: summary.chatID
                )
            } catch {
                // Keep the summary row even if the full chat cannot be loaded.
            }
        }
        return (summaries, chatsByID)
    }

    func refreshLatestExternalAppSnapshot() {
        updateLatestExternalAppSnapshot(from: NSWorkspace.shared.frontmostApplication)
    }

    func wordPressComAppSiteOverride(for bundleIdentifier: String?) -> WPCOMAppSiteOverride? {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return nil }
        return wordpressComAppSiteOverrides.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func setWordPressComAppSiteOverride(bundleIdentifier: String?, appName: String?, siteID: Int?) {
        guard let bundleIdentifier = normalizedBundleIdentifier(bundleIdentifier) else { return }

        var overrides = wordpressComAppSiteOverrides.filter { $0.bundleIdentifier != bundleIdentifier }
        if let siteID {
            let trimmedAppName = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = trimmedAppName?.isEmpty == false ? trimmedAppName! : bundleIdentifier
            overrides.append(WPCOMAppSiteOverride(
                bundleIdentifier: bundleIdentifier,
                appName: displayName,
                siteID: siteID
            ))
        }
        wordpressComAppSiteOverrides = overrides.sorted(by: Self.sortWordPressComAppSiteOverrides)
    }

    func assignSelectedWordPressComSiteToLatestExternalApp() {
        guard let siteID = selectedWordPressComSiteID,
              let snapshot = latestExternalAppSnapshot else { return }
        setWordPressComAppSiteOverride(
            bundleIdentifier: snapshot.bundleIdentifier,
            appName: snapshot.appName,
            siteID: siteID
        )
    }

    func removeWordPressComAppSiteOverride(bundleIdentifier: String) {
        setWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier, appName: nil, siteID: nil)
    }

    func effectiveWordPressComSiteID(for bundleIdentifier: String?) -> Int? {
        if let override = wordPressComAppSiteOverride(for: bundleIdentifier) {
            return override.siteID
        }
        return selectedWordPressComSiteID
    }

    func effectiveWordPressComSite(for bundleIdentifier: String?) -> WPCOMSite? {
        guard let siteID = effectiveWordPressComSiteID(for: bundleIdentifier) else { return nil }
        return wordpressComSites.first { $0.id == siteID }
    }

    private func pruneWordPressComAppSiteOverrides(validSiteIDs: Set<Int>) {
        let validOverrides = wordpressComAppSiteOverrides.filter { validSiteIDs.contains($0.siteID) }
        if validOverrides.count != wordpressComAppSiteOverrides.count {
            wordpressComAppSiteOverrides = validOverrides
        }
    }

    private func pruneWordPressAgentStarredSites(validSiteIDs: Set<Int>) {
        let prunedSiteIDs = starredWordPressAgentSiteIDs.filter { validSiteIDs.contains($0) }
        if prunedSiteIDs.count != starredWordPressAgentSiteIDs.count {
            starredWordPressAgentSiteIDs = prunedSiteIDs
        }
    }

    private func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    func discoverTranscribeSkillForSelectedSite() async {
        guard let siteID = selectedWordPressComSiteID, isWordPressComSignedIn else {
            transcribeSkill = nil
            return
        }

        do {
            transcribeSkill = try await wpcomClient.discoverTranscribeSkill(siteID: siteID)
        } catch {
            transcribeSkill = nil
        }
    }

    func openTranscribeSkill() {
        guard let transcribeSkill,
              let selectedWordPressComSite else { return }
        NSWorkspace.shared.open(wpcomClient.editURL(for: transcribeSkill, site: selectedWordPressComSite))
    }

    func transcribeAudioForSetupTest(fileURL: URL) async throws -> String {
        let context = await contextService.collectContext()
        let response = try await transcribeWithWordPressCom(
            fileURL: fileURL,
            intent: .dictation,
            context: context,
            enableWordPressAgent: false,
            saveArtifact: false
        )
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeWithWordPressCom(
        fileURL: URL,
        intent: SessionIntent,
        context: AppContext,
        siteID explicitSiteID: Int? = nil,
        enableWordPressAgent: Bool,
        saveArtifact: Bool
    ) async throws -> WPCOMTranscribeResponse {
        guard let siteID = explicitSiteID ?? effectiveWordPressComSiteID(for: context.bundleIdentifier) else {
            throw WPCOMClientError.missingSelectedSite
        }

        let selectedText: String?
        let intentValue: String
        if enableWordPressAgent {
            intentValue = "auto"
            selectedText = intent.persistedSelectedText
        } else {
            switch intent {
            case .dictation:
                intentValue = "dictation"
                selectedText = nil
            case .command(_, let text):
                intentValue = "command"
                selectedText = text
            }
        }

        let appContext = WPCOMAppContextPayload(
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            selectedText: context.selectedText,
            currentActivity: context.currentActivity
        )
        let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return try await wpcomClient.transcribe(
            audioFileURL: fileURL,
            siteID: siteID,
            intent: intentValue,
            selectedText: selectedText,
            appContext: appContext,
            clientVersion: clientVersion,
            saveArtifact: saveArtifact
        )
    }

    private struct WordPressAgentTurnResult {
        let response: WPCOMAgentResponse
        let conversationID: String
    }

    private struct WordPressAgentAppendResult {
        let conversationID: String
        let sessionID: String?
    }

    @discardableResult
    private func mergeWordPressAgentHistory(
        agentID: String,
        summaries: [WPCOMAgentConversationSummary],
        chatsByID: [Int: WPCOMAgentChat],
        removeMissingRemoteConversations: Bool
    ) -> Int {
        var mergedConversations = Self.deduplicatedWordPressAgentConversations(wordpressAgentConversations)
        var refreshedRemoteChatIDs = Set<Int>()
        var processedRemoteChatIDs = Set<Int>()
        var mergedConversationCount = 0

        for summary in summaries {
            guard processedRemoteChatIDs.insert(summary.chatID).inserted else { continue }

            let chat = chatsByID[summary.chatID]
            guard let conversation = makeWordPressAgentConversation(
                agentID: agentID,
                summary: summary,
                chat: chat
            ) else {
                continue
            }

            if let index = indexForRemoteWordPressAgentConversation(
                in: mergedConversations,
                chatID: summary.chatID,
                sessionID: conversation.sessionID
            ) {
                if mergedConversations[index].isSending {
                    continue
                }
                let existingID = mergedConversations[index].id
                mergedConversations[index] = WordPressAgentConversation(
                    id: existingID,
                    key: conversation.key,
                    remoteChatID: conversation.remoteChatID,
                    siteName: conversation.siteName,
                    sessionID: conversation.sessionID,
                    messages: conversation.messages,
                    pendingUploadedMedia: conversation.pendingUploadedMedia,
                    isSending: false,
                    errorMessage: nil,
                    lastUpdated: conversation.lastUpdated
                )
                mergedConversationCount += 1
            } else {
                mergedConversations.append(conversation)
                mergedConversationCount += 1
            }
            if let remoteChatID = conversation.remoteChatID {
                refreshedRemoteChatIDs.insert(remoteChatID)
            }
        }

        if removeMissingRemoteConversations && mergedConversationCount > 0 {
            mergedConversations.removeAll { conversation in
                guard conversation.key.agentID == agentID,
                      let remoteChatID = conversation.remoteChatID,
                      !conversation.isSending else {
                    return false
                }
                return !refreshedRemoteChatIDs.contains(remoteChatID)
            }
        }

        wordpressAgentConversations = Self.deduplicatedWordPressAgentConversations(mergedConversations)

        let selectedConversationExists = selectedWordPressAgentConversationID.map { selectedID in
            wordpressAgentConversations.contains { $0.id == selectedID }
        } ?? false
        if !selectedConversationExists {
            setActiveWordPressAgentConversation(
                sortedWordPressAgentConversations.first { !$0.isEmptyLocalDraft }?.id
            )
        }

        return mergedConversationCount
    }

    private func makeWordPressAgentConversation(
        agentID: String,
        summary: WPCOMAgentConversationSummary,
        chat: WPCOMAgentChat?
    ) -> WordPressAgentConversation? {
        let sourceMessages = chat?.messages ?? [summary.firstMessage, summary.lastMessage].compactMap { $0 }
        let messages = sourceMessages.compactMap { wordPressAgentMessage(from: $0) }
        guard !messages.isEmpty else { return nil }

        let siteID = chat?.siteID
            ?? summary.siteID
            ?? unknownWordPressAgentSiteID
        guard siteID != 0 else { return nil }

        let key = WordPressAgentConversationKey(siteID: siteID, agentID: agentID)
        let lastUpdated = messages.last?.date
            ?? wordPressAgentDate(from: summary.lastMessage?.createdAt)
            ?? wordPressAgentDate(from: summary.createdAt)
            ?? Date()

        return WordPressAgentConversation(
            id: WordPressAgentConversation.remoteID(agentID: agentID, chatID: summary.chatID),
            key: key,
            remoteChatID: summary.chatID,
            siteName: siteName(forWordPressAgentSiteID: siteID),
            sessionID: chat?.sessionID ?? summary.sessionID,
            messages: messages,
            isSending: false,
            errorMessage: nil,
            lastUpdated: lastUpdated
        )
    }

    private func wordPressAgentMessage(from historyMessage: WPCOMAgentHistoryMessage) -> WordPressAgentMessage? {
        let text = historyMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let role: WordPressAgentMessageRole
        switch historyMessage.role.lowercased() {
        case "user":
            role = .user
        case "bot", "assistant", "agent":
            role = .agent
        default:
            return nil
        }

        return WordPressAgentMessage(
            role: role,
            text: text,
            date: wordPressAgentDate(from: historyMessage.createdAt) ?? Date(),
            state: nil
        )
    }

    private func wordPressAgentDate(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private func indexForRemoteWordPressAgentConversation(
        in conversations: [WordPressAgentConversation],
        chatID: Int?,
        sessionID: String?
    ) -> Int? {
        if let chatID,
           let index = conversations.firstIndex(where: { $0.remoteChatID == chatID }) {
            return index
        }

        if let sessionID = Self.normalizedWordPressAgentSessionID(sessionID),
           let index = conversations.firstIndex(where: {
               Self.normalizedWordPressAgentSessionID($0.sessionID) == sessionID
           }) {
            return index
        }

        return nil
    }

    private func indexForRemoteWordPressAgentConversation(chatID: Int?, sessionID: String?) -> Int? {
        indexForRemoteWordPressAgentConversation(
            in: wordpressAgentConversations,
            chatID: chatID,
            sessionID: sessionID
        )
    }

    func selectWordPressAgentConversation(_ conversationID: String?) {
        guard let conversationID else {
            let fallbackConversation = sortedWordPressAgentConversations.first { !$0.isEmptyLocalDraft }
            setActiveWordPressAgentConversation(fallbackConversation?.id)
            if let siteID = fallbackConversation?.key.siteID, siteID > 0 {
                selectedWordPressComSiteID = siteID
            }
            return
        }

        guard let conversation = wordpressAgentConversations.first(where: { $0.id == conversationID }) else {
            let fallbackConversation = sortedWordPressAgentConversations.first { !$0.isEmptyLocalDraft }
            setActiveWordPressAgentConversation(fallbackConversation?.id)
            if let siteID = fallbackConversation?.key.siteID, siteID > 0 {
                selectedWordPressComSiteID = siteID
            }
            return
        }
        removeEmptyWordPressAgentDrafts(except: conversationID)
        setActiveWordPressAgentConversation(conversationID)
        if conversation.key.siteID > 0 {
            selectedWordPressComSiteID = conversation.key.siteID
        }
    }

    func selectWordPressAgentSite(_ siteID: Int) {
        _ = startWordPressAgentConversation(siteID: siteID)
    }

    func newestWordPressAgentConversation(for siteID: Int) -> WordPressAgentConversation? {
        sortedWordPressAgentConversations.first { $0.key.siteID == siteID && !$0.isEmptyLocalDraft }
    }

    private func newestWordPressAgentConversation(for key: WordPressAgentConversationKey) -> WordPressAgentConversation? {
        sortedWordPressAgentConversations.first { $0.key == key && !$0.isEmptyLocalDraft }
    }

    @discardableResult
    func startWordPressAgentConversation(siteID: Int? = nil, agentID: String = "dolly") -> String? {
        guard let siteID = siteID ?? selectedWordPressComSiteID else {
            errorMessage = "Choose a WordPress.com site before starting an agent session."
            return nil
        }

        let key = WordPressAgentConversationKey(siteID: siteID, agentID: normalizedWordPressAgentID(agentID))
        removeEmptyWordPressAgentDrafts()
        let conversationID = createWordPressAgentConversation(for: key)
        selectedWordPressComSiteID = siteID
        setActiveWordPressAgentConversation(conversationID)
        return conversationID
    }

    func isWordPressAgentSiteStarred(_ siteID: Int) -> Bool {
        starredWordPressAgentSiteIDs.contains(siteID)
    }

    func toggleWordPressAgentSiteStar(_ siteID: Int) {
        guard siteID > 0 else { return }
        if isWordPressAgentSiteStarred(siteID) {
            starredWordPressAgentSiteIDs.removeAll { $0 == siteID }
        } else {
            var siteIDs = starredWordPressAgentSiteIDs.filter { $0 != siteID }
            siteIDs.insert(siteID, at: 0)
            starredWordPressAgentSiteIDs = siteIDs
        }
    }

    func showWordPressAgentWindow(conversationID: String? = nil) {
        NotificationCenter.default.post(
            name: .showWordPressAgent,
            object: nil,
            userInfo: conversationID.map { ["conversationID": $0] }
        )
    }

    func showWordPressAgentUtilityOverlay() {
        NotificationCenter.default.post(name: .showWordPressAgentUtilityOverlay, object: nil)
    }

    func showImageUploadPicker() {
        NotificationCenter.default.post(name: .showImageUploadPicker, object: nil)
    }

    @MainActor
    func openWordPressAgentPreview(url: URL, title: String? = nil, conversationID: String? = nil) {
        let targetConversationID = conversationID
            ?? selectedWordPressAgentConversationID
            ?? startWordPressAgentConversation(siteID: selectedWordPressComSiteID)
        let previewURL = WordPressAgentPreviewURLResolver.previewURL(for: url) ?? url
        let preview = WordPressAgentPreview(
            url: previewURL,
            title: title,
            siteID: siteIDForWordPressAgentPreview(conversationID: targetConversationID)
        )

        if let targetConversationID {
            wordpressAgentPreviewsByConversationID[targetConversationID] = preview
        }
        wordpressAgentPreview = preview
        showWordPressAgentWindow(conversationID: targetConversationID)
    }

    @MainActor
    func closeWordPressAgentPreview() {
        if let selectedWordPressAgentConversationID {
            wordpressAgentPreviewsByConversationID[selectedWordPressAgentConversationID] = nil
        }
        wordpressAgentPreview = nil
    }

    @MainActor
    func updateWordPressAgentPreviewPage(
        previewID: UUID,
        currentURL: URL?,
        title: String?,
        isLoading: Bool
    ) {
        guard let preview = wordpressAgentPreview, preview.id == previewID else { return }
        let updatedPreview = preview.updatingCurrentPage(
            url: currentURL,
            title: title,
            isLoading: isLoading
        )
        guard updatedPreview != preview else { return }

        wordpressAgentPreview = updatedPreview
        if let selectedWordPressAgentConversationID {
            wordpressAgentPreviewsByConversationID[selectedWordPressAgentConversationID] = updatedPreview
        }
    }

    private func setActiveWordPressAgentConversation(_ conversationID: String?) {
        selectedWordPressAgentConversationID = conversationID
        wordpressAgentPreview = conversationID.flatMap { wordpressAgentPreviewsByConversationID[$0] }
    }

    private func siteIDForWordPressAgentPreview(conversationID: String?) -> Int? {
        let siteID = conversationID
            .flatMap { conversationID in
                wordpressAgentConversations.first(where: { $0.id == conversationID })?.key.siteID
            }
            ?? selectedWordPressAgentConversation?.key.siteID
            ?? selectedWordPressComSiteID

        guard let siteID, siteID > 0 else { return nil }
        return siteID
    }

    private func wordPressAgentPreviewContext(
        siteID: Int,
        conversationID: String?
    ) -> WPCOMAgentPreviewContextPayload? {
        let preview = conversationID.flatMap { wordpressAgentPreviewsByConversationID[$0] }
            ?? wordpressAgentPreview
        guard let preview,
              preview.siteID == nil || preview.siteID == siteID else {
            return nil
        }

        return WPCOMAgentPreviewContextPayload(
            isOpen: true,
            siteID: preview.siteID,
            openedURL: preview.url.absoluteString,
            currentURL: preview.currentURL.absoluteString,
            title: preview.displayTitle,
            isLoading: preview.isLoading
        )
    }

    func importImagesIntoWordPressAgentChat(
        fileURLs: [URL],
        siteID: Int,
        options: ImageImportProcessingOptions,
        opensChat: Bool,
        progress: @escaping (String) async -> Void
    ) async throws -> ImageImportUploadResult {
        let imageFileURLs = ImageImportProcessor.supportedImageFileURLs(from: fileURLs)
        guard !imageFileURLs.isEmpty else {
            throw WPCOMClientError.invalidResponse("Choose at least one image file to upload.")
        }

        await MainActor.run {
            self.selectedWordPressComSiteID = siteID
        }

        await progress("Preparing images...")
        let preparedImages = try await ImageImportProcessor.prepare(fileURLs: imageFileURLs, options: options)
        let processedCount = preparedImages.filter(\.wasProcessed).count
        if processedCount > 0 {
            await progress("Prepared \(processedCount) processed \(processedCount == 1 ? "copy" : "copies")...")
        }

        await progress("Uploading to WordPress.com...")
        let uploadedMedia = try await wpcomClient.uploadMedia(
            siteID: siteID,
            fileURLs: preparedImages.map(\.uploadURL),
            uploadTitles: options.anonymizesFilenames
                ? preparedImages.map { $0.uploadURL.deletingPathExtension().lastPathComponent }
                : []
        )

        let attachmentPageURLs = await MainActor.run {
            self.attachmentPageURLs(for: uploadedMedia, siteID: siteID)
        }

        let conversationID: String?
        if opensChat {
            await progress("Opening WordPress Agent...")
            conversationID = await MainActor.run(body: {
                self.seedWordPressAgentImageImportConversation(
                    siteID: siteID,
                    preparedImages: preparedImages,
                    uploadedMedia: uploadedMedia,
                    attachmentPageURLs: attachmentPageURLs
                )
            })
            if conversationID == nil {
                throw WPCOMClientError.missingSelectedSite
            }
        } else {
            conversationID = nil
        }

        return ImageImportUploadResult(
            conversationID: conversationID,
            attachmentPageURLs: attachmentPageURLs
        )
    }

    @discardableResult
    func submitWordPressAgentComposerMessage(
        _ message: String,
        attachments: [URL] = [],
        siteID: Int? = nil,
        startsNewConversation: Bool = false
    ) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty || !attachments.isEmpty else { return nil }

        let targetSiteID = siteID ?? selectedWordPressComSiteID ?? selectedWordPressAgentConversation?.key.siteID
        let targetKey = targetSiteID.map {
            WordPressAgentConversationKey(siteID: $0, agentID: "dolly")
        }
        let reusableConversation = targetKey.flatMap { key in
            selectedWordPressAgentConversation?.key == key ? selectedWordPressAgentConversation : nil
        }
        var conversationID = startsNewConversation ? nil : reusableConversation?.id
        if startsNewConversation {
            guard let newConversationID = startWordPressAgentConversation(siteID: targetSiteID) else { return nil }
            conversationID = newConversationID
        } else if !attachments.isEmpty,
           let reusableConversation,
           !reusableConversation.isEmptyLocalDraft {
            guard let newConversationID = startWordPressAgentConversation(siteID: targetSiteID) else { return nil }
            conversationID = newConversationID
        } else if conversationID == nil {
            guard let newConversationID = startWordPressAgentConversation(siteID: targetSiteID) else { return nil }
            conversationID = newConversationID
        }

        sendWordPressAgentChatMessage(trimmedMessage, attachments: attachments, conversationID: conversationID)
        return conversationID
    }

    func sendWordPressAgentChatMessage(_ message: String, attachments: [URL] = [], conversationID: String? = nil) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty || !attachments.isEmpty else { return }

        let existingConversation = conversationID.flatMap { id in
            wordpressAgentConversations.first(where: { $0.id == id })
        } ?? selectedWordPressAgentConversation

        let selectedConversation: WordPressAgentConversation?
        if let existingConversation {
            selectedConversation = existingConversation
        } else if let conversationID = startWordPressAgentConversation(),
                  let conversation = wordpressAgentConversations.first(where: { $0.id == conversationID }) {
            selectedConversation = conversation
        } else {
            selectedConversation = nil
        }

        guard let selectedConversation else {
            return
        }

        let key = selectedConversation.key
        guard key.siteID > 0 else {
            setWordPressAgentError("Choose a WordPress.com site before continuing this chat.", for: selectedConversation.id)
            return
        }
        let pendingUploadedMedia = selectedConversation.pendingUploadedMedia
        let messageToSend = trimmedMessage.isEmpty ? Self.defaultPrompt(forAttachmentCount: attachments.count) : trimmedMessage
        let messageAttachments = attachments.map { WordPressAgentAttachment(fileURL: $0) }

        Task {
            let context = await self.contextService.collectContext()
            do {
                let result = try await self.callWordPressAgentMessage(
                    message: messageToSend,
                    conversationID: selectedConversation.id,
                    key: key,
                    context: context,
                    attachments: attachments,
                    preuploadedMedia: pendingUploadedMedia,
                    displayAttachments: messageAttachments
                )
                await MainActor.run {
                    self.lastAgentResponse = result.response.text
                    self.deliverWordPressAgentNotification(reply: result.response.text, conversationID: result.conversationID)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func callWordPressAgent(
        agent: WPCOMTranscribeAgent,
        siteID: Int,
        context: AppContext
    ) async throws -> WordPressAgentTurnResult {
        let agentID = normalizedWordPressAgentID(agent.id)
        let key = WordPressAgentConversationKey(siteID: siteID, agentID: agentID)
        let message = agent.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await callWordPressAgentMessage(message: message, key: key, context: context)
    }

    private func callWordPressAgentMessage(
        message: String,
        conversationID: String? = nil,
        key: WordPressAgentConversationKey,
        context: AppContext,
        attachments: [URL] = [],
        preuploadedMedia: [WPCOMUploadedMedia] = [],
        displayAttachments: [WordPressAgentAttachment] = []
    ) async throws -> WordPressAgentTurnResult {
        let appendResult = await MainActor.run {
            self.appendWordPressAgentMessage(
                conversationID: conversationID,
                key: key,
                role: .user,
                text: message,
                state: nil,
                markSending: true,
                attachments: displayAttachments
            )
        }

        do {
            let response = try await sendWordPressAgentMessage(
                siteID: key.siteID,
                agentID: key.agentID,
                message: message,
                sessionID: appendResult.sessionID,
                context: context,
                attachments: attachments,
                preuploadedMedia: preuploadedMedia,
                conversationIDForPreview: appendResult.conversationID
            )
            await MainActor.run {
                self.recordWordPressAgentResponse(
                    response,
                    conversationID: appendResult.conversationID,
                    key: key
                )
            }
            return WordPressAgentTurnResult(response: response, conversationID: appendResult.conversationID)
        } catch {
            await MainActor.run {
                self.markWordPressAgentConversation(
                    conversationID: appendResult.conversationID,
                    key: key,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    private func sendWordPressAgentMessage(
        siteID: Int,
        agentID: String,
        message: String,
        sessionID: String?,
        context: AppContext,
        attachments: [URL] = [],
        preuploadedMedia: [WPCOMUploadedMedia] = [],
        conversationIDForPreview: String?
    ) async throws -> WPCOMAgentResponse {
        let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let freshlyUploadedMedia = try await wpcomClient.uploadMedia(siteID: siteID, fileURLs: attachments)
        let agentMessage = Self.agentMessage(
            message,
            includingImportedMediaReferences: preuploadedMedia
        )
        let frontendAbilities = Self.wordpressAgentFrontendAbilities
        let clientContext = WPCOMAgentClientContextPayload(
            constructorArguments: WPCOMAgentConstructorArgumentsPayload(client: "wpworkspace"),
            selectedSiteID: siteID,
            wpworkspace: WPCOMAgentWPWorkspaceContextPayload(
                appName: context.appName,
                currentActivity: context.currentActivity,
                clientVersion: clientVersion,
                preview: wordPressAgentPreviewContext(
                    siteID: siteID,
                    conversationID: conversationIDForPreview
                )
            )
        )
        let response = try await sendWordPressAgentMessageWithMediaRetry(
            siteID: siteID,
            agentID: agentID,
            message: agentMessage,
            clientContext: clientContext,
            sessionID: sessionID,
            uploadedMedia: freshlyUploadedMedia,
            mediaReferences: freshlyUploadedMedia,
            frontendAbilities: frontendAbilities
        )

        return try await resolveWordPressAgentFrontendToolCalls(
            initialResponse: response,
            siteID: siteID,
            agentID: agentID,
            clientContext: clientContext,
            sessionID: sessionID,
            frontendAbilities: frontendAbilities,
            conversationIDForPreview: conversationIDForPreview
        )
    }

    private func sendWordPressAgentMessageWithMediaRetry(
        siteID: Int,
        agentID: String,
        message: String,
        clientContext: WPCOMAgentClientContextPayload,
        sessionID: String?,
        uploadedMedia: [WPCOMUploadedMedia],
        mediaReferences: [WPCOMUploadedMedia],
        frontendAbilities: [WPCOMAgentFrontendAbility]
    ) async throws -> WPCOMAgentResponse {
        let retryDelays: [UInt64] = [
            1_500_000_000,
            4_000_000_000
        ]

        for attempt in 0...retryDelays.count {
            do {
                return try await wpcomClient.sendAgentMessage(
                    siteID: siteID,
                    agentID: agentID,
                    message: message,
                    clientContext: clientContext,
                    sessionID: sessionID,
                    uploadedMedia: uploadedMedia,
                    frontendAbilities: frontendAbilities
                )
            } catch {
                guard attempt < retryDelays.count,
                      shouldRetryWordPressAgentMediaRequest(error, mediaReferences: mediaReferences) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }

        throw WPCOMClientError.invalidResponse("WordPress Agent request did not complete.")
    }

    private func shouldRetryWordPressAgentMediaRequest(
        _ error: Error,
        mediaReferences: [WPCOMUploadedMedia]
    ) -> Bool {
        guard !mediaReferences.isEmpty else { return false }

        if case WPCOMClientError.requestFailed(let code, let details) = error {
            return code == -32000
                && details.localizedCaseInsensitiveContains("processing the request")
        }

        return false
    }

    private struct WordPressAgentFrontendToolExecution {
        let toolResult: WPCOMAgentToolResult
        let shouldReturnToAgent: Bool
        let agentMessage: String?
    }

    private func resolveWordPressAgentFrontendToolCalls(
        initialResponse: WPCOMAgentResponse,
        siteID: Int,
        agentID: String,
        clientContext: WPCOMAgentClientContextPayload,
        sessionID: String?,
        frontendAbilities: [WPCOMAgentFrontendAbility],
        conversationIDForPreview: String?
    ) async throws -> WPCOMAgentResponse {
        var response = initialResponse
        var currentSessionID = response.sessionID ?? sessionID
        var fallbackAgentMessage: String?

        for _ in 0..<maxWordPressAgentFrontendToolIterations {
            guard !response.toolCalls.isEmpty else {
                return responseWithFallback(response, fallbackAgentMessage: fallbackAgentMessage)
            }

            let executions = await executeWordPressAgentFrontendToolCalls(
                response.toolCalls,
                conversationIDForPreview: conversationIDForPreview
            )
            let toolResults = executions.map(\.toolResult)
            let agentMessages = executions.compactMap(\.agentMessage)
            if !agentMessages.isEmpty {
                fallbackAgentMessage = agentMessages.joined(separator: "\n")
            }

            guard executions.contains(where: \.shouldReturnToAgent) else {
                return responseWithFallback(response, fallbackAgentMessage: fallbackAgentMessage)
            }

            response = try await wpcomClient.sendAgentToolResults(
                siteID: siteID,
                agentID: agentID,
                toolCalls: response.toolCalls,
                toolResults: toolResults,
                clientContext: clientContext,
                sessionID: currentSessionID,
                taskID: response.taskID,
                frontendAbilities: frontendAbilities
            )
            currentSessionID = response.sessionID ?? currentSessionID
        }

        throw WPCOMClientError.invalidResponse("Agent requested too many frontend preview actions.")
    }

    private func executeWordPressAgentFrontendToolCalls(
        _ toolCalls: [WPCOMAgentToolCall],
        conversationIDForPreview: String?
    ) async -> [WordPressAgentFrontendToolExecution] {
        var executions: [WordPressAgentFrontendToolExecution] = []
        for toolCall in toolCalls {
            executions.append(
                await executeWordPressAgentFrontendToolCall(
                    toolCall,
                    conversationIDForPreview: conversationIDForPreview
                )
            )
        }
        return executions
    }

    private func executeWordPressAgentFrontendToolCall(
        _ toolCall: WPCOMAgentToolCall,
        conversationIDForPreview: String?
    ) async -> WordPressAgentFrontendToolExecution {
        guard Self.isPreviewFrontendToolID(toolCall.toolID) else {
            return WordPressAgentFrontendToolExecution(
                toolResult: WPCOMAgentToolResult(
                    toolCallID: toolCall.toolCallID,
                    toolID: toolCall.toolID,
                    result: nil,
                    error: "WP Workspace does not provide a frontend ability named \(toolCall.toolID)."
                ),
                shouldReturnToAgent: true,
                agentMessage: nil
            )
        }

        guard let urlString = toolCall.arguments.stringValue(forPossibleKeys: ["url", "URL", "uri"]),
              let url = Self.normalizedPreviewURL(from: urlString) else {
            return WordPressAgentFrontendToolExecution(
                toolResult: WPCOMAgentToolResult(
                    toolCallID: toolCall.toolCallID,
                    toolID: toolCall.toolID,
                    result: nil,
                    error: "Preview needs a valid http or https URL."
                ),
                shouldReturnToAgent: true,
                agentMessage: nil
            )
        }

        let title = toolCall.arguments.stringValue(forPossibleKeys: ["title", "name"])
        await MainActor.run {
            self.openWordPressAgentPreview(
                url: url,
                title: title,
                conversationID: conversationIDForPreview
            )
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle: String
        if let trimmedTitle, !trimmedTitle.isEmpty {
            displayTitle = trimmedTitle
        } else {
            displayTitle = url.host ?? url.absoluteString
        }
        let message = "Opened preview: \(displayTitle)"

        return WordPressAgentFrontendToolExecution(
            toolResult: WPCOMAgentToolResult(
                toolCallID: toolCall.toolCallID,
                toolID: toolCall.toolID,
                result: .object([
                    "success": .bool(true),
                    "url": .string(url.absoluteString),
                    "message": .string(message)
                ]),
                error: nil
            ),
            shouldReturnToAgent: true,
            agentMessage: message
        )
    }

    private func responseWithFallback(
        _ response: WPCOMAgentResponse,
        fallbackAgentMessage: String?
    ) -> WPCOMAgentResponse {
        guard response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let fallbackAgentMessage,
              !fallbackAgentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return response
        }

        return WPCOMAgentResponse(
            text: fallbackAgentMessage,
            state: "completed",
            sessionID: response.sessionID,
            taskID: response.taskID,
            toolCalls: response.toolCalls
        )
    }

    private static func isPreviewFrontendToolID(_ toolID: String) -> Bool {
        let normalizedToolID = toolID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedToolID == "preview"
            || normalizedToolID == "wpworkspace/preview"
            || normalizedToolID == "wpworkspace__preview"
            || normalizedToolID == "wpworkspace_preview"
    }

    private static func normalizedPreviewURL(from rawValue: String) -> URL? {
        WordPressAgentPreviewURLResolver.normalizedURL(from: rawValue)
    }

    @discardableResult
    private func appendWordPressAgentMessage(
        conversationID: String?,
        key: WordPressAgentConversationKey,
        role: WordPressAgentMessageRole,
        text: String,
        state: String?,
        markSending: Bool,
        attachments: [WordPressAgentAttachment] = []
    ) -> WordPressAgentAppendResult {
        let index = ensureWordPressAgentConversation(
            for: key,
            preferredConversationID: conversationID
        )
        guard wordpressAgentConversations.indices.contains(index) else {
            let newConversationID = createWordPressAgentConversation(for: key)
            let fallbackIndex = wordpressAgentConversations.firstIndex(where: { $0.id == newConversationID }) ?? 0
            let sessionID = UUID().uuidString
            wordpressAgentConversations[fallbackIndex].sessionID = sessionID
            return WordPressAgentAppendResult(
                conversationID: wordpressAgentConversations[fallbackIndex].id,
                sessionID: sessionID
            )
        }

        if wordpressAgentConversations[index].remoteChatID == nil,
           wordpressAgentConversations[index].sessionID == nil,
           wordpressAgentConversations[index].messages.isEmpty {
            wordpressAgentConversations[index].sessionID = UUID().uuidString
        }

        wordpressAgentConversations[index].messages.append(
            WordPressAgentMessage(role: role, text: text, state: state, attachments: attachments)
        )
        wordpressAgentConversations[index].lastUpdated = Date()
        wordpressAgentConversations[index].isSending = markSending
        wordpressAgentConversations[index].errorMessage = nil
        setActiveWordPressAgentConversation(wordpressAgentConversations[index].id)
        return WordPressAgentAppendResult(
            conversationID: wordpressAgentConversations[index].id,
            sessionID: wordpressAgentConversations[index].sessionID
        )
    }

    private func recordWordPressAgentResponse(
        _ response: WPCOMAgentResponse,
        conversationID: String,
        key: WordPressAgentConversationKey
    ) {
        let index = ensureWordPressAgentConversation(
            for: key,
            preferredConversationID: conversationID
        )
        guard wordpressAgentConversations.indices.contains(index) else { return }

        if let sessionID = response.sessionID, !sessionID.isEmpty {
            wordpressAgentConversations[index].sessionID = sessionID
        }
        if !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wordpressAgentConversations[index].messages.append(
                WordPressAgentMessage(role: .agent, text: response.text, state: response.state)
            )
        }
        wordpressAgentConversations[index].pendingUploadedMedia = []
        wordpressAgentConversations[index].lastUpdated = Date()
        wordpressAgentConversations[index].isSending = false
        wordpressAgentConversations[index].errorMessage = nil
        setActiveWordPressAgentConversation(wordpressAgentConversations[index].id)
    }

    private func setWordPressAgentError(_ error: String, for conversationID: String) {
        guard let index = wordpressAgentConversations.firstIndex(where: { $0.id == conversationID }) else {
            errorMessage = error
            return
        }
        wordpressAgentConversations[index].isSending = false
        wordpressAgentConversations[index].errorMessage = error
        setActiveWordPressAgentConversation(wordpressAgentConversations[index].id)
    }

    private func markWordPressAgentConversation(
        conversationID: String,
        key: WordPressAgentConversationKey,
        error: String
    ) {
        let index = ensureWordPressAgentConversation(
            for: key,
            preferredConversationID: conversationID
        )
        guard wordpressAgentConversations.indices.contains(index) else { return }
        wordpressAgentConversations[index].isSending = false
        wordpressAgentConversations[index].errorMessage = error
        wordpressAgentConversations[index].messages.append(
            WordPressAgentMessage(role: .system, text: error, state: "failed")
        )
        wordpressAgentConversations[index].lastUpdated = Date()
        setActiveWordPressAgentConversation(wordpressAgentConversations[index].id)
    }

    @MainActor
    private func seedWordPressAgentImageImportConversation(
        siteID: Int,
        preparedImages: [PreparedImageImport],
        uploadedMedia: [WPCOMUploadedMedia],
        attachmentPageURLs: [URL]
    ) -> String? {
        guard siteID > 0, !preparedImages.isEmpty, !uploadedMedia.isEmpty else { return nil }

        let key = WordPressAgentConversationKey(siteID: siteID, agentID: "dolly")
        removeEmptyWordPressAgentDrafts()
        let conversationID = createWordPressAgentConversation(for: key)
        guard let index = wordpressAgentConversations.firstIndex(where: { $0.id == conversationID }) else {
            return nil
        }

        wordpressAgentConversations[index].messages.append(
            WordPressAgentMessage(
                role: .user,
                text: Self.imageImportSeedMessage(uploadedMedia: uploadedMedia, attachmentPageURLs: attachmentPageURLs),
                attachments: preparedImages.map { WordPressAgentAttachment(fileURL: $0.uploadURL) }
            )
        )
        wordpressAgentConversations[index].pendingUploadedMedia = uploadedMedia
        wordpressAgentConversations[index].lastUpdated = Date()
        wordpressAgentConversations[index].isSending = false
        wordpressAgentConversations[index].errorMessage = nil
        selectedWordPressComSiteID = siteID
        setActiveWordPressAgentConversation(conversationID)
        return conversationID
    }

    @MainActor
    private func attachmentPageURLs(for uploadedMedia: [WPCOMUploadedMedia], siteID: Int) -> [URL] {
        let site = wordpressComSites.first(where: { $0.id == siteID })
        return uploadedMedia.compactMap { media in
            media.link
                ?? attachmentPageURL(for: media, site: site)
                ?? media.url
        }
    }

    private func attachmentPageURL(for media: WPCOMUploadedMedia, site: WPCOMSite?) -> URL? {
        guard let siteURLString = site?.url,
              let siteURL = URL(string: siteURLString),
              let slug = media.attachmentSlug else {
            return nil
        }

        var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        if !path.hasSuffix("/") {
            path += "/"
        }
        path += "\(slug)/"
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private func ensureWordPressAgentConversation(
        for key: WordPressAgentConversationKey,
        preferredConversationID: String? = nil
    ) -> Int {
        if let preferredConversationID,
           let index = wordpressAgentConversations.firstIndex(where: {
               $0.id == preferredConversationID && $0.key == key
           }) {
            wordpressAgentConversations[index].siteName = siteName(forWordPressAgentSiteID: key.siteID)
            return index
        }

        if let selectedWordPressAgentConversationID,
           let index = wordpressAgentConversations.firstIndex(where: {
               $0.id == selectedWordPressAgentConversationID && $0.key == key
           }) {
            wordpressAgentConversations[index].siteName = siteName(forWordPressAgentSiteID: key.siteID)
            return index
        }

        if let conversation = newestWordPressAgentConversation(for: key),
           let index = wordpressAgentConversations.firstIndex(where: { $0.id == conversation.id }) {
            wordpressAgentConversations[index].siteName = siteName(forWordPressAgentSiteID: key.siteID)
            return index
        }

        let conversationID = createWordPressAgentConversation(for: key)
        return wordpressAgentConversations.firstIndex(where: { $0.id == conversationID }) ?? 0
    }

    private func removeEmptyWordPressAgentDrafts(except preservedConversationID: String? = nil) {
        wordpressAgentConversations.removeAll { conversation in
            conversation.id != preservedConversationID && conversation.isEmptyLocalDraft
        }
    }

    @discardableResult
    private func createWordPressAgentConversation(
        for key: WordPressAgentConversationKey,
        id: String = WordPressAgentConversation.localID(),
        remoteChatID: Int? = nil,
        sessionID: String? = nil,
        messages: [WordPressAgentMessage] = [],
        lastUpdated: Date = Date()
    ) -> String {
        wordpressAgentConversations.append(
            WordPressAgentConversation(
                id: id,
                key: key,
                remoteChatID: remoteChatID,
                siteName: siteName(forWordPressAgentSiteID: key.siteID),
                sessionID: sessionID,
                messages: messages,
                isSending: false,
                errorMessage: nil,
                lastUpdated: lastUpdated
            )
        )
        return id
    }

    private func normalizedWordPressAgentID(_ agentID: String) -> String {
        let trimmed = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "dolly" : trimmed
    }

    private func wordPressAgentWindowDictationKey() -> WordPressAgentConversationKey? {
        if let selectedWordPressAgentConversation,
           selectedWordPressAgentConversation.key.siteID > 0 {
            return selectedWordPressAgentConversation.key
        }

        guard let selectedWordPressComSiteID else { return nil }
        return WordPressAgentConversationKey(siteID: selectedWordPressComSiteID, agentID: "dolly")
    }

    private func siteName(forWordPressAgentSiteID siteID: Int) -> String? {
        guard siteID > 0 else { return nil }
        return wordpressComSites.first(where: { $0.id == siteID })?.displayName
    }

    private static func defaultPrompt(forAttachmentCount attachmentCount: Int) -> String {
        attachmentCount == 1 ? "Please look at the attached image." : "Please look at the attached images."
    }

    private static func agentMessage(
        _ message: String,
        includingImportedMediaReferences importedMedia: [WPCOMUploadedMedia]
    ) -> String {
        guard !importedMedia.isEmpty else { return message }

        let count = importedMedia.count
        let noun = count == 1 ? "image" : "images"
        let mediaLines = importedMedia.prefix(20).map { media in
            let title = media.displayName ?? media.url?.lastPathComponent ?? "Uploaded image"
            guard !media.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "- \(title)"
            }
            return "- \(title): \(media.urlString)"
        }
        let omittedCount = importedMedia.count - mediaLines.count
        let omittedLine = omittedCount > 0 ? "\n- \(omittedCount) more uploaded \(omittedCount == 1 ? "image" : "images")" : ""

        return """
        Context: The user previously uploaded \(count) \(noun) to the WordPress.com media library in this chat. These are media-library URLs, not a request to inspect or analyze image contents unless the user explicitly asks.

        \(mediaLines.joined(separator: "\n"))\(omittedLine)

        User message:
        \(message)
        """
    }

    private static func imageImportSeedMessage(uploadedMedia: [WPCOMUploadedMedia], attachmentPageURLs: [URL]) -> String {
        let count = uploadedMedia.count
        let noun = count == 1 ? "image" : "images"
        let mediaLines = zip(uploadedMedia, attachmentPageURLs).prefix(12).map { media, pageURL in
            let title = media.displayName ?? media.url?.lastPathComponent ?? "Uploaded image"
            return "- [\(title)](\(pageURL.absoluteString))"
        }

        var message = "Uploaded \(count) \(noun) to the WordPress.com media library."
        if !mediaLines.isEmpty {
            message += "\n\n" + mediaLines.joined(separator: "\n")
        }
        if uploadedMedia.count > mediaLines.count {
            message += "\n- \(uploadedMedia.count - mediaLines.count) more"
        }
        message += "\n\nReady for your next instruction."
        return message
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        hasAccessibility = AXIsProcessTrusted()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hasAccessibility = AXIsProcessTrusted()
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openMicrophoneSettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            refreshAvailableMicrophones()
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.refreshAvailableMicrophones()
                    }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle on failure without re-triggering didSet
            let current = SMAppService.mainApp.status == .enabled
            if current != launchAtLogin {
                launchAtLogin = current
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        let current = SMAppService.mainApp.status == .enabled
        if current != launchAtLogin {
            launchAtLogin = current
        }
    }

    func refreshAvailableMicrophones() {
        guard !isRecording, !audioRecorder.isRecording else {
            needsMicrophoneRefreshAfterRecording = true
            return
        }

        needsMicrophoneRefreshAfterRecording = false
        availableMicrophones = AudioDevice.availableInputDevices()
    }

    func refreshAvailableSpeechVoices() {
        availableSpeechVoices = AVSpeechSynthesisVoice.speechVoices()
            .map { voice in
                SpeechVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    languageCode: voice.language
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func elevenLabsAPIKey() -> String? {
        guard let apiKey = AppSettingsStorage.loadSecure(account: elevenLabsAPIKeyStorageAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    func saveElevenLabsAPIKey(_ apiKey: String) {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            elevenLabsStatusMessage = "Enter an ElevenLabs API key first."
            return
        }

        AppSettingsStorage.saveSecure(trimmedAPIKey, account: elevenLabsAPIKeyStorageAccount)
        hasElevenLabsAPIKey = true
        elevenLabsStatusMessage = "ElevenLabs API key saved."
        refreshElevenLabsVoicesFromUI()
    }

    func clearElevenLabsAPIKey() {
        if wordpressAgentSpeechProvider == .elevenLabs {
            stopCurrentWordPressAgentSpeech()
        }
        AppSettingsStorage.deleteSecure(account: elevenLabsAPIKeyStorageAccount)
        hasElevenLabsAPIKey = false
        availableElevenLabsVoices = []
        selectedElevenLabsVoiceIdentifier = ""
        elevenLabsStatusMessage = "ElevenLabs API key removed."
    }

    func refreshElevenLabsVoicesFromUI() {
        Task { await refreshElevenLabsVoices() }
    }

    func refreshElevenLabsVoices() async {
        guard let apiKey = elevenLabsAPIKey() else {
            await MainActor.run {
                self.hasElevenLabsAPIKey = false
                self.availableElevenLabsVoices = []
                self.elevenLabsStatusMessage = "Add an ElevenLabs API key to load voices."
            }
            return
        }

        await MainActor.run {
            self.isRefreshingElevenLabsVoices = true
            self.elevenLabsStatusMessage = "Loading ElevenLabs voices..."
        }

        do {
            let voices = try await elevenLabsClient.fetchVoices(apiKey: apiKey)
            await MainActor.run {
                self.availableElevenLabsVoices = voices
                if voices.contains(where: { $0.id == self.selectedElevenLabsVoiceIdentifier }) {
                    // Keep the user's selected voice.
                } else {
                    self.selectedElevenLabsVoiceIdentifier = voices.first?.id ?? ""
                }
                self.hasElevenLabsAPIKey = true
                self.elevenLabsStatusMessage = voices.isEmpty
                    ? "No ElevenLabs voices found for this account."
                    : "ElevenLabs voices loaded."
                self.isRefreshingElevenLabsVoices = false
            }
        } catch {
            await MainActor.run {
                self.elevenLabsStatusMessage = error.localizedDescription
                self.errorMessage = error.localizedDescription
                self.isRefreshingElevenLabsVoices = false
            }
        }
    }

    private func refreshAvailableMicrophonesIfNeeded() {
        guard needsMicrophoneRefreshAfterRecording else { return }
        refreshAvailableMicrophones()
    }

    private func installAudioDeviceObservers() {
        removeAudioDeviceObservers()

        let notificationCenter = NotificationCenter.default
        let refreshOnAudioDeviceChange: (Notification) -> Void = { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice,
                  device.hasMediaType(.audio) else {
                return
            }
            self?.refreshAvailableMicrophones()
        }

        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
    }

    var usesFnShortcut: Bool {
        holdShortcut.usesFnKey || toggleShortcut.usesFnKey || agentUtilityOverlayShortcut.usesFnKey
    }

    var hasEnabledHoldShortcut: Bool {
        !holdShortcut.isDisabled
    }

    var hasEnabledToggleShortcut: Bool {
        !toggleShortcut.isDisabled
    }

    var hasEnabledAgentUtilityOverlayShortcut: Bool {
        !agentUtilityOverlayShortcut.isDisabled
    }

    var shortcutStatusText: String {
        if hotkeyMonitoringErrorMessage != nil {
            return "Global shortcuts unavailable"
        }

        switch (hasEnabledHoldShortcut, hasEnabledToggleShortcut) {
        case (true, true):
            return "Hold \(holdShortcut.displayName) or tap \(toggleShortcut.displayName) to dictate"
        case (true, false):
            return "Hold \(holdShortcut.displayName) to dictate"
        case (false, true):
            return "Tap \(toggleShortcut.displayName) to dictate"
        case (false, false):
            return "No dictation shortcut enabled"
        }
    }

    var shortcutStartDelayMilliseconds: Int {
        Int((shortcutStartDelay * 1000).rounded())
    }

    func savedCustomShortcut(for role: ShortcutRole) -> ShortcutBinding? {
        switch role {
        case .hold:
            return savedHoldCustomShortcut
        case .toggle:
            return savedToggleCustomShortcut
        case .agentUtilityOverlay:
            return savedAgentUtilityOverlayCustomShortcut
        }
    }

    var commandModeManualModifierValidationMessage: String? {
        guard isCommandModeEnabled, commandModeStyle == .manual else { return nil }
        return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
    }

    @discardableResult
    func setCommandModeEnabled(_ enabled: Bool) -> String? {
        isCommandModeEnabled = enabled
        if enabled, commandModeStyle == .manual {
            return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
        }
        return nil
    }

    @discardableResult
    func setCommandModeStyle(_ style: CommandModeStyle) -> String? {
        commandModeStyle = style
        if isCommandModeEnabled, style == .manual {
            return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
        }
        return nil
    }

    @discardableResult
    func setCommandModeManualModifier(_ modifier: CommandModeManualModifier) -> String? {
        if isCommandModeEnabled,
           commandModeStyle == .manual,
           let message = commandModeManualModifierCollisionMessage(for: modifier) {
            return message
        }

        commandModeManualModifier = modifier
        return nil
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding, for role: ShortcutRole) -> String? {
        let binding = binding.normalizedForStorageMigration()
        let nextHoldShortcut = role == .hold ? binding : holdShortcut
        let nextToggleShortcut = role == .toggle ? binding : toggleShortcut
        let nextAgentUtilityOverlayShortcut = role == .agentUtilityOverlay ? binding : agentUtilityOverlayShortcut
        let nextShortcuts: [(role: ShortcutRole, binding: ShortcutBinding)] = [
            (.hold, nextHoldShortcut),
            (.toggle, nextToggleShortcut),
            (.agentUtilityOverlay, nextAgentUtilityOverlayShortcut)
        ]
        for lhsIndex in nextShortcuts.indices {
            for rhsIndex in nextShortcuts.indices where rhsIndex > lhsIndex {
                let lhs = nextShortcuts[lhsIndex]
                let rhs = nextShortcuts[rhsIndex]
                if lhs.binding.conflicts(with: rhs.binding) {
                    return "\(lhs.role.title) and \(rhs.role.title) shortcuts must be distinct."
                }
            }
        }
        if isCommandModeEnabled,
           commandModeStyle == .manual,
           let message = commandModeManualModifierCollisionMessage(
            for: commandModeManualModifier,
            holdBinding: nextHoldShortcut,
            toggleBinding: nextToggleShortcut
           ) {
            return message
        }

        switch role {
        case .hold:
            if binding.isCustom {
                savedHoldCustomShortcut = binding
            }
            holdShortcut = binding
        case .toggle:
            if binding.isCustom {
                savedToggleCustomShortcut = binding
            }
            toggleShortcut = binding
        case .agentUtilityOverlay:
            if binding.isCustom {
                savedAgentUtilityOverlayCustomShortcut = binding
            }
            agentUtilityOverlayShortcut = binding
        }

        return nil
    }

    private func commandModeManualModifierCollisionMessage(
        for modifier: CommandModeManualModifier,
        holdBinding: ShortcutBinding? = nil,
        toggleBinding: ShortcutBinding? = nil
    ) -> String? {
        let holdBinding = holdBinding ?? holdShortcut
        let toggleBinding = toggleBinding ?? toggleShortcut
        let manualModifier = modifier.shortcutModifier

        if !holdBinding.isDisabled && holdBinding.modifiers.contains(manualModifier) {
            return "That modifier is already part of the hold shortcut."
        }
        if !toggleBinding.isDisabled && toggleBinding.modifiers.contains(manualModifier) {
            return "That modifier is already part of the tap shortcut."
        }

        return nil
    }

    func startHotkeyMonitoring() {
        shouldMonitorHotkeys = true
        hotkeyManager.onShortcutEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleShortcutEvent(event)
            }
        }
        hotkeyManager.onEscapeKeyPressed = { [weak self] in
            self?.handleEscapeKeyPress() ?? false
        }
        restartHotkeyMonitoring()
    }

    func stopHotkeyMonitoring() {
        shouldMonitorHotkeys = false
        hotkeyMonitoringErrorMessage = nil
        hotkeyManager.onShortcutEvent = nil
        hotkeyManager.onEscapeKeyPressed = nil
        hotkeyManager.stop()
    }

    func suspendHotkeyMonitoringForShortcutCapture() {
        isCapturingShortcut = true
        restartHotkeyMonitoring()
    }

    func resumeHotkeyMonitoringAfterShortcutCapture() {
        isCapturingShortcut = false
        restartHotkeyMonitoring()
    }

    private var activeShortcutConfiguration: ShortcutConfiguration {
        let permittedAdditionalExactMatchModifiers: ShortcutModifiers
        if isCommandModeEnabled, commandModeStyle == .manual {
            permittedAdditionalExactMatchModifiers = commandModeManualModifier.shortcutModifier
        } else {
            permittedAdditionalExactMatchModifiers = []
        }

        return ShortcutConfiguration(
            hold: holdShortcut,
            toggle: toggleShortcut,
            agentUtilityOverlay: agentUtilityOverlayShortcut,
            permittedAdditionalExactMatchModifiers: permittedAdditionalExactMatchModifiers
        )
    }

    private func restartHotkeyMonitoring() {
        guard shouldMonitorHotkeys, !isCapturingShortcut, !isAwaitingMicrophonePermission else {
            hotkeyManager.stop()
            return
        }

        do {
            try hotkeyManager.start(configuration: activeShortcutConfiguration)
            hotkeyMonitoringErrorMessage = nil
        } catch {
            hotkeyMonitoringErrorMessage = error.localizedDescription
            os_log(.error, log: recordingLog, "Hotkey monitoring failed to start: %{public}@", error.localizedDescription)
        }
    }

    private func handleShortcutEvent(_ event: ShortcutEvent) {
        if event == .agentUtilityOverlayActivated {
            guard !isRecording else { return }
            cancelPendingShortcutStart()
            shortcutSessionController.reset()
            showWordPressAgentUtilityOverlay()
            return
        }

        guard let action = shortcutSessionController.handle(event: event, isTranscribing: isTranscribing) else {
            return
        }

        switch action {
        case .start(let mode):
            os_log(.info, log: recordingLog, "Shortcut start fired for mode %{public}@", mode.rawValue)
            scheduleShortcutStart(mode: mode)
        case .stop:
            cancelPendingShortcutStart()
            guard isRecording else {
                shortcutSessionController.reset()
                activeRecordingTriggerMode = nil
                return
            }
            stopAndTranscribe()
        case .switchedToToggle:
            if isRecording {
                activeRecordingTriggerMode = .toggle
                overlayManager.setRecordingTriggerMode(.toggle, animated: true)
            } else if pendingShortcutStartMode != nil {
                pendingShortcutStartMode = .toggle
            }
        }
    }

    private func handleEscapeKeyPress() -> Bool {
        if isTranscribing {
            cancelTranscription()
            return true
        }

        if pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle {
            cancelToggleShortcutSession()
            return true
        }

        return false
    }

    func toggleRecording() {
        os_log(.info, log: recordingLog, "toggleRecording() called, isRecording=%{public}d", isRecording)
        cancelPendingShortcutStart()
        if isRecording {
            stopAndTranscribe()
        } else {
            shortcutSessionController.beginManual(mode: .toggle)
            startRecording(triggerMode: .toggle)
        }
    }

    private func handleOverlayStopButtonPressed() {
        guard isRecording, activeRecordingTriggerMode == .toggle else { return }
        stopAndTranscribe()
    }

    private func cancelToggleShortcutSession() {
        guard pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle else { return }

        cancelPendingShortcutStart()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        cancelRecordingInitializationTimer()
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        isRecording = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        audioRecorder.cancelRecording()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func cancelTranscription() {
        guard isTranscribing else { return }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribingIndicatorTask?.cancel()
        transcribingIndicatorTask = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        isRecording = false
        isTranscribing = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        audioRecorder.cleanup()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func scheduleShortcutStart(mode: RecordingTriggerMode) {
        cancelPendingShortcutStart(resetMode: false)
        pendingSelectionSnapshot = contextService.collectSelectionSnapshot()
        pendingManualCommandInvocation = hotkeyManager.currentPressedModifiers.contains(
            commandModeManualModifier.shortcutModifier
        )
        pendingShortcutStartMode = mode
        let delay = shortcutStartDelay

        guard delay > 0 else {
            pendingShortcutStartMode = nil
            startRecording(triggerMode: mode)
            return
        }

        pendingShortcutStartTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, let pendingMode = self.pendingShortcutStartMode else { return }
                self.pendingShortcutStartTask = nil
                self.pendingShortcutStartMode = nil
                self.startRecording(triggerMode: pendingMode)
            }
        }
    }

    private func cancelPendingShortcutStart(resetMode: Bool = true) {
        pendingShortcutStartTask?.cancel()
        pendingShortcutStartTask = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        if resetMode {
            pendingShortcutStartMode = nil
        }
    }

    private func resolveSessionIntent(
        triggerMode: RecordingTriggerMode,
        selectionSnapshot: AppSelectionSnapshot,
        manualCommandRequested: Bool
    ) -> SessionIntent? {
        guard isCommandModeEnabled else {
            return .dictation
        }

        let rawSelectedText = selectionSnapshot.selectedText ?? ""
        let trimmedSelectedText = rawSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch commandModeStyle {
        case .automatic:
            if !trimmedSelectedText.isEmpty {
                return .command(invocation: .automatic, selectedText: rawSelectedText)
            }
            return .dictation
        case .manual:
            if let message = commandModeManualModifierCollisionMessage(for: commandModeManualModifier) {
                rejectInvalidCommandModeModifier(triggerMode: triggerMode, message: message)
                return nil
            }
            guard manualCommandRequested else {
                return .dictation
            }
            guard !trimmedSelectedText.isEmpty else {
                rejectCommandModeSelectionRequirement(triggerMode: triggerMode)
                return nil
            }
            return .command(invocation: .manual, selectedText: rawSelectedText)
        }
    }

    private func rejectCommandModeSelectionRequirement(triggerMode: RecordingTriggerMode) {
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        activeRecordingTriggerMode = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        errorMessage = "Select text to transform first."
        statusText = "Select text to transform first"
        debugStatusMessage = "Edit mode requires selected text"
        shortcutSessionController.reset()
        if triggerMode == .toggle {
            cancelPendingShortcutStart()
        }
        playAlertSound(named: "Basso")
        scheduleReadyStatusReset(after: 2, matching: ["Select text to transform first"])
    }

    private func rejectInvalidCommandModeModifier(triggerMode: RecordingTriggerMode, message: String) {
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        activeRecordingTriggerMode = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        errorMessage = message
        statusText = "Fix Edit Mode modifier"
        debugStatusMessage = "Edit mode modifier conflicts with dictation shortcuts"
        shortcutSessionController.reset()
        if triggerMode == .toggle {
            cancelPendingShortcutStart()
        }
        playAlertSound(named: "Basso")
        scheduleReadyStatusReset(after: 2, matching: ["Fix Edit Mode modifier"])
    }

    private func startRecording(triggerMode: RecordingTriggerMode) {
        let t0 = CFAbsoluteTimeGetCurrent()
        os_log(.info, log: recordingLog, "startRecording() entered")
        guard !isRecording && !isTranscribing else { return }
        let scheduledSelectionSnapshot = pendingSelectionSnapshot
        let scheduledManualCommandInvocation = pendingManualCommandInvocation
        cancelPendingShortcutStart()
        guard prepareRecordingStart(
            triggerMode: triggerMode,
            selectionSnapshot: scheduledSelectionSnapshot,
            manualCommandRequested: scheduledSelectionSnapshot == nil
                ? hotkeyManager.currentPressedModifiers.contains(commandModeManualModifier.shortcutModifier)
                : scheduledManualCommandInvocation,
            startedAt: t0
        ) else { return }
        guard ensureMicrophoneAccess() else { return }
        os_log(.info, log: recordingLog, "mic access check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        beginRecording(triggerMode: triggerMode)
        os_log(.info, log: recordingLog, "startRecording() finished: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    private func prepareRecordingStart(
        triggerMode: RecordingTriggerMode,
        selectionSnapshot: AppSelectionSnapshot? = nil,
        manualCommandRequested: Bool? = nil,
        startedAt: CFAbsoluteTime? = nil
    ) -> Bool {
        activeRecordingTriggerMode = triggerMode
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        guard hasAccessibility else {
            errorMessage = "Accessibility permission required. Grant access in System Settings > Privacy & Security > Accessibility."
            statusText = "No Accessibility"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            currentSessionWordPressComSiteID = nil
            currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
            shortcutSessionController.reset()
            showAccessibilityAlert()
            return false
        }
        if let startedAt {
            os_log(.info, log: recordingLog, "accessibility check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        }

        let selectionSnapshot = selectionSnapshot ?? contextService.collectSelectionSnapshot()

        if isWordPressAgentWindowFocused || isWordPressAgentUtilityOverlayFocused {
            guard isWordPressComSignedIn,
                  let agentConversationKey = wordPressAgentWindowDictationKey() else {
                errorMessage = "Sign in with WordPress.com and choose a default site before using agent dictation."
                statusText = "WordPress.com sign-in required"
                activeRecordingTriggerMode = nil
                currentSessionIntent = .dictation
                currentSessionWordPressComSiteID = nil
                currentSessionWordPressAgentConversationKey = nil
                currentSessionWordPressAgentConversationID = nil
                currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
                shortcutSessionController.reset()
                NotificationCenter.default.post(name: .showSettings, object: nil)
                return false
            }

            let agentConversationIndex = ensureWordPressAgentConversation(for: agentConversationKey)
            currentSessionIntent = .dictation
            currentSessionWordPressComSiteID = agentConversationKey.siteID
            currentSessionWordPressAgentConversationKey = agentConversationKey
            currentSessionWordPressAgentConversationID = wordpressAgentConversations.indices.contains(agentConversationIndex)
                ? wordpressAgentConversations[agentConversationIndex].id
                : nil
            currentSessionShouldOpenWordPressAgentWindowOnCompletion = isWordPressAgentUtilityOverlayFocused
            overlayManager.setRecordingTriggerMode(triggerMode, animated: false)
            return true
        }

        guard isWordPressComSignedIn,
              let resolvedSiteID = effectiveWordPressComSiteID(for: selectionSnapshot.bundleIdentifier) else {
            errorMessage = "Sign in with WordPress.com and choose a default site or app-specific site before dictating."
            statusText = "WordPress.com sign-in required"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            currentSessionWordPressComSiteID = nil
            currentSessionWordPressAgentConversationKey = nil
            currentSessionWordPressAgentConversationID = nil
            currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
            shortcutSessionController.reset()
            NotificationCenter.default.post(name: .showSettings, object: nil)
            return false
        }

        let manualCommandRequested = manualCommandRequested
            ?? hotkeyManager.currentPressedModifiers.contains(commandModeManualModifier.shortcutModifier)
        guard let resolvedIntent = resolveSessionIntent(
            triggerMode: triggerMode,
            selectionSnapshot: selectionSnapshot,
            manualCommandRequested: manualCommandRequested
        ) else { return false }

        currentSessionIntent = resolvedIntent
        currentSessionWordPressComSiteID = resolvedSiteID
        overlayManager.setRecordingTriggerMode(triggerMode, animated: false)
        return true
    }

    private func ensureMicrophoneAccess() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard let triggerMode = activeRecordingTriggerMode else {
                return false
            }

            prepareForMicrophonePermissionPrompt(triggerMode: triggerMode)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let strongSelf = self else { return }
                    let pendingTriggerMode = strongSelf.pendingMicrophonePermissionTriggerMode
                    strongSelf.pendingMicrophonePermissionTriggerMode = nil
                    strongSelf.isAwaitingMicrophonePermission = false
                    strongSelf.restartHotkeyMonitoring()

                    guard let triggerMode = pendingTriggerMode else { return }
                    if granted {
                        strongSelf.errorMessage = nil
                        if triggerMode == .toggle {
                            guard strongSelf.prepareRecordingStart(triggerMode: .toggle) else { return }
                            strongSelf.shortcutSessionController.beginManual(mode: .toggle)
                            strongSelf.beginRecording(triggerMode: .toggle)
                        } else {
                            strongSelf.currentSessionIntent = .dictation
                            strongSelf.currentSessionWordPressComSiteID = nil
                            strongSelf.statusText = "Microphone access granted. Press and hold again to record."
                            strongSelf.scheduleReadyStatusReset(
                                after: 2,
                                matching: ["Microphone access granted. Press and hold again to record."]
                            )
                        }
                    } else {
                        strongSelf.errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
                        strongSelf.statusText = "No Microphone"
                        strongSelf.activeRecordingTriggerMode = nil
                        strongSelf.currentSessionIntent = .dictation
                        strongSelf.currentSessionWordPressComSiteID = nil
                        strongSelf.shortcutSessionController.reset()
                        strongSelf.showMicrophonePermissionAlert()
                    }
                }
            }
            return false
        default:
            errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
            statusText = "No Microphone"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            currentSessionWordPressComSiteID = nil
            shortcutSessionController.reset()
            showMicrophonePermissionAlert()
            return false
        }
    }

    private func prepareForMicrophonePermissionPrompt(triggerMode: RecordingTriggerMode) {
        isAwaitingMicrophonePermission = true
        pendingMicrophonePermissionTriggerMode = triggerMode
        hotkeyManager.stop()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        currentSessionWordPressComSiteID = nil
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        overlayManager.dismiss()
    }

    private func beginRecording(triggerMode: RecordingTriggerMode) {
        os_log(.info, log: recordingLog, "beginRecording() entered")
        clearPendingOverlayDismissToken()
        errorMessage = nil

        isRecording = true
        statusText = "Starting..."

        // Show initializing dots only if engine takes longer than 0.2s to start
        var overlayShown = false
        cancelRecordingInitializationTimer()
        let initTimer = DispatchSource.makeTimerSource(queue: .main)
        recordingInitializationTimer = initTimer
        initTimer.schedule(deadline: .now() + 0.2)
        initTimer.setEventHandler { [weak self] in
            guard let self, !overlayShown else { return }
            overlayShown = true
            os_log(.info, log: recordingLog, "engine slow — showing initializing overlay")
            self.clearPendingOverlayDismissToken()
            self.overlayManager.showInitializing(
                mode: self.activeRecordingTriggerMode ?? triggerMode,
                isCommandMode: self.currentSessionIntent.isCommandMode
            )
        }
        initTimer.resume()

        // Transition to waveform when first real audio arrives (any non-zero RMS)
        let deviceUID = selectedMicrophoneID
        audioRecorder.onRecordingReady = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                os_log(.info, log: recordingLog, "first real audio — transitioning to waveform")
                self.statusText = "Recording..."
                self.clearPendingOverlayDismissToken()
                if overlayShown {
                    self.overlayManager.transitionToRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        isCommandMode: self.currentSessionIntent.isCommandMode
                    )
                } else {
                    self.overlayManager.showRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        isCommandMode: self.currentSessionIntent.isCommandMode
                    )
                }
                overlayShown = true
                self.playAlertSound(named: "Tink")
            }
        }
        audioRecorder.onRecordingFailure = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                self.handleRecordingFailure(error)
            }
        }

        // Start engine on background thread so UI isn't blocked
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                try self.audioRecorder.startRecording(deviceUID: deviceUID)
                os_log(.info, log: recordingLog, "audioRecorder.startRecording() done: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                DispatchQueue.main.async {
                    guard self.isRecording, self.activeRecordingTriggerMode != nil else { return }
                    self.startContextCapture()
                    self.audioLevelCancellable = self.audioRecorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] level in
                            self?.overlayManager.updateAudioLevel(level)
                        }
                }
            } catch {
                DispatchQueue.main.async {
                    self.cancelRecordingInitializationTimer()
                    guard self.isRecording || self.activeRecordingTriggerMode != nil else { return }
                    self.handleRecordingFailure(error)
                }
            }
        }
    }

    private func handleRecordingFailure(_ error: Error) {
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        audioRecorder.cleanup()
        isRecording = false
        isTranscribing = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribingIndicatorTask?.cancel()
        transcribingIndicatorTask = nil
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        shortcutSessionController.reset()
        errorMessage = formattedRecordingStartError(error)
        statusText = "Error"
        overlayManager.dismiss()
        refreshAvailableMicrophonesIfNeeded()
    }

    private func formattedRecordingStartError(_ error: Error) -> String {
        if let recorderError = error as? AudioRecorderError {
            return "Failed to start recording: \(recorderError.localizedDescription)"
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("operation couldn't be completed") || lower.contains("operation could not be completed") {
            return "Failed to start recording: Audio input error. Verify microphone access is granted and a working mic is selected in System Settings > Sound > Input."
        }

        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            return "Failed to start recording (audio subsystem error \(nsError.code)). Check microphone permissions and selected input device."
        }

        return "Failed to start recording: \(error.localizedDescription)"
    }

    func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "WP Workspace cannot record audio without Microphone access.\n\nGo to System Settings > Privacy & Security > Microphone and enable WP Workspace."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }

    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "WP Workspace cannot type transcriptions without Accessibility access.\n\nGo to System Settings > Privacy & Security > Accessibility and enable WP Workspace."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    func playAlertSound(named name: String) {
        guard alertSoundsEnabled else { return }

        let sound = NSSound(named: name)
        sound?.volume = soundVolume
        sound?.play()
    }

    func previewWordPressAgentVoice() {
        speakWordPressAgentText("This is the WordPress Agent voice.")
    }

    private func deliverWordPressAgentNotification(reply: String, conversationID: String?) {
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmedReply.isEmpty ? "The WordPress Agent finished." : trimmedReply
        let content = UNMutableNotificationContent()
        content.title = "WordPress Agent"
        content.body = String(body.prefix(240))
        content.sound = alertSoundsEnabled ? .default : nil
        if let conversationID {
            content.userInfo = ["conversationID": conversationID]
        }

        let request = UNNotificationRequest(
            identifier: "wordpress-agent-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }

        speakWordPressAgentReply(body)
    }

    private func speakWordPressAgentReply(_ reply: String) {
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldSpeakWordPressAgentReplies, !trimmedReply.isEmpty else { return }

        speakWordPressAgentText(trimmedReply)
    }

    private func speakWordPressAgentText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        stopCurrentWordPressAgentSpeech()

        switch wordpressAgentSpeechProvider {
        case .system:
            speakWordPressAgentTextWithSystemVoice(trimmedText)
        case .elevenLabs:
            speakWordPressAgentTextWithElevenLabs(trimmedText)
        }
    }

    private func stopCurrentWordPressAgentSpeech() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        elevenLabsSpeechTask?.cancel()
        elevenLabsSpeechTask = nil
        elevenLabsAudioPlayer?.stop()
        elevenLabsAudioPlayer = nil
    }

    private func speakWordPressAgentTextWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: String(text.prefix(1200)))
        if !selectedWordPressAgentVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedWordPressAgentVoiceIdentifier) {
            utterance.voice = voice
        }
        speechSynthesizer.speak(utterance)
    }

    private func speakWordPressAgentTextWithElevenLabs(_ text: String) {
        guard let apiKey = elevenLabsAPIKey() else {
            elevenLabsStatusMessage = ElevenLabsClientError.missingAPIKey.localizedDescription
            return
        }

        let voiceID = selectedElevenLabsVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voiceID.isEmpty else {
            elevenLabsStatusMessage = ElevenLabsClientError.missingVoice.localizedDescription
            return
        }

        let spokenText = String(text.prefix(1200))
        elevenLabsSpeechTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData = try await self.elevenLabsClient.synthesizeSpeech(
                    text: spokenText,
                    voiceID: voiceID,
                    apiKey: apiKey
                )
                try Task.checkCancellation()
                await MainActor.run {
                    do {
                        let player = try AVAudioPlayer(data: audioData)
                        self.elevenLabsAudioPlayer = player
                        player.prepareToPlay()
                        player.play()
                        self.elevenLabsStatusMessage = "Playing ElevenLabs voice."
                    } catch {
                        self.elevenLabsStatusMessage = error.localizedDescription
                        self.errorMessage = error.localizedDescription
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.elevenLabsStatusMessage = error.localizedDescription
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopAndTranscribe() {
        cancelPendingShortcutStart()
        cancelRecordingInitializationTimer()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        let sessionIntent = currentSessionIntent
        let sessionSiteID = currentSessionWordPressComSiteID
        let sessionWordPressAgentEnabled = isWordPressAgentEnabled
        let sessionWordPressAgentConversationKey = currentSessionWordPressAgentConversationKey
        let sessionWordPressAgentConversationID = currentSessionWordPressAgentConversationID
        let sessionShouldOpenWordPressAgentWindowOnCompletion =
            currentSessionShouldOpenWordPressAgentWindowOnCompletion
        currentSessionIntent = .dictation
        currentSessionWordPressComSiteID = nil
        currentSessionWordPressAgentConversationKey = nil
        currentSessionWordPressAgentConversationID = nil
        currentSessionShouldOpenWordPressAgentWindowOnCompletion = false
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        debugStatusMessage = "Preparing audio"
        let sessionContext = capturedContext
        let inFlightContextTask = contextCaptureTask
        capturedContext = nil
        contextCaptureTask = nil
        lastRawTranscript = ""
        lastPostProcessedTranscript = ""
        lastContextSummary = ""
        lastPostProcessingStatus = ""
        lastPostProcessingPrompt = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "No screenshot"
        isRecording = false
        isTranscribing = true
        statusText = "Preparing audio..."
        errorMessage = nil
        playAlertSound(named: "Pop")
        overlayManager.prepareForTranscribing()
        audioRecorder.stopRecording { [weak self] fileURL in
            guard let self else { return }
            guard let fileURL else {
                self.isTranscribing = false
                self.audioRecorder.cleanup()
                self.errorMessage = "No audio recorded"
                self.statusText = "Error"
                self.overlayManager.dismiss()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }

            self.statusText = "Transcribing..."
            self.debugStatusMessage = "Transcribing audio"

            self.transcribingIndicatorTask?.cancel()
            let indicatorDelay = self.transcribingIndicatorDelay
            self.transcribingIndicatorTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(indicatorDelay * 1_000_000_000))
                    let shouldShowTranscribing = self?.isTranscribing ?? false
                    guard shouldShowTranscribing else { return }
                    await MainActor.run { [weak self] in
                        self?.overlayManager.showTranscribing()
                    }
                } catch {}
            }

            self.transcriptionTask?.cancel()
            self.transcriptionTask = Task {
                do {
                    let appContext: AppContext
                    if let sessionContext {
                        appContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        appContext = inFlightContext
                    } else {
                        appContext = self.fallbackContextAtStop()
                    }
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        self?.debugStatusMessage = "Calling WordPress.com"
                    }
                    let response = try await self.transcribeWithWordPressCom(
                        fileURL: fileURL,
                        intent: sessionIntent,
                        context: appContext,
                        siteID: sessionSiteID,
                        enableWordPressAgent: sessionWordPressAgentEnabled && sessionWordPressAgentConversationKey == nil,
                        saveArtifact: self.saveTranscriptionArtifacts
                    )
                    try Task.checkCancellation()

                    var agentReply: WordPressAgentTurnResult?
                    let shouldOpenWordPressAgentWindowBeforeAgentReply =
                        sessionShouldOpenWordPressAgentWindowOnCompletion
                            && sessionWordPressAgentConversationID != nil
                    if let sessionWordPressAgentConversationKey {
                        let agentMessage = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !agentMessage.isEmpty {
                            await MainActor.run { [weak self] in
                                guard let self, self.isTranscribing else { return }
                                self.statusText = "Asking WordPress Agent..."
                                self.debugStatusMessage = "Calling WordPress Agent"
                                self.lastAgentResponse = ""
                            }
                            if shouldOpenWordPressAgentWindowBeforeAgentReply,
                               let sessionWordPressAgentConversationID {
                                await MainActor.run { [weak self] in
                                    self?.showWordPressAgentWindow(conversationID: sessionWordPressAgentConversationID)
                                }
                            }
                            agentReply = try await self.callWordPressAgentMessage(
                                message: agentMessage,
                                key: sessionWordPressAgentConversationKey,
                                context: appContext
                            )
                            try Task.checkCancellation()
                        }
                    } else if sessionWordPressAgentEnabled,
                       response.status == "agent_requested",
                       let agent = response.agent {
                        let agentSiteID = response.siteID
                            ?? sessionSiteID
                            ?? self.effectiveWordPressComSiteID(for: appContext.bundleIdentifier)
                        guard let agentSiteID else {
                            throw WPCOMClientError.missingSelectedSite
                        }
                        await MainActor.run { [weak self] in
                            guard let self, self.isTranscribing else { return }
                            self.statusText = "Asking WordPress Agent..."
                            self.debugStatusMessage = "Calling WordPress Agent"
                            self.lastAgentResponse = ""
                        }
                        agentReply = try await self.callWordPressAgent(
                            agent: agent,
                            siteID: agentSiteID,
                            context: appContext
                        )
                        try Task.checkCancellation()
                    }

                    let completedAgentReply = agentReply
                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.lastContextSummary = appContext.contextSummary
                        self.lastContextScreenshotDataURL = appContext.screenshotDataURL
                        self.lastContextScreenshotStatus = self.contextScreenshotStatus(for: appContext)
                        let trimmedRawTranscript = response.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedFinalTranscript = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        var processingStatus = response.status
                        if let detectedIntent = response.detectedIntent {
                            processingStatus += " (\(detectedIntent))"
                        }
                        if !response.warnings.isEmpty {
                            processingStatus += " (" + response.warnings.joined(separator: ", ") + ")"
                        }
                        var postProcessingPrompt = response.skillID.map { "WordPress.com transcribe skill #\($0)" } ?? ""
                        if response.skillCreated {
                            postProcessingPrompt += postProcessingPrompt.isEmpty
                                ? "WordPress.com created transcribe skill"
                                : " (created during request)"
                        }
                        if let artifactID = response.artifactID {
                            postProcessingPrompt += postProcessingPrompt.isEmpty
                                ? "WordPress.com saved transcription artifact #\(artifactID)"
                                : " (artifact #\(artifactID))"
                        }

                        self.lastPostProcessingPrompt = postProcessingPrompt
                        self.lastRawTranscript = trimmedRawTranscript
                        self.lastPostProcessedTranscript = trimmedFinalTranscript
                        self.lastPostProcessingStatus = processingStatus
                        self.transcriptionTask = nil
                        self.transcribingIndicatorTask?.cancel()
                        self.transcribingIndicatorTask = nil
                        self.lastTranscript = trimmedFinalTranscript
                        self.isTranscribing = false
                        self.debugStatusMessage = "Done"
                        let completionStatusText = self.preserveClipboard ? "Pasted at cursor!" : "Copied to clipboard!"

                        if let agentReply = completedAgentReply {
                            let reply = agentReply.response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.lastAgentResponse = reply
                            self.lastTranscript = ""
                            self.lastPostProcessedTranscript = reply
                            self.lastPostProcessingStatus = "WordPress Agent \(agentReply.response.state)"
                            self.statusText = reply.isEmpty ? "WordPress Agent finished" : "WordPress Agent replied"
                            self.clearPendingOverlayDismissToken()
                            self.overlayManager.dismiss()
                            self.deliverWordPressAgentNotification(
                                reply: reply,
                                conversationID: agentReply.conversationID
                            )
                            if sessionShouldOpenWordPressAgentWindowOnCompletion
                                && !shouldOpenWordPressAgentWindowBeforeAgentReply {
                                self.showWordPressAgentWindow(conversationID: agentReply.conversationID)
                            }
                        } else if trimmedFinalTranscript.isEmpty {
                            self.statusText = "Nothing to transcribe"
                            self.clearPendingOverlayDismissToken()
                            self.overlayManager.dismiss()
                        } else {
                            self.statusText = completionStatusText
                            self.clearPendingOverlayDismissToken()
                            self.overlayManager.dismiss()

                            let pendingClipboardRestore = self.writeTranscriptToPasteboard(trimmedFinalTranscript)
                            self.pasteAtCursorWhenShortcutReleased {
                                self.restoreClipboardIfNeeded(pendingClipboardRestore)
                            }
                        }

                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()
                        Task { await self.discoverTranscribeSkillForSelectedSite() }

                        self.scheduleReadyStatusReset(
                            after: 3,
                            matching: [completionStatusText, "Nothing to transcribe", "WordPress Agent replied", "WordPress Agent finished"]
                        )
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.transcriptionTask = nil
                    }
                } catch {
                    let resolvedContext: AppContext
                    if let sessionContext {
                        resolvedContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        resolvedContext = inFlightContext
                    } else {
                        resolvedContext = self.fallbackContextAtStop()
                    }
                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.transcriptionTask = nil
                        self.transcribingIndicatorTask?.cancel()
                        self.transcribingIndicatorTask = nil
                        self.errorMessage = error.localizedDescription
                        self.isTranscribing = false
                        self.statusText = "Error"
                        self.overlayManager.dismiss()
                        self.lastPostProcessedTranscript = ""
                        self.lastRawTranscript = ""
                        self.lastContextSummary = ""
                        self.lastPostProcessingStatus = "Error: \(error.localizedDescription)"
                        self.lastPostProcessingPrompt = ""
                        self.lastContextScreenshotDataURL = resolvedContext.screenshotDataURL
                        self.lastContextScreenshotStatus = self.contextScreenshotStatus(for: resolvedContext)
                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()
                    }
                }
            }
        }
    }

    private func startContextCapture() {
        contextCaptureTask?.cancel()
        capturedContext = nil
        lastContextSummary = "Collecting app context..."
        lastPostProcessingStatus = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "No screenshot"

        contextCaptureTask = Task { [weak self] in
            guard let self else { return nil }
            let context = await self.contextService.collectContext()
            await MainActor.run {
                self.capturedContext = context
                self.lastContextSummary = context.contextSummary
                self.lastContextScreenshotDataURL = context.screenshotDataURL
                self.lastContextScreenshotStatus = self.contextScreenshotStatus(for: context)
                self.lastPostProcessingStatus = "App context captured"
            }
            return context
        }
    }

    private func contextScreenshotStatus(for context: AppContext) -> String {
        if let error = context.screenshotError {
            return error
        }

        if context.screenshotDataURL != nil {
            return "available (\(context.screenshotMimeType ?? "image"))"
        }

        return "No screenshot"
    }

    private func fallbackContextAtStop() -> AppContext {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let windowTitle = focusedWindowTitle(for: frontmostApp)
        return AppContext(
            appName: frontmostApp?.localizedName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: nil,
            currentActivity: "Could not refresh app context at stop time; using text-only app context.",
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )
    }

    private func focusedWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return focusedWindowTitle(from: appElement)
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        guard let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) else {
            return nil
        }

        return trimmedText(windowTitle)
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private func trimmedText(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    func toggleDebugOverlay() {
        if isDebugOverlayActive {
            stopDebugOverlay()
        } else {
            startDebugOverlay()
        }
    }

    private func startDebugOverlay() {
        isDebugOverlayActive = true
        clearPendingOverlayDismissToken()
        overlayManager.showRecording()

        // Simulate audio levels with a timer
        var phase: Double = 0.0
        debugOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            phase += 0.15
            // Generate a fake audio level that oscillates like speech
            let base = 0.3 + 0.2 * sin(phase)
            let noise = Float.random(in: -0.15...0.15)
            let level = min(max(Float(base) + noise, 0.0), 1.0)
            self.overlayManager.updateAudioLevel(level)
        }
    }

    private func stopDebugOverlay() {
        debugOverlayTimer?.invalidate()
        debugOverlayTimer = nil
        isDebugOverlayActive = false
        clearPendingOverlayDismissToken()
        overlayManager.dismiss()
    }

    private func clearPendingOverlayDismissToken() {
        pendingOverlayDismissToken = nil
    }

    private func scheduleOverlayDismissAfterFailureIndicator(after delay: TimeInterval) {
        let dismissToken = UUID()
        pendingOverlayDismissToken = dismissToken
        overlayManager.showFailureIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pendingOverlayDismissToken == dismissToken else { return }
            self.pendingOverlayDismissToken = nil
            self.overlayManager.dismiss()
        }
    }

    func toggleDebugPanel() {
        selectedSettingsTab = .permissions
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    private func pasteAtCursor() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }

    private func writeTranscriptToPasteboard(_ transcript: String) -> PendingClipboardRestore? {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PreservedPasteboardSnapshot(pasteboard: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)

        guard let snapshot else { return nil }
        return PendingClipboardRestore(snapshot: snapshot, expectedChangeCount: pasteboard.changeCount)
    }

    private func restoreClipboardIfNeeded(_ pendingRestore: PendingClipboardRestore?) {
        guard let pendingRestore else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == pendingRestore.expectedChangeCount else { return }
            pendingRestore.snapshot.restore(to: pasteboard)
        }
    }

    private func pasteAtCursorWhenShortcutReleased(attempt: Int = 0, completion: (() -> Void)? = nil) {
        let maxAttempts = 24
        if hotkeyManager.hasPressedShortcutInputs && attempt < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.pasteAtCursorWhenShortcutReleased(attempt: attempt + 1, completion: completion)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.pasteAtCursor()
            completion?()
        }
    }

    private func cancelRecordingInitializationTimer() {
        recordingInitializationTimer?.cancel()
        recordingInitializationTimer = nil
    }

    private func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if let statuses, !statuses.contains(self.statusText) {
                return
            }
            self.statusText = "Ready"
        }
    }
}
