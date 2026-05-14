import SwiftUI
import AVFoundation

// MARK: - Shared Helpers

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let usesWordPressComLogo: Bool
    let content: Content

    init(
        _ title: String,
        icon: String,
        usesWordPressComLogo: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.usesWordPressComLogo = usesWordPressComLogo
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if usesWordPressComLogo {
                    WordPressComLogoMark()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: icon)
                }

                Text(title)
            }
            .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        appState.selectedSettingsTab = tab
                    } label: {
                        settingsTabLabel(tab)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill((appState.selectedSettingsTab ?? .permissions) == tab
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch appState.selectedSettingsTab ?? .permissions {
                case .permissions:
                    GeneralSettingsView(tab: .permissions)
                case .keyBindings:
                    GeneralSettingsView(tab: .keyBindings)
                case .transcription:
                    GeneralSettingsView(tab: .transcription)
                case .wordpressCom:
                    GeneralSettingsView(tab: .wordpressCom)
                case .network:
                    GeneralSettingsView(tab: .network)
                case .wordpressAgent:
                    GeneralSettingsView(tab: .wordpressAgent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func settingsTabLabel(_ tab: SettingsTab) -> some View {
        HStack(spacing: 6) {
            if tab == .wordpressCom {
                WordPressComLogoMark()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: tab.icon)
            }

            Text(tab.title)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var micPermissionGranted = false
    @State private var elevenLabsAPIKeyInput = ""
    let tab: SettingsTab

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch tab {
                case .permissions:
                    SettingsCard("Permissions", icon: tab.icon) {
                        permissionsSection
                    }
                    SettingsCard("Setup & Diagnostics", icon: "wrench.and.screwdriver") {
                        setupDiagnosticsSection
                    }
                case .keyBindings:
                    SettingsCard("Shortcuts", icon: tab.icon) {
                        hotkeySection
                    }
                case .transcription:
                    SettingsCard("Transcription", icon: tab.icon) {
                        transcriptionSection
                    }
                case .wordpressCom:
                    SettingsCard("WordPress.com", icon: tab.icon, usesWordPressComLogo: true) {
                        wordpressComSection
                    }
                case .network:
                    SettingsCard("Network", icon: tab.icon) {
                        networkSection
                    }
                case .wordpressAgent:
                    SettingsCard("WordPress Agent", icon: tab.icon) {
                        wordpressAgentSection
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            checkMicPermission()
            appState.refreshLaunchAtLoginStatus()
            appState.refreshWordPressComSitesFromUI()
            appState.refreshAvailableSpeechVoices()
            if appState.hasElevenLabsAPIKey {
                appState.refreshElevenLabsVoicesFromUI()
            }
            appState.refreshLatestExternalAppSnapshot()
        }
    }

    // MARK: WordPress.com

    private var wordpressComSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isWordPressComSignedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Sign in to choose the site WP Workspace should use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    appState.signInToWordPressCom()
                } label: {
                    if appState.isSigningInToWordPressCom {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Signing in...")
                        }
                    } else {
                        Label(appState.isWordPressComSignedIn ? "Sign In Again" : "Sign In", systemImage: "person.crop.circle")
                    }
                }
                .disabled(appState.isSigningInToWordPressCom)

                Button {
                    appState.refreshWordPressComSitesFromUI()
                } label: {
                    if appState.isRefreshingWordPressComSites {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Refreshing...")
                        }
                    } else {
                        Label("Refresh Sites", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!appState.isWordPressComSignedIn || appState.isRefreshingWordPressComSites)

                Button("Sign Out") {
                    appState.signOutOfWordPressCom()
                }
                .disabled(!appState.isWordPressComSignedIn)
            }

            if !appState.wordpressComSites.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Site")
                        .font(.caption.weight(.semibold))
                    WordPressSiteSearchPicker(
                        sites: appState.wordpressComSitesSortedByStarred,
                        selectedSiteID: Binding(
                            get: { appState.selectedWordPressComSiteID },
                            set: { appState.selectedWordPressComSiteID = $0 }
                        ),
                        maxVisibleRows: 6,
                        starredSiteIDs: appState.starredWordPressAgentSiteIDs,
                        onToggleStar: { siteID in
                            appState.toggleWordPressAgentSiteStar(siteID)
                        }
                    )
                }
            }

            transcribeGuidelineLink

            if !appState.wordpressComSites.isEmpty {
                appSiteOverridesSection
            }

            if !appState.wordpressComSites.isEmpty {
                localWorkspaceSection
            }

            if let message = appState.wordpressComStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var wordpressAgentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable WordPress Agent", isOn: $appState.isWordPressAgentEnabled)
                .disabled(!appState.isWordPressComSignedIn)

            VStack(alignment: .leading, spacing: 4) {
                Text("When enabled:")
                    .font(.caption.weight(.semibold))
                Text("- Voice invocation can route requests to the WordPress Agent instead of always pasting dictated text.")
                Text("- Left-clicking the menu bar icon opens the WordPress Agent window.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle("Read WordPress Agent Replies Aloud", isOn: $appState.shouldSpeakWordPressAgentReplies)
                .disabled(!appState.isWordPressComSignedIn || !appState.isWordPressAgentEnabled)

            Text("Uses the selected voice provider to speak the same reply shown in the notification.")
                .font(.caption)
                .foregroundStyle(.secondary)

            wordpressAgentSpeechControls

            if !appState.isWordPressComSignedIn {
                Text("Sign in to WordPress.com before enabling the WordPress Agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save Transcription Artifacts", isOn: $appState.saveTranscriptionArtifacts)
                .disabled(!appState.isWordPressComSignedIn)

            Text("When enabled, each non-empty recording saves the raw transcript as a private Transcription artifact on the WordPress.com site used for that recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("App-specific transcription site routing is managed in the WordPress.com tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open WordPress.com") {
                    appState.selectedSettingsTab = .wordpressCom
                }
                .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription Guideline")
                    .font(.caption.weight(.semibold))
                transcribeGuidelineLink
            }

            if !appState.isWordPressComSignedIn {
                Text("Sign in to WordPress.com before saving transcription artifacts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var transcribeGuidelineLink: some View {
        HStack(spacing: 10) {
            if appState.transcribeSkill != nil {
                Label("Transcription guideline found", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    appState.openTranscribeSkill()
                } label: {
                    Label("Open in wp-admin", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
            } else if appState.selectedWordPressComSiteID != nil {
                Text("The AI transcription endpoint will create the Transcription guideline on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var wordpressAgentSpeechControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Speech", selection: $appState.wordpressAgentSpeechProvider) {
                ForEach(WordPressAgentSpeechProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            switch appState.wordpressAgentSpeechProvider {
            case .system:
                systemSpeechControls
            case .elevenLabs:
                elevenLabsSpeechControls
            }
        }
    }

    private var systemSpeechControls: some View {
        HStack(spacing: 10) {
            Picker("Voice", selection: $appState.selectedWordPressAgentVoiceIdentifier) {
                Text("System Default").tag("")
                ForEach(appState.availableSpeechVoices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            .frame(maxWidth: 360)

            Button {
                appState.previewWordPressAgentVoice()
            } label: {
                Label("Preview", systemImage: "speaker.wave.2.fill")
            }
        }
        .disabled(
            !appState.isWordPressComSignedIn
            || !appState.isWordPressAgentEnabled
        )
    }

    private var elevenLabsSpeechControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SecureField(
                    appState.hasElevenLabsAPIKey ? "Saved API key" : "ElevenLabs API key",
                    text: $elevenLabsAPIKeyInput
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

                Button {
                    appState.saveElevenLabsAPIKey(elevenLabsAPIKeyInput)
                    elevenLabsAPIKeyInput = ""
                } label: {
                    Label("Save", systemImage: "key.fill")
                }
                .disabled(elevenLabsAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    elevenLabsAPIKeyInput = ""
                    appState.clearElevenLabsAPIKey()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(!appState.hasElevenLabsAPIKey && elevenLabsAPIKeyInput.isEmpty)
            }

            HStack(spacing: 10) {
                Picker("Voice", selection: $appState.selectedElevenLabsVoiceIdentifier) {
                    if appState.selectedElevenLabsVoiceIdentifier.isEmpty {
                        Text("Choose Voice").tag("")
                    } else if !appState.availableElevenLabsVoices.contains(where: { $0.id == appState.selectedElevenLabsVoiceIdentifier }) {
                        Text("Saved Voice").tag(appState.selectedElevenLabsVoiceIdentifier)
                    }
                    ForEach(appState.availableElevenLabsVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                .frame(maxWidth: 360)

                Button {
                    appState.refreshElevenLabsVoicesFromUI()
                } label: {
                    if appState.isRefreshingElevenLabsVoices {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Refreshing...")
                        }
                    } else {
                        Label("Refresh Voices", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!appState.hasElevenLabsAPIKey || appState.isRefreshingElevenLabsVoices)

                Button {
                    appState.previewWordPressAgentVoice()
                } label: {
                    Label("Preview", systemImage: "speaker.wave.2.fill")
                }
                .disabled(!appState.hasElevenLabsAPIKey || appState.selectedElevenLabsVoiceIdentifier.isEmpty)
            }

            if let message = appState.elevenLabsStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Bypass macOS system proxy",
                isOn: Binding(
                    get: { appState.networkRoutingSettings.bypassesSystemProxy },
                    set: { appState.setNetworkBypassesSystemProxy($0) }
                )
            )

            Text("Developer sandbox setting. Use only when /etc/hosts points public-api.wordpress.com at a sandbox IP and a system proxy would otherwise route around local DNS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var localWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Local Workspace")
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            if let siteID = appState.selectedWordPressComSiteID {
                let workspace = appState.localWorkspace(for: siteID)
                if let workspace {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .frame(width: 20)
                                .foregroundStyle(Color.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(siteName(siteID))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(localWorkspaceSubtitle(workspace))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Toggle(
                                "Agent Access",
                                isOn: Binding(
                                    get: { appState.localWorkspace(for: siteID)?.isEnabled ?? false },
                                    set: { appState.setLocalWorkspaceEnabled(siteID: siteID, isEnabled: $0) }
                                )
                            )
                            .toggleStyle(.switch)
                            .font(.caption)
                            .help("Enable local project tools for this site")

                            Button {
                                appState.addLocalProjectToWorkspace(siteID: siteID)
                            } label: {
                                Label("Add Folder", systemImage: "folder.badge.plus")
                            }

                            Button {
                                appState.removeLocalWorkspace(siteID: siteID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Disconnect local workspace")
                        }

                        if workspace.projects.isEmpty {
                            Text("Add a theme, plugin, or project folder to let the WordPress Agent route local file questions to Claude Code on this Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(workspace.projects) { project in
                                    localWorkspaceProjectRow(project, siteID: siteID)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .frame(width: 20)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Connect a local project")
                                    .font(.caption.weight(.semibold))
                                Text("Link a theme, plugin, or project folder to \(siteName(siteID)). The connection is created only after you choose a folder.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }

                        Button {
                            appState.createLocalWorkspaceForSelectedSite()
                        } label: {
                            Label("Connect Project", systemImage: "folder.badge.plus")
                        }
                    }
                }
            } else {
                Text("Choose a default site before creating a local workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func localWorkspaceProjectRow(_ project: WPLocalProject, siteID: Int) -> some View {
        let healthCheck = appState.localProjectHealthCheck(for: project.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: localWorkspaceProjectIcon(project.kind))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        localWorkspaceBadge(project.kind.label)
                        localWorkspaceWritePolicyPicker(project, siteID: siteID)
                    }
                    Text(project.rootPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button {
                    appState.checkLocalProjectAgent(siteID: siteID, projectID: project.id)
                } label: {
                    if healthCheck?.state == .checking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                }
                .buttonStyle(.borderless)
                .help("Test Claude Code for this project")
                .disabled(healthCheck?.state == .checking)

                Button {
                    appState.removeLocalProject(siteID: siteID, projectID: project.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Remove project folder")
            }

            HStack(spacing: 6) {
                Image(systemName: localProjectCheckIcon(healthCheck))
                    .frame(width: 14)
                    .foregroundStyle(localProjectCheckColor(healthCheck))
                Text(localProjectCheckMessage(healthCheck))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .cornerRadius(6)
    }

    private func localWorkspaceWritePolicyPicker(_ project: WPLocalProject, siteID: Int) -> some View {
        Picker(
            "Local agent access",
            selection: Binding(
                get: {
                    appState.localWorkspace(for: siteID)?
                        .projects
                        .first(where: { $0.id == project.id })?
                        .writePolicy ?? project.writePolicy
                },
                set: { writePolicy in
                    appState.setLocalProjectWritePolicy(
                        siteID: siteID,
                        projectID: project.id,
                        writePolicy: writePolicy
                    )
                }
            )
        ) {
            ForEach(WPLocalWorkspaceWritePolicy.allCases, id: \.rawValue) { writePolicy in
                Text(writePolicy.label).tag(writePolicy)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 132)
        .help("Choose whether the local agent can request approved edits for this project.")
    }

    private func localWorkspaceSubtitle(_ workspace: WPSiteLocalWorkspace?) -> String {
        guard let workspace else { return "No local workspace configured" }
        let count = workspace.projects.count
        let noun = count == 1 ? "project" : "projects"
        let state = workspace.isEnabled ? "Agent access enabled" : "Agent access disabled"
        return "\(state) - \(count) local \(noun)"
    }

    private func localWorkspaceBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(4)
    }

    private func localWorkspaceProjectIcon(_ kind: WPLocalProjectKind) -> String {
        switch kind {
        case .theme:
            return "paintpalette"
        case .plugin:
            return "puzzlepiece.extension"
        case .other:
            return "folder"
        }
    }

    private func localProjectCheckIcon(_ check: WPLocalProjectHealthCheck?) -> String {
        switch check?.state {
        case .checking:
            return "clock"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case nil:
            return "circle.dashed"
        }
    }

    private func localProjectCheckColor(_ check: WPLocalProjectHealthCheck?) -> Color {
        switch check?.state {
        case .checking:
            return .secondary
        case .ready:
            return .green
        case .failed:
            return .orange
        case nil:
            return .secondary
        }
    }

    private func localProjectCheckMessage(_ check: WPLocalProjectHealthCheck?) -> String {
        check?.message ?? "Claude Code has not been tested for this project."
    }

    private var appSiteOverridesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Text("App-Specific Sites")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    appState.refreshLatestExternalAppSnapshot()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh current app")
            }

            currentAppSiteOverrideRow

            let storedOverrides = sortedAppSiteOverrides(
                appState.wordpressComAppSiteOverrides.filter {
                    $0.bundleIdentifier != appState.latestExternalAppSnapshot?.bundleIdentifier
                }
            )
            if !storedOverrides.isEmpty {
                VStack(spacing: 6) {
                    ForEach(storedOverrides) { override in
                        storedAppSiteOverrideRow(override)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentAppSiteOverrideRow: some View {
        if let snapshot = appState.latestExternalAppSnapshot,
           let bundleIdentifier = snapshot.bundleIdentifier {
            let override = appState.wordPressComAppSiteOverride(for: bundleIdentifier)
            HStack(spacing: 10) {
                Image(systemName: "app.badge")
                    .frame(width: 20)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.appName ?? bundleIdentifier)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                siteSelectionMenu(
                    siteID: override?.siteID,
                    allowsDefault: true,
                    action: { siteID in
                        appState.setWordPressComAppSiteOverride(
                            bundleIdentifier: bundleIdentifier,
                            appName: snapshot.appName,
                            siteID: siteID
                        )
                    }
                )
                Button {
                    appState.assignSelectedWordPressComSiteToLatestExternalApp()
                } label: {
                    Image(systemName: "pin.fill")
                }
                .buttonStyle(.borderless)
                .disabled(appState.selectedWordPressComSiteID == nil)
                .help("Pin current default site to this app")
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        } else {
            Text("Switch to another app, then reopen WP Workspace to assign a site.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func storedAppSiteOverrideRow(_ override: WPCOMAppSiteOverride) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "app.connected.to.app.below.fill")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(override.appName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(override.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            siteSelectionMenu(
                siteID: override.siteID,
                allowsDefault: false,
                action: { siteID in
                    appState.setWordPressComAppSiteOverride(
                        bundleIdentifier: override.bundleIdentifier,
                        appName: override.appName,
                        siteID: siteID
                    )
                }
            )
            Button {
                appState.removeWordPressComAppSiteOverride(bundleIdentifier: override.bundleIdentifier)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove app-specific site")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .cornerRadius(6)
    }

    private func siteSelectionMenu(
        siteID: Int?,
        allowsDefault: Bool,
        action: @escaping (Int?) -> Void
    ) -> some View {
        Menu {
            if allowsDefault {
                Button {
                    action(nil)
                } label: {
                    siteMenuItem(title: "Use Default Site", isSelected: siteID == nil)
                }
                Divider()
            }

            ForEach(appState.wordpressComSitesSortedByStarred) { site in
                Button {
                    action(site.id)
                } label: {
                    siteMenuItem(
                        title: site.displayName,
                        isSelected: siteID == site.id,
                        isStarred: appState.isWordPressAgentSiteStarred(site.id)
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(siteSelectionTitle(siteID: siteID, allowsDefault: allowsDefault))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 190, alignment: .trailing)
    }

    private func siteMenuItem(title: String, isSelected: Bool, isStarred: Bool = false) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark")
            }
            if isStarred {
                Image(systemName: "star.fill")
            }
            Text(title)
        }
    }

    private func sortedAppSiteOverrides(_ overrides: [WPCOMAppSiteOverride]) -> [WPCOMAppSiteOverride] {
        overrides.sorted { lhs, rhs in
            let lhsStarred = appState.isWordPressAgentSiteStarred(lhs.siteID)
            let rhsStarred = appState.isWordPressAgentSiteStarred(rhs.siteID)
            if lhsStarred != rhsStarred {
                return lhsStarred
            }
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    private func siteSelectionTitle(siteID: Int?, allowsDefault: Bool) -> String {
        if let siteID {
            return siteName(siteID)
        }

        guard allowsDefault else { return "Choose Site" }
        if let selectedWordPressComSiteID = appState.selectedWordPressComSiteID {
            return "Default: \(siteName(selectedWordPressComSiteID))"
        }
        return "Use Default Site"
    }

    private func siteName(_ siteID: Int) -> String {
        appState.wordpressComSites.first(where: { $0.id == siteID })?.displayName ?? "Site \(siteID)"
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: {
                    appState.requestMicrophoneAccess { granted in
                        micPermissionGranted = granted
                    }
                }
            )

            permissionRow(
                title: "Accessibility",
                icon: "hand.raised.fill",
                granted: appState.hasAccessibility,
                action: {
                    appState.openAccessibilitySettings()
                }
            )
        }
    }

    private var setupDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .showSetup, object: nil)
                } label: {
                    Label("Re-run Setup", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    appState.toggleDebugOverlay()
                } label: {
                    Label(
                        appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Start Debug Overlay",
                        systemImage: appState.isDebugOverlayActive ? "xmark.circle" : "ladybug"
                    )
                }
            }

            Text("Use setup to revisit permissions and onboarding. The debug overlay shows live app state while diagnosing shortcut, transcription, or context issues.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Dictation Shortcuts

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DictationShortcutEditor { isCapturing in
                if isCapturing {
                    appState.suspendHotkeyMonitoringForShortcutCapture()
                } else {
                    appState.resumeHotkeyMonitoringAfterShortcutCapture()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shortcut Start Delay")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(appState.shortcutStartDelayMilliseconds) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $appState.shortcutStartDelay,
                    in: 0...0.5,
                    step: 0.025
                )

                Text("Applies before recording starts for both hold and tap shortcuts. Stopping still happens immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    action()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
