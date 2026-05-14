import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct WordPressAgentWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var draftMessage = ""
    @State private var pendingImageURLs: [URL] = []
    @State private var sidebarSearch = ""
    @AppStorage("wordpress_agent_starred_sites_expanded") private var isStarredSitesExpanded = true
    @AppStorage("wordpress_agent_all_sites_expanded") private var isAllSitesExpanded = false
    @State private var shouldRestoreComposerFocusAfterSend = false
    @State private var previewSidebarWidth: CGFloat = 520
    @State private var previewSidebarResizeStartWidth: CGFloat?
    @State private var composerTextHeight: CGFloat = 24
    @FocusState private var isComposerFocused: Bool

    private let workspaceMinimumWidth: CGFloat = 360
    private let previewMinimumWidth: CGFloat = 320
    private static let pasteableImageContentTypes: [UTType] = [.fileURL, .image]

    private var selectedConversation: WordPressAgentConversation? {
        appState.selectedWordPressAgentConversation
    }

    private var activeSiteID: Int? {
        if let selectedConversation {
            let siteID = selectedConversation.key.siteID
            return siteID > 0 ? siteID : nil
        }
        return appState.selectedWordPressComSiteID
    }

    private var activeSite: WPCOMSite? {
        guard let activeSiteID else {
            return selectedConversation == nil ? appState.selectedWordPressComSite : nil
        }
        if let site = appState.wordpressComSites.first(where: { $0.id == activeSiteID }) {
            return site
        }
        return selectedConversation == nil ? appState.selectedWordPressComSite : nil
    }

    private var activeWorkspaceTitle: String {
        activeSite?.displayName ?? selectedConversation?.title ?? "WordPress Agent"
    }

    private var normalizedSearch: String {
        sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var siteByID: [Int: WPCOMSite] {
        Dictionary(uniqueKeysWithValues: appState.wordpressComSites.map { ($0.id, $0) })
    }

    private var starredSites: [WPCOMSite] {
        let sitesByID = siteByID
        return appState.starredWordPressAgentSiteIDs.compactMap { sitesByID[$0] }
    }

    private var visibleStarredSites: [WPCOMSite] {
        guard !normalizedSearch.isEmpty else { return starredSites }
        return starredSites.filter(siteMatchesSearch)
    }

    private var allSites: [WPCOMSite] {
        return appState.wordpressComSites
            .filter { normalizedSearch.isEmpty || siteMatchesSearch($0) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var shouldShowDropdownSites: Bool {
        isAllSitesExpanded || !normalizedSearch.isEmpty
    }

    private var isSelectedConversationSending: Bool {
        selectedConversation?.isSending == true
    }

    private var allSitesCount: Int {
        normalizedSearch.isEmpty ? appState.wordpressComSites.count : allSites.count
    }

    private var starredSitesCount: Int {
        normalizedSearch.isEmpty ? starredSites.count : visibleStarredSites.count
    }

    private var shouldShowStarredSites: Bool {
        isStarredSitesExpanded || !normalizedSearch.isEmpty
    }

    private func siteMatchesSearch(_ site: WPCOMSite) -> Bool {
        site.displayName.localizedCaseInsensitiveContains(normalizedSearch)
        || (site.slug ?? "").localizedCaseInsensitiveContains(normalizedSearch)
        || (site.url ?? "").localizedCaseInsensitiveContains(normalizedSearch)
    }

    private var visibleConversations: [WordPressAgentConversation] {
        let conversations = appState.sortedWordPressAgentConversations.filter { !$0.isEmptyLocalDraft }
        guard !normalizedSearch.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(normalizedSearch)
                || conversation.key.agentID.localizedCaseInsensitiveContains(normalizedSearch)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(normalizedSearch) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 292)

            Rectangle()
                .fill(AgentPalette.separator)
                .frame(width: 1)

            contentArea
        }
        .background(AgentPalette.workspace)
        .frame(minWidth: appState.wordpressAgentPreview == nil ? 900 : 1120, minHeight: 620)
        .task {
            appState.seedDefaultWordPressAgentStarredSiteIfNeeded()
            await appState.refreshWordPressAgentConversationsIfNeeded()
            appState.seedDefaultWordPressAgentStarredSiteIfNeeded()
        }
        .onChange(of: appState.selectedWordPressComSiteID) { _ in
            appState.seedDefaultWordPressAgentStarredSiteIfNeeded()
        }
        .onChange(of: appState.wordpressComSites) { _ in
            appState.seedDefaultWordPressAgentStarredSiteIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                sidebarTitleBar
                sidebarSearchField
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    sitesSection
                    conversationsSection
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }

            accountFooter
        }
        .background(AgentPalette.sidebar)
    }

    private var sidebarTitleBar: some View {
        HStack(spacing: 10) {
            WordPressComLogoMark()
                .frame(width: 26, height: 26)

            Text("WordPress Agent")
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button {
                _ = appState.startWordPressAgentConversation(siteID: activeSiteID)
                isComposerFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Start agent session")
            .disabled(activeSiteID == nil)
        }
    }

    private var sidebarSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search", text: $sidebarSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AgentPalette.searchField)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AgentPalette.controlStroke, lineWidth: 1)
                )
        )
    }

    private var sitesSection: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            starredSitesDropdown

            if appState.isWordPressComSignedIn {
                allSitesDropdown
            }
        }
    }

    private var starredSitesDropdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isStarredSitesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: shouldShowStarredSites ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)

                    Text("Starred")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Text("\(starredSitesCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if shouldShowStarredSites {
                if visibleStarredSites.isEmpty {
                    SidebarEmptyText(starredEmptyText)
                        .padding(.horizontal, 8)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleStarredSites) { site in
                            SiteSidebarRow(
                                site: site,
                                isSelected: site.id == activeSiteID,
                                isStarred: appState.isWordPressAgentSiteStarred(site.id),
                                onSelect: {
                                    appState.selectWordPressAgentSite(site.id)
                                    isComposerFocused = true
                                },
                                onToggleStar: {
                                    appState.toggleWordPressAgentSiteStar(site.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var starredEmptyText: String {
        if !appState.isWordPressComSignedIn {
            return "Sign in to WordPress.com"
        }
        return normalizedSearch.isEmpty ? "No starred sites" : "No starred matching sites"
    }

    private var allSitesDropdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isAllSitesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: shouldShowDropdownSites ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)

                    Text(normalizedSearch.isEmpty ? "All Sites" : "Matching Sites")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Text("\(allSitesCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if shouldShowDropdownSites {
                if allSites.isEmpty {
                    SidebarEmptyText("No matching sites")
                        .padding(.horizontal, 8)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(allSites) { site in
                            SiteSidebarRow(
                                site: site,
                                isSelected: site.id == activeSiteID,
                                isStarred: appState.isWordPressAgentSiteStarred(site.id),
                                onSelect: {
                                    appState.selectWordPressAgentSite(site.id)
                                    isComposerFocused = true
                                },
                                onToggleStar: {
                                    appState.toggleWordPressAgentSiteStar(site.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var conversationsSection: some View {
        let conversations = visibleConversations

        return VStack(alignment: .leading, spacing: 6) {
            SidebarSectionHeader(title: "Recent")

            if conversations.isEmpty {
                if appState.isRefreshingWordPressAgentConversations {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        SidebarEmptyText("Loading conversations...")
                    }
                    .padding(.horizontal, 8)
                } else {
                    SidebarEmptyText(appState.wordpressAgentHistoryStatusMessage ?? "No conversations")
                        .padding(.horizontal, 8)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(conversations) { conversation in
                        Button {
                            appState.selectWordPressAgentConversation(conversation.id)
                            appState.selectedWordPressComSiteID = conversation.key.siteID
                            isComposerFocused = true
                        } label: {
                            ConversationSidebarRow(
                                conversation: conversation,
                                site: site(for: conversation.key.siteID),
                                isSelected: conversation.id == selectedConversation?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if normalizedSearch.isEmpty {
                        conversationPaginationRow
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var conversationPaginationRow: some View {
        Button {
            if !appState.isLoadingMoreWordPressAgentConversations {
                appState.loadMoreWordPressAgentConversationsFromUI()
            }
        } label: {
            HStack(spacing: 8) {
                if appState.isLoadingMoreWordPressAgentConversations {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(appState.isLoadingMoreWordPressAgentConversations
                    ? "Loading previous conversations..."
                    : "Load previous conversations")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AgentPalette.softControl.opacity(
                        appState.isLoadingMoreWordPressAgentConversations ? 0.72 : 0.55
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isRefreshingWordPressAgentConversations
            || appState.isLoadingMoreWordPressAgentConversations)
    }

    private var accountFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AgentPalette.separator)
                .frame(height: 1)

            Button {
                appState.selectedSettingsTab = .wordpressCom
                NotificationCenter.default.post(name: .showSettings, object: nil)
            } label: {
                HStack(spacing: 10) {
                    RemoteAvatar(
                        url: appState.wordpressComUser?.avatarURL,
                        fallbackText: appState.wordpressComUser?.displayLabel ?? "WP",
                        size: 32
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.wordpressComUser?.displayLabel ?? "WordPress.com")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        Text(accountSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var accountSubtitle: String {
        if let username = appState.wordpressComUser?.username,
           !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "@\(username)"
        }
        if let email = appState.wordpressComUser?.email,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        return appState.isWordPressComSignedIn ? "Connected" : "Not signed in"
    }

    @ViewBuilder
    private var contentArea: some View {
        if let preview = appState.wordpressAgentPreview {
            GeometryReader { geometry in
                let maximumPreviewWidth = max(
                    previewMinimumWidth,
                    geometry.size.width - workspaceMinimumWidth - PreviewResizeHandle.width
                )
                let resolvedPreviewWidth = clampedPreviewSidebarWidth(maximumPreviewWidth: maximumPreviewWidth)

                HStack(spacing: 0) {
                    workspace
                        .frame(
                            width: max(
                                workspaceMinimumWidth,
                                geometry.size.width - resolvedPreviewWidth - PreviewResizeHandle.width
                            )
                        )

                    PreviewResizeHandle(
                        onDragChanged: { translationX in
                            if previewSidebarResizeStartWidth == nil {
                                previewSidebarResizeStartWidth = resolvedPreviewWidth
                            }
                            let startWidth = previewSidebarResizeStartWidth ?? resolvedPreviewWidth
                            let nextWidth = min(
                                max(startWidth - translationX, previewMinimumWidth),
                                maximumPreviewWidth
                            )
                            if abs(nextWidth - previewSidebarWidth) >= 6 {
                                previewSidebarWidth = nextWidth
                            }
                        },
                        onDragEnded: {
                            previewSidebarWidth = clampedPreviewSidebarWidth(
                                maximumPreviewWidth: maximumPreviewWidth
                            )
                            previewSidebarResizeStartWidth = nil
                        }
                    )

                    WordPressAgentPreviewPanel(
                        preview: preview,
                        onClose: {
                            Task { @MainActor in
                                appState.closeWordPressAgentPreview()
                            }
                        },
                        onPageUpdate: { previewID, currentURL, title, isLoading in
                            Task { @MainActor in
                                appState.updateWordPressAgentPreviewPage(
                                    previewID: previewID,
                                    currentURL: currentURL,
                                    title: title,
                                    isLoading: isLoading
                                )
                            }
                        }
                    )
                    .frame(width: resolvedPreviewWidth)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            workspace
        }
    }

    private func clampedPreviewSidebarWidth(maximumPreviewWidth: CGFloat) -> CGFloat {
        min(max(previewSidebarWidth, previewMinimumWidth), maximumPreviewWidth)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            WordPressAgentTranscriptView(
                conversation: selectedConversation,
                activeSite: activeSite,
                activeWorkspaceTitle: activeWorkspaceTitle,
                isSignedIn: appState.isWordPressComSignedIn
            )
            .equatable()
            composer
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentPalette.workspace)
        .environment(\.openURL, OpenURLAction { url in
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                NSWorkspace.shared.open(WordPressAgentPreviewURLResolver.defaultOpenURL(forPossiblyBare: url) ?? url)
                return .handled
            }

            guard let previewURL = WordPressAgentPreviewURLResolver.previewURL(forPossiblyBare: url) else {
                NSWorkspace.shared.open(WordPressAgentPreviewURLResolver.defaultOpenURL(forPossiblyBare: url) ?? url)
                return .handled
            }

            Task { @MainActor in
                appState.openWordPressAgentPreview(url: previewURL)
            }
            return .handled
        })
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            Button {
                _ = appState.startWordPressAgentConversation(siteID: activeSiteID)
                isComposerFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Start agent session")
            .disabled(activeSiteID == nil)

            AgentHeaderPill(
                site: activeSite,
                conversation: selectedConversation
            )

            if selectedConversation?.isSending == true {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }

            Spacer()

            Button {
                openActiveSite()
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(activeSite?.url == nil ? .tertiary : .secondary)
            .help("Open site")
            .disabled(activeSite?.url == nil)
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 14) {
            if let activeSite {
                RemoteSiteIcon(site: activeSite, size: 54, cornerRadius: 14)
            } else {
                WordPressComLogoMark()
                    .frame(width: 54, height: 54)
            }

            Text(activeWorkspaceTitle)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(appState.isWordPressComSignedIn ? "New chat" : "WordPress.com sign-in needed")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                if !pendingImageURLs.isEmpty {
                    ComposerAttachmentStrip(fileURLs: pendingImageURLs) { url in
                        pendingImageURLs.removeAll { $0 == url }
                    }
                }

                composerTextView

                HStack(spacing: 10) {
                    Button {
                        selectImages()
                        isComposerFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .regular))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add images")
                    .disabled(isComposerDisabled)

                    Spacer()

                    Button {
                        appState.toggleRecording()
                    } label: {
                        Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.isRecording ? .red : .secondary)
                    .help(appState.isRecording ? "Stop recording" : "Dictate")
                    .disabled(activeSiteID == nil || appState.isTranscribing)

                    Button {
                        sendDraftMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSendMessage ? AgentPalette.primaryActionIcon : AgentPalette.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(canSendMessage ? AgentPalette.primaryActionFill : AgentPalette.disabledControl)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Send")
                    .disabled(!canSendMessage)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AgentPalette.composer)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AgentPalette.controlStroke, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 820)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .padding(.top, 8)
        }
        .onChange(of: isSelectedConversationSending) { isSending in
            guard shouldRestoreComposerFocusAfterSend else { return }
            restoreComposerFocusSoon(clearPending: !isSending)
        }
        .onChange(of: appState.wordpressAgentPreview?.id) { _ in
            guard shouldRestoreComposerFocusAfterSend else { return }
            restoreComposerFocusSoon(clearPending: false)
        }
        .onPasteCommand(of: Self.pasteableImageContentTypes) { _ in
            pasteImagesFromClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteImageIntoWordPressAgentComposer)) { notification in
            guard isComposerFocused,
                  let request = notification.object as? WordPressAgentComposerPasteRequest else {
                return
            }
            request.handled = pasteImagesFromClipboardIfAvailable()
        }
    }

    private var canSendMessage: Bool {
        (Self.containsNonWhitespace(draftMessage) || !pendingImageURLs.isEmpty)
        && !isComposerDisabled
    }

    private var isComposerDisabled: Bool {
        activeSiteID == nil
        || selectedConversation?.isSending == true
        || appState.isTranscribing
    }

    private var isComposerInputDisabled: Bool {
        activeSiteID == nil || appState.isTranscribing
    }

    private var composerTextView: some View {
        ZStack(alignment: .topLeading) {
            AgentComposerTextView(
                text: $draftMessage,
                isFocused: Binding(
                    get: { isComposerFocused },
                    set: { isComposerFocused = $0 }
                ),
                height: $composerTextHeight,
                fontSize: 16,
                minimumHeight: 24,
                maximumHeight: 220,
                isDisabled: isComposerInputDisabled,
                onSubmit: sendDraftMessage
            )
            .frame(height: composerTextHeight)

            if draftMessage.isEmpty {
                Text("Ask WordPress Agent")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .onPasteCommand(of: Self.pasteableImageContentTypes) { _ in
            pasteImagesFromClipboard()
        }
    }

    private func sendDraftMessage() {
        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingImageURLs
        guard !trimmedMessage.isEmpty || !attachments.isEmpty else { return }
        let message = draftMessage
        draftMessage = ""
        pendingImageURLs = []
        guard appState.submitWordPressAgentComposerMessage(
            message,
            attachments: attachments,
            siteID: activeSiteID
        ) != nil else {
            draftMessage = message
            pendingImageURLs = attachments
            return
        }
        shouldRestoreComposerFocusAfterSend = true
        restoreComposerFocusSoon(clearPending: false)
    }

    private static func containsNonWhitespace(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace && !$0.isNewline }
    }

    private func restoreComposerFocusSoon(clearPending: Bool) {
        guard !isComposerInputDisabled else { return }

        DispatchQueue.main.async {
            isComposerFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !isComposerInputDisabled else { return }
            isComposerFocused = true
            if clearPending {
                shouldRestoreComposerFocusAfterSend = false
            }
        }
    }

    private func selectImages() {
        guard !isComposerDisabled else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }

        appendPendingImageURLs(panel.urls)
    }

    private func pasteImagesFromClipboard() {
        _ = pasteImagesFromClipboardIfAvailable()
    }

    private func pasteImagesFromClipboardIfAvailable() -> Bool {
        guard !isComposerDisabled else { return false }

        do {
            let pastedImageURLs = try Self.imageFileURLs(from: NSPasteboard.general)
            guard !pastedImageURLs.isEmpty else { return false }
            appendPendingImageURLs(pastedImageURLs)
            isComposerFocused = true
            return true
        } catch {
            showImagePasteError(error)
            return true
        }
    }

    private func appendPendingImageURLs(_ urls: [URL]) {
        var existingURLs = Set(pendingImageURLs)
        for url in urls where existingURLs.insert(url).inserted {
            pendingImageURLs.append(url)
        }
    }

    private static func imageFileURLs(from pasteboard: NSPasteboard) throws -> [URL] {
        let existingFileURLs = existingImageFileURLs(from: pasteboard)
        if !existingFileURLs.isEmpty {
            return existingFileURLs
        }

        return try writeImageDataFromPasteboard(pasteboard)
    }

    private static func existingImageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url
            }
            if let url = object as? NSURL {
                return url as URL
            }
            return nil
        }

        let legacyFileURLs = (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? [])
            .map(URL.init(fileURLWithPath:))

        let fileURLStringURLs = pasteboard.string(forType: .fileURL)
            .flatMap(URL.init(string:))
            .map { [$0] } ?? []

        var seenPaths = Set<String>()
        let uniqueURLs = (urls + legacyFileURLs + fileURLStringURLs).filter { url in
            guard url.isFileURL else { return false }
            return seenPaths.insert(url.standardizedFileURL.path).inserted
        }

        return ImageImportProcessor.supportedImageFileURLs(from: uniqueURLs)
    }

    private struct PasteboardImagePayload {
        let data: Data
        let fileExtension: String
    }

    private static func writeImageDataFromPasteboard(_ pasteboard: NSPasteboard) throws -> [URL] {
        var payloads = (pasteboard.pasteboardItems ?? []).compactMap(imagePayload)

        if payloads.isEmpty,
           let image = NSImage(pasteboard: pasteboard),
           let pngData = pngData(from: image) {
            payloads = [PasteboardImagePayload(data: pngData, fileExtension: "png")]
        }

        guard !payloads.isEmpty else { return [] }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WPWorkspacePastedImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try payloads.map { payload in
            let filename = "pasted-image-\(String(UUID().uuidString.prefix(8)).lowercased()).\(payload.fileExtension)"
            let url = directory.appendingPathComponent(filename)
            try payload.data.write(to: url, options: .atomic)
            return url
        }
    }

    private static func imagePayload(from item: NSPasteboardItem) -> PasteboardImagePayload? {
        let preferredTypes: [(NSPasteboard.PasteboardType, String)] = [
            (NSPasteboard.PasteboardType("public.png"), "png"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
            (NSPasteboard.PasteboardType("public.tiff"), "tiff"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
            (NSPasteboard.PasteboardType("org.webmproject.webp"), "webp")
        ]

        for (type, fileExtension) in preferredTypes {
            if let data = item.data(forType: type), !data.isEmpty {
                return PasteboardImagePayload(data: data, fileExtension: fileExtension)
            }
        }

        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func showImagePasteError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not paste image."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func site(for siteID: Int) -> WPCOMSite? {
        appState.wordpressComSites.first { $0.id == siteID }
    }

    private func openActiveSite() {
        guard let urlString = activeSite?.url,
              let url = URL(string: urlString) else { return }
        appState.openWordPressAgentPreview(url: url, title: activeSite?.displayName)
    }
}

private struct WordPressAgentPreviewPanel: View {
    let preview: WordPressAgentPreview
    let onClose: () -> Void
    let onPageUpdate: (UUID, URL?, String?, Bool) -> Void

    @State private var previewReloadTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close preview")

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text(preview.currentURL.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 10)

                Button {
                    previewReloadTrigger += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh preview")

                Button {
                    NSWorkspace.shared.open(preview.currentURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in browser")
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(Color(nsColor: .windowBackgroundColor))

            Rectangle()
                .fill(AgentPalette.separator)
                .frame(height: 1)

            WordPressAgentWebPreview(
                previewID: preview.id,
                url: preview.url,
                reloadTrigger: previewReloadTrigger,
                onPageUpdate: onPageUpdate
            )
                .id(preview.id)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PreviewResizeHandle: NSViewRepresentable {
    static let width: CGFloat = 14

    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> PreviewResizeHandleView {
        let view = PreviewResizeHandleView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 1))
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: PreviewResizeHandleView, context: Context) {
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }
}

private final class PreviewResizeHandleView: NSView {
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private var dragStartX: CGFloat?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PreviewResizeHandle.width, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStartX == nil else { return }
        isHovered = false
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        isHovered = true
        NSCursor.resizeLeftRight.set()
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let startX = dragStartX ?? currentX
        onDragChanged?(currentX - startX)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
        onDragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered || dragStartX != nil {
            let hoverFill = effectiveAppearance.isDarkMode
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.045)
            hoverFill.setFill()
            bounds.fill()
        }

        let separatorFill = effectiveAppearance.isDarkMode
            ? NSColor.white.withAlphaComponent(isHovered || dragStartX != nil ? 0.18 : 0.10)
            : NSColor.black.withAlphaComponent(isHovered || dragStartX != nil ? 0.18 : 0.10)
        separatorFill.setFill()
        NSRect(x: floor(bounds.midX), y: 0, width: 1, height: bounds.height).fill()

        NSColor.secondaryLabelColor
            .withAlphaComponent(isHovered || dragStartX != nil ? 0.7 : 0.4)
            .setFill()

        let gripHeight: CGFloat = 18
        let gripWidth: CGFloat = 3
        let gripSpacing: CGFloat = 3
        let totalHeight = (gripHeight * 3) + (gripSpacing * 2)
        let firstY = bounds.midY - (totalHeight / 2)
        for index in 0..<3 {
            let gripRect = NSRect(
                x: bounds.midX - (gripWidth / 2),
                y: firstY + (CGFloat(index) * (gripHeight + gripSpacing)),
                width: gripWidth,
                height: gripHeight
            )
            NSBezierPath(
                roundedRect: gripRect,
                xRadius: gripWidth / 2,
                yRadius: gripWidth / 2
            ).fill()
        }
    }
}

private struct WordPressAgentWebPreview: NSViewRepresentable {
    let previewID: UUID
    let url: URL
    let reloadTrigger: Int
    let onPageUpdate: (UUID, URL?, String?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(previewID: previewID, onPageUpdate: onPageUpdate)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.previewID = previewID
        context.coordinator.onPageUpdate = onPageUpdate
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.previewID = previewID
        context.coordinator.onPageUpdate = onPageUpdate
        context.coordinator.load(url, in: webView)
        context.coordinator.reloadIfNeeded(reloadTrigger, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var previewID: UUID
        var onPageUpdate: (UUID, URL?, String?, Bool) -> Void
        private var loadedURL: URL?
        private var lastReloadTrigger = 0
        private var lastReportedURL: URL?
        private var lastReportedTitle: String?
        private var lastReportedIsLoading: Bool?

        init(previewID: UUID, onPageUpdate: @escaping (UUID, URL?, String?, Bool) -> Void) {
            self.previewID = previewID
            self.onPageUpdate = onPageUpdate
        }

        func load(_ url: URL, in webView: WKWebView) {
            let previewURL = WordPressAgentPreviewURLResolver.previewURL(for: url) ?? url
            guard loadedURL != previewURL else { return }
            loadedURL = previewURL
            loadPreviewURL(previewURL, in: webView)
        }

        private func navigate(_ url: URL, in webView: WKWebView) {
            let previewURL = WordPressAgentPreviewURLResolver.previewURL(for: url) ?? url
            loadPreviewURL(previewURL, in: webView)
        }

        private func loadPreviewURL(_ previewURL: URL, in webView: WKWebView) {
            reportPageUpdate(url: previewURL, title: nil, isLoading: true)
            webView.load(URLRequest(url: previewURL))
        }

        func reloadIfNeeded(_ trigger: Int, in webView: WKWebView) {
            guard trigger != lastReloadTrigger else { return }
            lastReloadTrigger = trigger
            reportPageUpdate(webView, isLoading: true)
            webView.reloadFromOrigin()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            reportPageUpdate(webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            reportPageUpdate(webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reportPageUpdate(webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            reportPageUpdate(webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportPageUpdate(webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if Self.isWebKitInternalURL(url) {
                decisionHandler(.allow)
                return
            }

            if let previewURL = WordPressAgentPreviewURLResolver.previewURL(for: url) {
                if previewURL.absoluteString != url.absoluteString || navigationAction.targetFrame == nil {
                    decisionHandler(.cancel)
                    navigate(previewURL, in: webView)
                    return
                }

                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame?.isMainFrame != false {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                navigate(url, in: webView)
            } else {
                reportPageUpdate(webView, isLoading: true)
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func reportPageUpdate(_ webView: WKWebView, isLoading: Bool) {
            reportPageUpdate(url: webView.url, title: webView.title, isLoading: isLoading)
        }

        private func reportPageUpdate(url: URL?, title: String?, isLoading: Bool) {
            guard lastReportedURL != url
                || lastReportedTitle != title
                || lastReportedIsLoading != isLoading else {
                return
            }
            lastReportedURL = url
            lastReportedTitle = title
            lastReportedIsLoading = isLoading
            onPageUpdate(previewID, url, title, isLoading)
        }

        private static func isWebKitInternalURL(_ url: URL) -> Bool {
            switch url.scheme?.lowercased() {
            case nil, "about", "data", "blob", "javascript", "applewebdata":
                return true
            default:
                return false
            }
        }
    }
}

enum AgentPalette {
    static let sidebar = dynamicColor(
        light: NSColor(calibratedRed: 0.972, green: 0.958, blue: 0.974, alpha: 1),
        dark: NSColor(calibratedRed: 0.120, green: 0.116, blue: 0.128, alpha: 1)
    )
    static let sidebarSelection = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let workspace = Color(nsColor: .textBackgroundColor)
    static let composer = Color(nsColor: .windowBackgroundColor)
    static let softControl = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    static let searchField = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.72),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    static let separator = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let controlStroke = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let disabledControl = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let primaryActionFill = dynamicColor(
        light: .black,
        dark: .white
    )
    static let primaryActionIcon = dynamicColor(
        light: .white,
        dark: .black
    )
    static let starFill = dynamicColor(
        light: NSColor(calibratedRed: 0.86, green: 0.55, blue: 0.02, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.18, alpha: 1)
    )
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDarkMode ? dark : light
        })
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}

private struct SidebarEmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct SiteSidebarRow: View {
    let site: WPCOMSite
    let isSelected: Bool
    let isStarred: Bool
    let onSelect: () -> Void
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    RemoteSiteIcon(site: site, size: 24, cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(site.displayName)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(site.slug ?? readableHost(from: site.url) ?? "Site \(site.id)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isStarred ? AgentPalette.starFill : AgentPalette.secondaryText)
                    .frame(width: 28, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isStarred ? "Remove from Starred" : "Add to Starred")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AgentPalette.sidebarSelection : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func readableHost(from urlString: String?) -> String? {
        guard let urlString,
              let host = URL(string: urlString)?.host else {
            return nil
        }
        return host
    }
}

private struct ConversationSidebarRow: View {
    let conversation: WordPressAgentConversation
    let site: WPCOMSite?
    let isSelected: Bool

    private var title: String {
        if let firstUserMessage = conversation.messages.first(where: { $0.role == .user })?.text,
           let compactTitle = Self.compactTitle(from: firstUserMessage) {
            return compactTitle
        }
        return conversation.title
    }

    private var subtitle: String {
        site?.displayName ?? conversation.title
    }

    private var lastUpdatedText: String {
        Self.relativeTimestamp(from: conversation.lastUpdated)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let site {
                RemoteSiteIcon(site: site, size: 22, cornerRadius: 6)
                    .frame(width: 22, height: 22)
            } else {
                WordPressComLogoMark()
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AgentPalette.softControl.opacity(isSelected ? 0.65 : 0.42))
                        )

                    Text(lastUpdatedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 16)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AgentPalette.sidebarSelection : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private static func relativeTimestamp(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 {
            return "now"
        }

        let minute = 60.0
        let hour = 60.0 * minute
        let day = 24.0 * hour
        let month = 30.0 * day
        let year = 365.0 * day

        if interval < hour {
            return "\(max(1, Int(interval / minute))) min"
        }
        if interval < day {
            return "\(max(1, Int(interval / hour))) h"
        }
        if interval < month {
            return "\(max(1, Int(interval / day))) d"
        }
        if interval < year {
            return "\(max(1, Int(interval / month))) mo"
        }
        return "\(max(1, Int(interval / year))) y"
    }

    private static func compactTitle(from text: String) -> String? {
        var title = ""
        var previousWasWhitespace = false
        let limit = 140

        for character in text {
            if character.isWhitespace || character.isNewline {
                guard !title.isEmpty, !previousWasWhitespace else { continue }
                title.append(" ")
                previousWasWhitespace = true
            } else {
                title.append(character)
                previousWasWhitespace = false
            }

            if title.count >= limit {
                return title.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
            }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }
}

private struct AgentHeaderPill: View {
    let site: WPCOMSite?
    let conversation: WordPressAgentConversation?

    var body: some View {
        HStack(spacing: 9) {
            if let site {
                RemoteSiteIcon(site: site, size: 28, cornerRadius: 7)
            } else {
                WordPressComLogoMark()
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(site?.displayName ?? conversation?.title ?? "WordPress Agent")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)

                Text(conversation?.key.agentID ?? "dolly")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .frame(height: 48)
        .background(
            Capsule(style: .continuous)
                .fill(AgentPalette.softControl)
        )
    }
}

private struct ComposerAttachmentStrip: View {
    let fileURLs: [URL]
    let onRemove: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileURLs, id: \.self) { url in
                    ComposerAttachmentPill(fileURL: url) {
                        onRemove(url)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComposerAttachmentPill: View {
    let fileURL: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            LocalImageThumbnail(fileURL: fileURL, width: 32, height: 32, cornerRadius: 6)

            Text(fileURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove")
        }
        .padding(.leading, 4)
        .padding(.trailing, 7)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AgentPalette.softControl)
        )
    }
}

private struct SentAttachmentPreviewList: View {
    let attachments: [WordPressAgentAttachment]

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(attachments) { attachment in
                SentAttachmentPreview(attachment: attachment)
            }
        }
    }
}

private struct SentAttachmentPreview: View {
    let attachment: WordPressAgentAttachment

    var body: some View {
        if let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help(attachment.displayName)
        } else {
            Label(attachment.displayName, systemImage: "photo")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
        }
    }
}

private struct LocalImageThumbnail: View {
    let fileURL: URL
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .background(AgentPalette.softControl)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct WordPressAgentTranscriptView: View, Equatable {
    let conversation: WordPressAgentConversation?
    let activeSite: WPCOMSite?
    let activeWorkspaceTitle: String
    let isSignedIn: Bool

    private static let bottomAnchorID = "wordpress-agent-transcript-bottom"

    static func == (lhs: WordPressAgentTranscriptView, rhs: WordPressAgentTranscriptView) -> Bool {
        lhs.conversation == rhs.conversation
            && lhs.activeSite == rhs.activeSite
            && lhs.activeWorkspaceTitle == rhs.activeWorkspaceTitle
            && lhs.isSignedIn == rhs.isSignedIn
    }

    var body: some View {
        if let conversation {
            if conversation.messages.isEmpty,
               !conversation.isSending,
               conversation.errorMessage == nil {
                emptyWorkspace
            } else {
                transcript(for: conversation)
            }
        } else {
            emptyWorkspace
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 14) {
            if let activeSite {
                RemoteSiteIcon(site: activeSite, size: 54, cornerRadius: 14)
            } else {
                WordPressComLogoMark()
                    .frame(width: 54, height: 54)
            }

            Text(activeWorkspaceTitle)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(isSignedIn ? "New chat" : "WordPress.com sign-in needed")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private func transcript(for conversation: WordPressAgentConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(conversation.messages) { message in
                        WordPressAgentMessageRow(message: message)
                            .equatable()
                            .id(message.id)
                    }

                    if conversation.isSending {
                        WordPressAgentTypingRow()
                    }

                    if let errorMessage = conversation.errorMessage,
                       Self.shouldShowErrorSummary(errorMessage, in: conversation) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 28)
            }
            .onAppear {
                Self.scrollToBottom(proxy, animated: false)
            }
            .onChange(of: conversation.messages.count) { _ in
                Self.scrollToBottom(proxy)
            }
            .onChange(of: conversation.isSending) { _ in
                Self.scrollToBottom(proxy)
            }
            .onChange(of: conversation.errorMessage) { _ in
                Self.scrollToBottom(proxy)
            }
        }
    }

    private static func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                scroll()
            }
        } else {
            scroll()
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    scroll()
                }
            } else {
                scroll()
            }
        }
    }

    private static func shouldShowErrorSummary(
        _ errorMessage: String,
        in conversation: WordPressAgentConversation
    ) -> Bool {
        let trimmedError = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedError.isEmpty else { return false }
        guard let lastMessage = conversation.messages.last else { return true }
        return lastMessage.role != .system
            || lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedError
    }
}

private struct WordPressAgentMessageRow: View, Equatable {
    let message: WordPressAgentMessage

    static func == (lhs: WordPressAgentMessageRow, rhs: WordPressAgentMessageRow) -> Bool {
        lhs.message == rhs.message
    }

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .agent:
            agentMessage
        case .system:
            systemMessage
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 80)

            VStack(alignment: .trailing, spacing: 10) {
                if !message.attachments.isEmpty {
                    SentAttachmentPreviewList(attachments: message.attachments)
                }

                if !message.text.isEmpty {
                    MessageBodyText(text: message.text, foregroundStyle: .white, isOnDarkBackground: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black)
                )
                .frame(maxWidth: 560, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var agentMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            WordPressComLogoMark()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(message.stateDisplayText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(message.date, style: .time)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                MessageBodyText(text: message.text, foregroundStyle: .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    Image(systemName: "hand.thumbsup")
                    Image(systemName: "hand.thumbsdown")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemMessage: some View {
        Label {
            MessageBodyText(text: message.text, foregroundStyle: .red)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 13))
        .foregroundStyle(.red)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WordPressAgentTypingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            WordPressComLogoMark()
                .frame(width: 24, height: 24)
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
            Text("Thinking...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBodyText: View {
    let text: String
    let foregroundStyle: Color
    var isOnDarkBackground = false

    @State private var isExpanded = false

    private static let inlineMarkdownByteLimit = 2_500
    private static let collapsedPreviewCharacterLimit = 600
    private static let expandedPreviewCharacterLimit = 2_000
    private static let inlineLineLimit = 80

    var body: some View {
        if shouldUseCompactPreview {
            compactPreview
        } else {
            MarkdownMessageText(
                text: text,
                foregroundStyle: foregroundStyle,
                isOnDarkBackground: isOnDarkBackground
            )
        }
    }

    private var shouldUseCompactPreview: Bool {
        text.utf8.count > Self.inlineMarkdownByteLimit || Self.exceedsInlineLineLimit(text)
    }

    private var previewText: String {
        let limit = isExpanded
            ? Self.expandedPreviewCharacterLimit
            : Self.collapsedPreviewCharacterLimit
        let endIndex = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        let isTruncated = endIndex < text.endIndex
        var preview = String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty {
            preview = String(text[..<endIndex])
        }
        if isTruncated {
            preview += "\n\n[Message preview truncated. Copy the full text to inspect everything.]"
        }
        return preview
    }

    private var compactPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(previewText)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(foregroundStyle)
                .lineLimit(isExpanded ? 24 : 8)

            HStack(spacing: 10) {
                Text(compactStatusText)
                    .font(.system(size: 12, weight: .medium))

                Spacer(minLength: 0)

                if canExpandPreview {
                    Button(isExpanded ? "Show less" : "Show more") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                }

                Button("Copy full") {
                    copyFullText()
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(secondaryTextColor)
        }
    }

    private var canExpandPreview: Bool {
        guard let collapsedEndIndex = text.index(
            text.startIndex,
            offsetBy: Self.collapsedPreviewCharacterLimit,
            limitedBy: text.endIndex
        ) else {
            return false
        }
        return collapsedEndIndex < text.endIndex
    }

    private var compactStatusText: String {
        let previewKind = isExpanded ? "Larger preview" : "Compact preview"
        return "\(previewKind) of \(Self.formattedByteCount(text.utf8.count)) message"
    }

    private var secondaryTextColor: Color {
        isOnDarkBackground
            ? Color.white.opacity(0.72)
            : Color(nsColor: .secondaryLabelColor)
    }

    private func copyFullText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func formattedByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private static func exceedsInlineLineLimit(_ text: String) -> Bool {
        var lineBreaks = 0
        for character in text where character.isNewline {
            lineBreaks += 1
            if lineBreaks > inlineLineLimit {
                return true
            }
        }
        return false
    }
}

private struct MarkdownMessageText: View {
    let text: String
    let foregroundStyle: Color
    var isOnDarkBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.messageFragments(from: text)) { fragment in
                switch fragment {
                case .text(_, let fragmentText):
                    if !fragmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(Self.messageAttributedString(from: fragmentText))
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .foregroundStyle(foregroundStyle)
                    }
                case .image(_, let altText, let url):
                    RemoteMarkdownImage(url: url, altText: altText)
                case .table(_, let table):
                    MarkdownTableView(
                        table: table,
                        foregroundStyle: foregroundStyle,
                        isOnDarkBackground: isOnDarkBackground
                    )
                }
            }
        }
    }

    private enum MessageFragment: Identifiable {
        case text(Int, String)
        case image(Int, altText: String, url: URL)
        case table(Int, MarkdownTable)

        var id: Int {
            switch self {
            case .text(let id, _), .image(let id, _, _), .table(let id, _):
                return id
            }
        }
    }

    private static func messageFragments(from text: String) -> [MessageFragment] {
        let source = text as NSString
        let lines = sourceLines(from: text)
        guard !lines.isEmpty else {
            return [.text(0, text)]
        }

        var fragments: [MessageFragment] = []
        var cursor = 0
        var lineIndex = 0

        while lineIndex < lines.count {
            if let block = markdownTableBlock(startingAt: lineIndex, in: lines) {
                if block.range.location > cursor {
                    let leadingRange = NSRange(location: cursor, length: block.range.location - cursor)
                    appendTextAndImageFragments(from: source.substring(with: leadingRange), to: &fragments)
                }

                fragments.append(.table(fragments.count, block.table))
                cursor = block.range.location + block.range.length
                lineIndex = block.nextLineIndex
            } else {
                lineIndex += 1
            }
        }

        if cursor < source.length {
            let trailingRange = NSRange(location: cursor, length: source.length - cursor)
            appendTextAndImageFragments(from: source.substring(with: trailingRange), to: &fragments)
        }

        return fragments.isEmpty ? [.text(0, text)] : fragments
    }

    private static func appendTextAndImageFragments(from text: String, to fragments: inout [MessageFragment]) {
        guard let expression = markdownImageExpression else {
            fragments.append(.text(fragments.count, text))
            return
        }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = expression.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else {
            fragments.append(.text(fragments.count, text))
            return
        }

        var cursor = 0

        for match in matches {
            guard match.range.location != NSNotFound else { continue }

            if match.range.location > cursor {
                let textRange = NSRange(location: cursor, length: match.range.location - cursor)
                fragments.append(.text(fragments.count, source.substring(with: textRange)))
            }

            let originalMarkdown = source.substring(with: match.range)
            let altText = substring(in: source, range: match.range(at: 1))
            let rawURLString = substring(in: source, range: match.range(at: 2))
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

            if let url = URL(string: rawURLString),
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme) {
                fragments.append(.image(fragments.count, altText: altText, url: url))
            } else {
                fragments.append(.text(fragments.count, originalMarkdown))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            let textRange = NSRange(location: cursor, length: source.length - cursor)
            fragments.append(.text(fragments.count, source.substring(with: textRange)))
        }
    }

    fileprivate static func messageAttributedString(from text: String) -> AttributedString {
        var attributedText = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        let visibleText = String(attributedText.characters)
        let matches = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?
            .matches(
                in: visibleText,
                options: [],
                range: NSRange(visibleText.startIndex..<visibleText.endIndex, in: visibleText)
            ) ?? []

        for match in matches {
            guard let url = match.url,
                  let textRange = Range(match.range, in: visibleText),
                  let attributedRange = Range(textRange, in: attributedText),
                  attributedText[attributedRange].link == nil else {
                continue
            }

            attributedText[attributedRange].link = url
        }

        return attributedText
    }

    private static var markdownImageExpression: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"!\[([^\]]*)\]\(\s*([^\s\)]+)(?:\s+"[^"]*")?\s*\)"#,
            options: []
        )
    }

    private static func substring(in source: NSString, range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        return source.substring(with: range)
    }

    private struct SourceLine {
        let text: String
        let range: NSRange
    }

    private static func sourceLines(from text: String) -> [SourceLine] {
        let source = text as NSString
        var lines: [SourceLine] = []
        var location = 0

        while location < source.length {
            var lineEnd = location

            while lineEnd < source.length {
                let character = source.character(at: lineEnd)
                if character == 10 || character == 13 {
                    break
                }
                lineEnd += 1
            }

            var enclosingEnd = lineEnd
            if enclosingEnd < source.length {
                let character = source.character(at: enclosingEnd)
                enclosingEnd += 1
                if character == 13,
                   enclosingEnd < source.length,
                   source.character(at: enclosingEnd) == 10 {
                    enclosingEnd += 1
                }
            }

            lines.append(SourceLine(
                text: source.substring(with: NSRange(location: location, length: lineEnd - location)),
                range: NSRange(location: location, length: enclosingEnd - location)
            ))
            location = enclosingEnd
        }

        return lines
    }

    private static func markdownTableBlock(
        startingAt lineIndex: Int,
        in lines: [SourceLine]
    ) -> (table: MarkdownTable, range: NSRange, nextLineIndex: Int)? {
        guard lineIndex + 1 < lines.count else { return nil }

        let headerCells = markdownTableCells(in: lines[lineIndex].text)
        guard headerCells.count >= 2,
              let alignments = markdownTableAlignments(in: lines[lineIndex + 1].text),
              alignments.count == headerCells.count else {
            return nil
        }

        var rows: [[String]] = []
        var nextLineIndex = lineIndex + 2

        while nextLineIndex < lines.count {
            let line = lines[nextLineIndex].text
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  line.contains("|") else {
                break
            }

            let cells = markdownTableCells(in: line)
            guard cells.count >= 2 else {
                break
            }

            rows.append(normalizedMarkdownTableRow(cells, columnCount: headerCells.count))
            nextLineIndex += 1
        }

        let firstLine = lines[lineIndex]
        let lastLine = lines[nextLineIndex - 1]
        return (
            table: MarkdownTable(
                header: headerCells,
                alignments: alignments,
                rows: rows
            ),
            range: NSRange(
                location: firstLine.range.location,
                length: lastLine.range.location + lastLine.range.length - firstLine.range.location
            ),
            nextLineIndex: nextLineIndex
        )
    }

    private static func markdownTableCells(in line: String) -> [String] {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.contains("|") else { return [] }

        var cells: [String] = []
        var currentCell = ""
        var isEscaped = false

        for character in trimmedLine {
            if isEscaped {
                if character == "|" {
                    currentCell.append(character)
                } else {
                    currentCell.append("\\")
                    currentCell.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(currentCell)
                currentCell = ""
            } else {
                currentCell.append(character)
            }
        }

        if isEscaped {
            currentCell.append("\\")
        }
        cells.append(currentCell)

        if trimmedLine.hasPrefix("|"), !cells.isEmpty {
            cells.removeFirst()
        }
        if trimmedLine.hasSuffix("|"), !cells.isEmpty {
            cells.removeLast()
        }

        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func markdownTableAlignments(in line: String) -> [MarkdownTable.ColumnAlignment]? {
        let cells = markdownTableCells(in: line)
        guard cells.count >= 2 else { return nil }

        var alignments: [MarkdownTable.ColumnAlignment] = []

        for cell in cells {
            let trimmedCell = cell.trimmingCharacters(in: .whitespaces)
            let hasLeadingColon = trimmedCell.hasPrefix(":")
            let hasTrailingColon = trimmedCell.hasSuffix(":")
            let dashContent = trimmedCell
                .drop(while: { $0 == ":" })
                .dropLast(hasTrailingColon ? 1 : 0)

            guard dashContent.count >= 3,
                  dashContent.allSatisfy({ $0 == "-" }) else {
                return nil
            }

            if hasLeadingColon && hasTrailingColon {
                alignments.append(.center)
            } else if hasTrailingColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }

        return alignments
    }

    private static func normalizedMarkdownTableRow(_ cells: [String], columnCount: Int) -> [String] {
        guard cells.count != columnCount else { return cells }

        if cells.count < columnCount {
            return cells + Array(repeating: "", count: columnCount - cells.count)
        }

        let leadingCells = cells.prefix(columnCount - 1)
        let trailingCell = cells.dropFirst(columnCount - 1).joined(separator: " | ")
        return Array(leadingCells) + [trailingCell]
    }
}

private struct MarkdownTable: Equatable {
    enum ColumnAlignment: Equatable {
        case leading
        case center
        case trailing
    }

    let header: [String]
    let alignments: [ColumnAlignment]
    let rows: [[String]]

    var columnCount: Int {
        header.count
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let foregroundStyle: Color
    let isOnDarkBackground: Bool

    private var borderColor: Color {
        isOnDarkBackground ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    private var headerBackground: Color {
        isOnDarkBackground ? Color.white.opacity(0.14) : Color.black.opacity(0.05)
    }

    private var rowBackground: Color {
        isOnDarkBackground ? Color.white.opacity(0.06) : Color.black.opacity(0.02)
    }

    private var alternateRowBackground: Color {
        isOnDarkBackground ? Color.white.opacity(0.03) : Color.clear
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                        cell(
                            text: table.header[columnIndex],
                            columnIndex: columnIndex,
                            rowIndex: 0,
                            isHeader: true
                        )
                    }
                }

                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        let row = normalizedRow(table.rows[rowIndex])
                        ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                            cell(
                                text: row[columnIndex],
                                columnIndex: columnIndex,
                                rowIndex: rowIndex + 1,
                                isHeader: false
                            )
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(
        text: String,
        columnIndex: Int,
        rowIndex: Int,
        isHeader: Bool
    ) -> some View {
        Text(MarkdownMessageText.messageAttributedString(from: text))
            .font(.system(size: 14, weight: isHeader ? .semibold : .regular))
            .lineSpacing(3)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: columnWidth(for: columnIndex), alignment: alignment(for: columnIndex))
            .frame(minHeight: 34, alignment: alignment(for: columnIndex))
            .background(backgroundColor(rowIndex: rowIndex, isHeader: isHeader))
            .overlay(alignment: .trailing) {
                if columnIndex < table.columnCount - 1 {
                    Rectangle()
                        .fill(borderColor)
                        .frame(width: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if rowIndex < table.rows.count {
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: 1)
                }
            }
    }

    private func normalizedRow(_ row: [String]) -> [String] {
        if row.count == table.columnCount {
            return row
        }

        if row.count < table.columnCount {
            return row + Array(repeating: "", count: table.columnCount - row.count)
        }

        let leadingCells = row.prefix(table.columnCount - 1)
        let trailingCell = row.dropFirst(table.columnCount - 1).joined(separator: " | ")
        return Array(leadingCells) + [trailingCell]
    }

    private func backgroundColor(rowIndex: Int, isHeader: Bool) -> Color {
        if isHeader {
            return headerBackground
        }

        return rowIndex.isMultiple(of: 2) ? alternateRowBackground : rowBackground
    }

    private func alignment(for columnIndex: Int) -> Alignment {
        guard columnIndex < table.alignments.count else {
            return .leading
        }

        switch table.alignments[columnIndex] {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func columnWidth(for columnIndex: Int) -> CGFloat {
        let values = [table.header[columnIndex]]
            + table.rows.compactMap { row in
                columnIndex < row.count ? row[columnIndex] : nil
            }
        let longestText = values.map(visibleCharacterCount(in:)).max() ?? 0
        let width = CGFloat(longestText) * 7.5 + 28
        return min(max(width, columnIndex == 0 ? 44 : 72), 220)
    }

    private func visibleCharacterCount(in markdown: String) -> Int {
        markdown
            .replacingOccurrences(of: #"[*_`~\[\]\(\)]"#, with: "", options: .regularExpression)
            .count
    }
}

private struct RemoteMarkdownImage: View {
    let url: URL
    let altText: String
    private let maximumDisplaySize = CGSize(width: 520, height: 360)
    @Environment(\.openURL) private var openURL
    @StateObject private var imageLoader = CachedRemoteImageLoader()

    var body: some View {
        Button {
            openURL(url)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            Button {
                copyImage()
            } label: {
                Label("Copy Image", systemImage: "photo.on.rectangle")
            }

            Button {
                copyImageURL()
            } label: {
                Label("Copy Image URL", systemImage: "link")
            }

            Divider()

            Button {
                saveImageAs()
            } label: {
                Label("Save Image As...", systemImage: "square.and.arrow.down")
            }

            Button {
                openURL(url)
            } label: {
                Label("Open Image", systemImage: "safari")
            }
        }
        .onAppear {
            imageLoader.load(url)
        }
        .onChange(of: url) { newURL in
            imageLoader.load(newURL)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = imageLoader.image {
            loadedImage(image)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AgentPalette.searchField)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AgentPalette.controlStroke, lineWidth: 1)
                    )

                if imageLoader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .medium))

                        if !altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(altText)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(16)
                }
            }
            .frame(width: maximumDisplaySize.width, height: 180)
        }
    }

    private var accessibilityLabel: String {
        let trimmedAltText = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAltText.isEmpty ? "Image" : trimmedAltText
    }

    private func loadedImage(_ image: NSImage) -> some View {
        let displaySize = fittedDisplaySize(for: image)

        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: displaySize.width, height: displaySize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AgentPalette.controlStroke, lineWidth: 1)
            )
    }

    private func fittedDisplaySize(for image: NSImage) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return maximumDisplaySize
        }

        let scale = min(
            maximumDisplaySize.width / imageSize.width,
            maximumDisplaySize.height / imageSize.height,
            1
        )

        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func copyImage() {
        if let image = imageLoader.image {
            Self.writeImageToPasteboard(image)
            return
        }

        let cachedData = imageLoader.imageData
        Task {
            do {
                let data = try await Self.loadImageData(from: url, cachedData: cachedData)
                guard let image = NSImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                await MainActor.run {
                    Self.writeImageToPasteboard(image)
                }
            } catch {
                await MainActor.run {
                    showImageActionError(title: "Could not copy image.", error: error)
                }
            }
        }
    }

    private func copyImageURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func saveImageAs() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        if let contentType = suggestedContentType {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK,
              let destinationURL = panel.url else {
            return
        }

        let cachedData = imageLoader.imageData
        Task {
            do {
                let data = try await Self.loadImageData(from: url, cachedData: cachedData)
                try data.write(to: destinationURL, options: .atomic)
            } catch {
                await MainActor.run {
                    showImageActionError(title: "Could not save image.", error: error)
                }
            }
        }
    }

    private var suggestedFilename: String {
        let decodedLastPathComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let trimmedLastPathComponent = decodedLastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLastPathComponent.isEmpty {
            return trimmedLastPathComponent
        }

        let baseName = sanitizedFilenameComponent(from: altText) ?? "image"
        let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return pathExtension.isEmpty ? "\(baseName).png" : "\(baseName).\(pathExtension)"
    }

    private var suggestedContentType: UTType? {
        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else {
            return nil
        }
        return type
    }

    private func sanitizedFilenameComponent(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let forbiddenCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitizedText = trimmedText
            .components(separatedBy: forbiddenCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))

        guard !sanitizedText.isEmpty else { return nil }
        return String(sanitizedText.prefix(80))
    }

    private static func loadImageData(from url: URL, cachedData: Data?) async throws -> Data {
        if let cachedData {
            return cachedData
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<400).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private static func writeImageToPasteboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func showImageActionError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct RemoteSiteIcon: View {
    let site: WPCOMSite
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RemoteRoundedImage(
            url: site.iconURL ?? fallbackFaviconURL,
            fallbackText: site.displayName,
            size: size,
            cornerRadius: cornerRadius,
            backgroundColor: Color(red: 0.18, green: 0.42, blue: 0.72)
        )
    }

    private var fallbackFaviconURL: URL? {
        guard let urlString = site.url,
              var components = URLComponents(string: urlString) else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct RemoteAvatar: View {
    let url: URL?
    let fallbackText: String
    let size: CGFloat

    var body: some View {
        RemoteRoundedImage(
            url: url,
            fallbackText: fallbackText,
            size: size,
            cornerRadius: size / 2,
            backgroundColor: Color(red: 0.05, green: 0.72, blue: 0.58)
        )
    }
}

@MainActor
private final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var imageData: Data?
    @Published private(set) var isLoading = false

    private static let cache = NSCache<NSURL, NSImage>()
    private static let dataCache = NSCache<NSURL, NSData>()
    private var loadedURL: URL?
    private var task: Task<Void, Never>?

    func load(_ url: URL?) {
        guard loadedURL != url else { return }

        task?.cancel()
        loadedURL = url
        image = nil
        imageData = nil
        isLoading = false

        guard let url else { return }

        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
            imageData = Self.dataCache.object(forKey: url as NSURL) as Data?
            return
        }

        isLoading = true
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 12

        task = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<400).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                let decodedImage = NSImage(data: data)

                guard let decodedImage else {
                    throw URLError(.cannotDecodeContentData)
                }

                Self.cache.setObject(decodedImage, forKey: url as NSURL)
                Self.dataCache.setObject(data as NSData, forKey: url as NSURL)
                self?.image = decodedImage
                self?.imageData = data
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.image = nil
                self?.imageData = nil
                self?.isLoading = false
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

private struct RemoteRoundedImage: View {
    let url: URL?
    let fallbackText: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color
    @StateObject private var imageLoader = CachedRemoteImageLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)

            if let image = imageLoader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if imageLoader.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                fallbackTextView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            imageLoader.load(url)
        }
        .onChange(of: url) { newURL in
            imageLoader.load(newURL)
        }
    }

    private var fallbackTextView: some View {
        Text(initials(from: fallbackText))
            .font(.system(size: max(10, size * 0.38), weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(2)
    }

    private func initials(from text: String) -> String {
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        if let first = words.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "WP"
    }
}

private extension WordPressAgentMessage {
    var stateDisplayText: String {
        guard let state,
              !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "WordPress Agent"
        }
        return state
    }
}
