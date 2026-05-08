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
                case .wordpressCom:
                    GeneralSettingsView(tab: .wordpressCom)
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
                case .keyBindings:
                    SettingsCard("Shortcuts", icon: tab.icon) {
                        hotkeySection
                    }
                case .wordpressCom:
                    SettingsCard("WordPress.com", icon: tab.icon, usesWordPressComLogo: true) {
                        wordpressComSection
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
                        sites: appState.wordpressComSites,
                        selectedSiteID: Binding(
                            get: { appState.selectedWordPressComSiteID },
                            set: { appState.selectedWordPressComSiteID = $0 }
                        ),
                        maxVisibleRows: 6
                    )
                }
            }

            HStack(spacing: 10) {
                if appState.transcribeSkill != nil {
                    Label("Transcribe skill found", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Transcribe Skill") {
                        appState.openTranscribeSkill()
                    }
                    .font(.caption)
                } else if appState.selectedWordPressComSiteID != nil {
                    Text("The AI transcription endpoint will create the Transcribe skill on first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !appState.wordpressComSites.isEmpty {
                appSiteOverridesSection
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

            Text("Enables Quick Ask and lets voice requests route to the WordPress Agent instead of always pasting text.")
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

            let storedOverrides = appState.wordpressComAppSiteOverrides.filter {
                $0.bundleIdentifier != appState.latestExternalAppSnapshot?.bundleIdentifier
            }
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

            ForEach(appState.wordpressComSites) { site in
                Button {
                    action(site.id)
                } label: {
                    siteMenuItem(title: site.displayName, isSelected: siteID == site.id)
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

    private func siteMenuItem(title: String, isSelected: Bool) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
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
