import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct WordPressAgentWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var draftMessage = ""
    @State private var pendingImageURLs: [URL] = []
    @State private var sidebarSearch = ""
    @State private var isAllSitesExpanded = false
    @State private var shouldRestoreComposerFocusAfterSend = false
    @State private var previewSidebarWidth: CGFloat = 520
    @State private var previewSidebarResizeStartWidth: CGFloat?
    @FocusState private var isComposerFocused: Bool

    private let recentSiteLimit = 5
    private let workspaceMinimumWidth: CGFloat = 360
    private let previewMinimumWidth: CGFloat = 320

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

    private var recentSites: [WPCOMSite] {
        let sitesByID = siteByID
        var seenSiteIDs = Set<Int>()
        var orderedSites: [WPCOMSite] = []

        func appendSite(_ siteID: Int?) {
            guard let siteID,
                  seenSiteIDs.insert(siteID).inserted,
                  let site = sitesByID[siteID] else {
                return
            }
            orderedSites.append(site)
        }

        appState.recentWordPressAgentSiteIDs.forEach { appendSite($0) }
        appendSite(appState.selectedWordPressComSiteID)
        appState.sortedWordPressAgentConversations.forEach { appendSite($0.key.siteID) }
        appState.wordpressComSites.prefix(recentSiteLimit).forEach { appendSite($0.id) }

        return Array(orderedSites.prefix(recentSiteLimit))
    }

    private var visibleRecentSites: [WPCOMSite] {
        guard !normalizedSearch.isEmpty else { return recentSites }
        return recentSites.filter(siteMatchesSearch)
    }

    private var dropdownSites: [WPCOMSite] {
        let recentSiteIDs = Set(recentSites.map(\.id))
        return appState.wordpressComSites
            .filter { !recentSiteIDs.contains($0.id) }
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

    private var remainingSiteCount: Int {
        max(0, appState.wordpressComSites.count - recentSites.count)
    }

    private func siteMatchesSearch(_ site: WPCOMSite) -> Bool {
        site.displayName.localizedCaseInsensitiveContains(normalizedSearch)
        || (site.slug ?? "").localizedCaseInsensitiveContains(normalizedSearch)
        || (site.url ?? "").localizedCaseInsensitiveContains(normalizedSearch)
    }

    private var latestConversationBySiteID: [Int: WordPressAgentConversation] {
        var conversationsBySiteID: [Int: WordPressAgentConversation] = [:]
        for conversation in appState.sortedWordPressAgentConversations where conversationsBySiteID[conversation.key.siteID] == nil {
            conversationsBySiteID[conversation.key.siteID] = conversation
        }
        return conversationsBySiteID
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
            await appState.refreshWordPressAgentConversationsIfNeeded()
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
            SidebarSectionHeader(title: "Last")

            if visibleRecentSites.isEmpty {
                SidebarEmptyText(appState.isWordPressComSignedIn ? "No recent matching sites" : "Sign in to WordPress.com")
                    .padding(.horizontal, 8)
            } else {
                LazyVStack(spacing: 2) {
                    let conversationsBySiteID = latestConversationBySiteID
                    ForEach(visibleRecentSites) { site in
                        Button {
                            appState.selectWordPressAgentSite(site.id)
                            isComposerFocused = true
                        } label: {
                            SiteSidebarRow(
                                site: site,
                                isSelected: site.id == activeSiteID,
                                lastUsedDate: conversationsBySiteID[site.id]?.lastUpdated
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if appState.isWordPressComSignedIn {
                allSitesDropdown
            }
        }
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

                    Text("\(normalizedSearch.isEmpty ? remainingSiteCount : dropdownSites.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if shouldShowDropdownSites {
                if dropdownSites.isEmpty {
                    SidebarEmptyText("No matching sites")
                        .padding(.horizontal, 8)
                } else {
                    LazyVStack(spacing: 2) {
                        let conversationsBySiteID = latestConversationBySiteID
                        ForEach(dropdownSites) { site in
                            Button {
                                appState.selectWordPressAgentSite(site.id)
                                isAllSitesExpanded = false
                                isComposerFocused = true
                            } label: {
                                SiteSidebarRow(
                                    site: site,
                                    isSelected: site.id == activeSiteID,
                                    lastUsedDate: conversationsBySiteID[site.id]?.lastUpdated
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var conversationsSection: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            SidebarSectionHeader(title: "Recent")

            if visibleConversations.isEmpty {
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
                LazyVStack(spacing: 2) {
                    ForEach(visibleConversations) { conversation in
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
                }
            }
        }
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
                            previewSidebarWidth = min(
                                max(startWidth - translationX, previewMinimumWidth),
                                maximumPreviewWidth
                            )
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
            transcript
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
                ProgressView()
                    .controlSize(.small)
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

    @ViewBuilder
    private var transcript: some View {
        if let selectedConversation {
            if selectedConversation.messages.isEmpty,
               !selectedConversation.isSending,
               selectedConversation.errorMessage == nil {
                emptyWorkspace
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(selectedConversation.messages) { message in
                                WordPressAgentMessageRow(message: message)
                                    .id(message.id)
                            }

                            if selectedConversation.isSending {
                                WordPressAgentTypingRow()
                            }

                            if let errorMessage = selectedConversation.errorMessage,
                               shouldShowErrorSummary(errorMessage, in: selectedConversation) {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 34)
                        .padding(.top, 34)
                        .padding(.bottom, 28)
                    }
                    .onAppear {
                        if let lastMessageID = selectedConversation.messages.last?.id {
                            proxy.scrollTo(lastMessageID, anchor: .bottom)
                        }
                    }
                    .onChange(of: selectedConversation.messages.count) { _ in
                        if let lastMessageID = selectedConversation.messages.last?.id {
                            proxy.scrollTo(lastMessageID, anchor: .bottom)
                        }
                    }
                }
            }
        } else {
            emptyWorkspace
        }
    }

    private func shouldShowErrorSummary(_ errorMessage: String, in conversation: WordPressAgentConversation) -> Bool {
        let trimmedError = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedError.isEmpty else { return false }
        guard let lastMessage = conversation.messages.last else { return true }
        return lastMessage.role != .system
            || lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedError
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
            VStack(spacing: 12) {
                if !pendingImageURLs.isEmpty {
                    ComposerAttachmentStrip(fileURLs: pendingImageURLs) { url in
                        pendingImageURLs.removeAll { $0 == url }
                    }
                }

                TextField("Ask WordPress Agent", text: $draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .focused($isComposerFocused)
                    .onSubmit(sendDraftMessage)
                    .disabled(isComposerInputDisabled)

                HStack(spacing: 14) {
                    Button {
                        selectImages()
                        isComposerFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .regular))
                            .frame(width: 28, height: 28)
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
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 30, height: 30)
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
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(canSendMessage ? AgentPalette.primaryActionIcon : AgentPalette.secondaryText)
                            .frame(width: 36, height: 36)
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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AgentPalette.composer)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
    }

    private var canSendMessage: Bool {
        (!draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImageURLs.isEmpty)
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

    private func sendDraftMessage() {
        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingImageURLs
        guard !trimmedMessage.isEmpty || !attachments.isEmpty else { return }
        guard appState.submitWordPressAgentComposerMessage(
            trimmedMessage,
            attachments: attachments,
            siteID: activeSiteID
        ) != nil else { return }
        draftMessage = ""
        pendingImageURLs = []
        shouldRestoreComposerFocusAfterSend = true
        restoreComposerFocusSoon(clearPending: false)
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

        var existingURLs = Set(pendingImageURLs)
        for url in panel.urls where existingURLs.insert(url).inserted {
            pendingImageURLs.append(url)
        }
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

                    Text(preview.url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 10)

                Button {
                    NSWorkspace.shared.open(preview.url)
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

            WordPressAgentWebPreview(url: preview.url)
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
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var loadedURL: URL?

        func load(_ url: URL, in webView: WKWebView) {
            let previewURL = WordPressAgentPreviewURLResolver.previewURL(for: url) ?? url
            guard loadedURL != previewURL else { return }
            loadedURL = previewURL
            webView.load(URLRequest(url: previewURL))
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
                    load(previewURL, in: webView)
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
                load(url, in: webView)
            } else {
                webView.load(navigationAction.request)
            }
            return nil
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
    let lastUsedDate: Date?

    var body: some View {
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

            if let lastUsedDate {
                Text(lastUsedDate, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
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
           !firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return firstUserMessage
        }
        return conversation.title
    }

    private var subtitle: String {
        site?.displayName ?? conversation.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let site {
                RemoteSiteIcon(site: site, size: 22, cornerRadius: 6)
            } else {
                WordPressComLogoMark()
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text(subtitle)
                        .lineLimit(1)
                    Text(conversation.lastUpdated, style: .relative)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AgentPalette.sidebarSelection : Color.clear)
        )
        .contentShape(Rectangle())
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

private struct WordPressAgentMessageRow: View {
    let message: WordPressAgentMessage

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
                    MarkdownMessageText(text: message.text, foregroundStyle: .white)
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

                MarkdownMessageText(text: message.text, foregroundStyle: .primary)
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
            MarkdownMessageText(text: message.text, foregroundStyle: .red)
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
            ProgressView()
                .controlSize(.small)
            Text("Thinking...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownMessageText: View {
    let text: String
    let foregroundStyle: Color

    var body: some View {
        Text(Self.messageAttributedString(from: text))
            .textSelection(.enabled)
            .font(.system(size: 16))
            .lineSpacing(4)
            .foregroundStyle(foregroundStyle)
    }

    private static func messageAttributedString(from text: String) -> AttributedString {
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
    @Published private(set) var isLoading = false

    private static let cache = NSCache<NSURL, NSImage>()
    private var loadedURL: URL?
    private var task: Task<Void, Never>?

    func load(_ url: URL?) {
        guard loadedURL != url else { return }

        task?.cancel()
        loadedURL = url
        image = nil
        isLoading = false

        guard let url else { return }

        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
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
                self?.image = decodedImage
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.image = nil
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
