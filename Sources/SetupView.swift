import SwiftUI
import AVFoundation
import Combine
import Foundation
import ServiceManagement

struct SetupView: View {
    var onComplete: () -> Void
    @EnvironmentObject var appState: AppState
    private enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case account
        case agentOverlay
        case imageUpload
        case micPermission
        case accessibility
        case holdShortcut
        case toggleShortcut
        case testTranscription
        case launchAtLogin
        case ready
    }

    @State private var currentStep = SetupStep.welcome
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var keyValidationError: String?
    @State private var accessibilityTimer: Timer?

    // Test transcription state
    private enum TestPhase: Equatable {
        case idle, recording, transcribing, done
    }
    @State private var testPhase: TestPhase = .idle
    @State private var testAudioRecorder: AudioRecorder? = nil
    @State private var testAudioLevel: Float = 0.0
    @State private var testTranscript: String = ""
    @State private var testError: String? = nil
    @State private var testAudioLevelCancellable: AnyCancellable? = nil
    @State private var testMicPulsing = false
    @State private var holdShortcutValidationMessage: String?
    @State private var toggleShortcutValidationMessage: String?
    @State private var agentUtilityOverlayValidationMessage: String?
    @State private var isCapturingHoldShortcut = false
    @State private var isCapturingToggleShortcut = false
    @State private var isCapturingAgentUtilityOverlayShortcut = false
    @StateObject private var testHotkeyHarness = SetupTestHotkeyHarness()

    private let totalSteps: [SetupStep] = SetupStep.allCases
    private var isCapturingShortcut: Bool {
        isCapturingHoldShortcut
            || isCapturingToggleShortcut
            || isCapturingAgentUtilityOverlayShortcut
    }

    var body: some View {
        VStack(spacing: 0) {
            currentStepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 32)

            Divider()

            ZStack {
                stepIndicator

                HStack(alignment: .center) {
                    Group {
                        if currentStep != .welcome {
                            Button("Back") {
                                keyValidationError = nil
                                withAnimation {
                                    currentStep = previousStep(currentStep)
                                }
                            }
                        }
                    }

                    Spacer()

                    Group {
                        if currentStep != .ready {
                            if currentStep == .testTranscription {
                                HStack(spacing: 10) {
                                    Button("Skip") {
                                        stopTestHotkeyMonitoring()
                                        withAnimation {
                                            currentStep = nextStep(currentStep)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)

                                    Button("Continue") {
                                        stopTestHotkeyMonitoring()
                                        withAnimation {
                                            currentStep = nextStep(currentStep)
                                        }
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(testPhase != .done || testTranscript.isEmpty || testError != nil)
                                }
                            } else {
                                Button(continueButtonTitle) {
                                    withAnimation {
                                        currentStep = nextStep(currentStep)
                                    }
                                }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canContinueFromCurrentStep)
                            }
                        } else {
                            Button("Open WordPress Agent") {
                                onComplete()
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 520, height: 680)
        .font(WordPressWorkspaceBrand.bodyFont(size: 14))
        .tint(WordPressWorkspaceBrand.blue)
        .onAppear {
            checkMicPermission()
            checkAccessibility()
            appState.refreshWordPressComSitesFromUI()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkAccessibility()
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
            appState.resumeHotkeyMonitoringAfterShortcutCapture()
        }
        .onChange(of: isCapturingShortcut) { isCapturing in
            if isCapturing {
                appState.suspendHotkeyMonitoringForShortcutCapture()
            } else {
                appState.resumeHotkeyMonitoringAfterShortcutCapture()
            }
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .account:
            accountStep
        case .micPermission:
            micPermissionStep
        case .accessibility:
            accessibilityStep
        case .holdShortcut:
            holdShortcutStep
        case .toggleShortcut:
            toggleShortcutStep
        case .launchAtLogin:
            launchAtLoginStep
        case .imageUpload:
            imageUploadStep
        case .agentOverlay:
            agentOverlayStep
        case .testTranscription:
            testTranscriptionStep
        case .ready:
            readyStep
        }
    }

    // MARK: - Steps

    var welcomeStep: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            WordPressWorkspaceWelcomeMark()

            VStack(spacing: 10) {
                Text("Welcome to\nWordPress Workspace")
                    .font(WordPressWorkspaceBrand.displayFont(size: 39))
                    .lineSpacing(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WordPressWorkspaceBrand.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Turn your WordPress.com site into a workspace on your Mac.")
                    .font(WordPressWorkspaceBrand.bodyFont(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

        }
    }

    var accountStep: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                WordPressComLogoMark()
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)

                Text("Choose a default site")
                    .font(WordPressWorkspaceBrand.displayFont(size: 32))
                    .multilineTextAlignment(.center)

                Text("This is only the starting site for new chats, uploads, screenshots, and dictation. You can switch sites anytime in WordPress Agent.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    if appState.isWordPressComSignedIn {
                        Label("Signed in to WordPress.com", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            appState.signInToWordPressCom()
                        } label: {
                            if appState.isSigningInToWordPressCom {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Signing in...")
                                }
                            } else {
                                Label("Sign in with WordPress.com", systemImage: "person.crop.circle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        appState.refreshWordPressComSitesFromUI()
                    } label: {
                        if appState.isRefreshingWordPressComSites {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading sites...")
                            }
                        } else {
                            Label("Refresh Sites", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(!appState.isWordPressComSignedIn || appState.isRefreshingWordPressComSites)

                    if !appState.wordpressComSites.isEmpty {
                        Text("Default Site")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        WordPressSiteSearchPicker(
                            sites: appState.wordpressComSitesSortedByStarred,
                            selectedSiteID: Binding(
                                get: { appState.selectedWordPressComSiteID },
                                set: { appState.selectedWordPressComSiteID = $0 }
                            ),
                            maxVisibleRows: 4
                        )
                    }

                    if let message = appState.wordpressComStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 440)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var micPermissionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Microphone Access")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Microphone access enables dictation. You can skip this and still use Quick Ask, uploads, screenshots, and site workflows.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "mic.fill")
                    .frame(width: 24)
                    .foregroundStyle(WordPressWorkspaceBrand.blue)
                Text("Microphone")
                Spacer()
                if micPermissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Access") {
                        requestMicPermission()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            if !micPermissionGranted {
                Text("You can enable the microphone later from Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        }
    }

    var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Accessibility Access")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("WP Workspace needs Accessibility access to transform selected text and paste results into your apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "hand.raised.fill")
                    .frame(width: 24)
                    .foregroundStyle(WordPressWorkspaceBrand.blue)
                Text("Accessibility")
                Spacer()
                if accessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Button("Check Again") {
                            checkAccessibility()
                        }

                        Button("Open Settings") {
                            requestAccessibility()
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

        }
        .onAppear {
            startAccessibilityPolling()
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
        }
    }

    var holdShortcutStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Hold to Talk Shortcut")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Choose the shortcut you want to hold while speaking.\nRelease it to stop unless you latch into tap mode later, or disable hold-to-talk entirely.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutRoleSection(
                role: .hold,
                selection: appState.holdShortcut,
                validationMessage: holdShortcutValidationMessage,
                isCapturing: $isCapturingHoldShortcut,
                onSelect: { binding in
                    holdShortcutValidationMessage = appState.setShortcut(binding, for: .hold)
                }
            )
                .padding(.top, 10)

            if appState.holdShortcut.usesFnKey {
                Text("Tip: If Fn opens Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

        }
    }

    var toggleShortcutStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "switch.2")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Tap to Toggle Shortcut")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Choose the shortcut you want to tap once to start dictating and tap again to stop.\nIf this shortcut becomes active while you are holding the hold shortcut, Workspace latches into tap mode. You can also disable tap-to-toggle entirely.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutRoleSection(
                role: .toggle,
                selection: appState.toggleShortcut,
                validationMessage: toggleShortcutValidationMessage,
                isCapturing: $isCapturingToggleShortcut,
                onSelect: { binding in
                    toggleShortcutValidationMessage = appState.setShortcut(binding, for: .toggle)
                }
            )
                .padding(.top, 10)

            if appState.toggleShortcut.usesFnKey {
                Text("Tip: If Fn opens Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

        }
    }

    var launchAtLoginStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Launch at Login")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Start WP Workspace automatically when you log in so it's always ready.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "sunrise.fill")
                    .frame(width: 24)
                    .foregroundStyle(WordPressWorkspaceBrand.blue)
                Toggle("Launch WP Workspace at login", isOn: $appState.launchAtLogin)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

        }
    }

    var imageUploadStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(WordPressWorkspaceBrand.blue)

            Text("Add Images to Your Site")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Try an upload now to see how Workspace adds images to your WordPress.com media library. You can copy the link or open the images in a WordPress Agent chat.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appState.showImageUploadPicker()
            } label: {
                Label("Choose Images", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.isWordPressComSignedIn || appState.selectedWordPressComSiteID == nil)

            Text("Later, drop images onto the menu bar icon to upload without opening this window.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    var agentOverlayStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(WordPressWorkspaceBrand.blue)

                Text("Quick Ask")
                    .font(WordPressWorkspaceBrand.displayFont(size: 30))

                Text("Open the floating WordPress Agent overlay to ask about your site from anywhere on your Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    appState.showWordPressAgentUtilityOverlay()
                } label: {
                    Label("Open Quick Ask", systemImage: "text.bubble")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.isWordPressComSignedIn || appState.selectedWordPressComSiteID == nil)

                ShortcutRoleSection(
                    role: .agentUtilityOverlay,
                    selection: appState.agentUtilityOverlayShortcut,
                    validationMessage: agentUtilityOverlayValidationMessage,
                    isCapturing: $isCapturingAgentUtilityOverlayShortcut,
                    onSelect: { binding in
                        agentUtilityOverlayValidationMessage = appState.setShortcut(binding, for: .agentUtilityOverlay)
                    }
                )
                .frame(maxWidth: 360)
                .padding(.top, 6)

                if appState.agentUtilityOverlayShortcut.usesFnKey {
                    Text("Tip: If Fn opens Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Text("The overlay supports typed prompts, image attachments, and dictation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var testTranscriptionStep: some View {
        VStack(spacing: 20) {
            // Microphone picker
            VStack(spacing: 4) {
                Picker("Microphone:", selection: $appState.selectedMicrophoneID) {
                    Text("System Default").tag("default")
                    ForEach(appState.availableMicrophones) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .frame(maxWidth: 340)

                Text("You can change this later in the menu bar or settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Group {
                switch testPhase {
                case .idle:
                    VStack(spacing: 20) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(WordPressWorkspaceBrand.blue)
                            .scaleEffect(testMicPulsing ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: testMicPulsing)

                        Text("Try Dictation")
                            .font(WordPressWorkspaceBrand.displayFont(size: 30))

                        Text(testShortcutPrompt)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(WordPressWorkspaceBrand.blue.opacity(0.1))
                            .cornerRadius(10)

                        Text("Say anything when voice is the fastest way to get words down.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .recording:
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(WordPressWorkspaceBrand.blue.opacity(0.65))
                                .frame(width: 100, height: 100)

                            Circle()
                                .stroke(WordPressWorkspaceBrand.blue.opacity(0.8), lineWidth: 3)
                                .frame(width: 100, height: 100)
                                .shadow(color: WordPressWorkspaceBrand.blue.opacity(0.5), radius: 10)

                            WaveformView(audioLevel: testAudioLevel)
                        }

                        Text("Listening...")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(WordPressWorkspaceBrand.blue)
                    }

                case .transcribing:
                    VStack(spacing: 20) {
                        InlineTranscribingDots()

                        Text("Transcribing...")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                case .done:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        if let error = testError {
                            Text("Something went wrong")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if testTranscript.isEmpty {
                            Text("No speech detected")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Perfect — Workspace is ready to go.")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(testTranscript)
                                .font(.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                                .transition(.move(edge: .bottom).combined(with: .opacity))

                            Text(retryShortcutPrompt)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .transition(.opacity)
            .id(testPhase)

            Spacer()
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
            testMicPulsing = true
            startTestHotkeyMonitoring()
        }
        .onDisappear {
            stopTestHotkeyMonitoring()
        }
    }

    var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(WordPressWorkspaceBrand.displayFont(size: 30))

            Text("Open the WordPress Agent to get started. After you close it, WP Workspace keeps running in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                if appState.hasEnabledAgentUtilityOverlayShortcut {
                    HowToRow(icon: "text.bubble", text: "Press \(appState.agentUtilityOverlayShortcut.displayName) for Quick Ask")
                } else {
                    HowToRow(icon: "text.bubble", text: "Open Quick Ask from the menu bar")
                }
                HowToRow(icon: "camera.viewfinder", text: "Upload images or capture screenshots for your site")
                if micPermissionGranted {
                    if appState.hasEnabledHoldShortcut {
                        HowToRow(icon: "keyboard", text: "Hold \(appState.holdShortcut.displayName) to dictate")
                    }
                    if appState.hasEnabledToggleShortcut {
                        HowToRow(icon: "switch.2", text: "Tap \(appState.toggleShortcut.displayName) to dictate hands-free")
                    }
                    if appState.hasEnabledHoldShortcut && appState.hasEnabledToggleShortcut {
                        HowToRow(icon: "arrow.triangle.branch", text: "While holding, press the toggle shortcut to latch on")
                    }
                } else {
                    HowToRow(icon: "mic", text: "Enable microphone access later to use dictation")
                }
                HowToRow(icon: "doc.on.clipboard", text: "Text is typed at your cursor & copied")
            }
            .padding(.top, 10)

        }
    }

    var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(totalSteps, id: \.rawValue) { step in
                Circle()
                    .fill(step == currentStep ? WordPressWorkspaceBrand.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var canContinueFromCurrentStep: Bool {
        if isCapturingShortcut {
            return false
        }

        switch currentStep {
        case .account:
            return appState.isWordPressComSignedIn && appState.selectedWordPressComSiteID != nil
        case .accessibility:
            return accessibilityGranted
        case .testTranscription:
            return testPhase == .done && !testTranscript.isEmpty && testError == nil
        default:
            return true
        }
    }

    private var continueButtonTitle: String {
        currentStep == .micPermission && !micPermissionGranted ? "Skip for Now" : "Continue"
    }

    private var testShortcutPrompt: String {
        switch (appState.hasEnabledHoldShortcut, appState.hasEnabledToggleShortcut) {
        case (true, true):
            return "Hold \(appState.holdShortcut.displayName) or tap \(appState.toggleShortcut.displayName)"
        case (true, false):
            return "Hold \(appState.holdShortcut.displayName)"
        case (false, true):
            return "Tap \(appState.toggleShortcut.displayName)"
        case (false, false):
            return "Use Start Dictating from the menu bar"
        }
    }

    private var retryShortcutPrompt: String {
        "\(testShortcutPrompt) to try again"
    }

    // MARK: - Helpers

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.subheadline)
                .tint(WordPressWorkspaceBrand.blue)
        }
    }

    // MARK: - Actions

    private func previousStep(_ step: SetupStep) -> SetupStep {
        let previous = SetupStep(rawValue: step.rawValue - 1)
        return previous ?? .welcome
    }

    private func nextStep(_ step: SetupStep) -> SetupStep {
        let next = SetupStep(rawValue: step.rawValue + 1)
        return next ?? .ready
    }

    func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermissionGranted = true
        default:
            break
        }
    }

    func requestMicPermission() {
        appState.requestMicrophoneAccess { granted in
            micPermissionGranted = granted
        }
    }

    func checkAccessibility() {
        let isTrusted = AXIsProcessTrusted()
        accessibilityGranted = isTrusted
        appState.hasAccessibility = isTrusted
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                checkAccessibility()
            }
        }
        if let accessibilityTimer {
            RunLoop.main.add(accessibilityTimer, forMode: .common)
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Test Transcription

    private func startTestHotkeyMonitoring() {
        testHotkeyHarness.onAction = { action in
            switch action {
            case .start:
                guard testPhase == .idle || testPhase == .done else { return }
                if testPhase == .done {
                    resetTest()
                }
                do {
                    let recorder = AudioRecorder()
                    recorder.onRecordingFailure = { [weak recorder] error in
                        guard let recorder else { return }
                        Task { @MainActor in
                            testAudioLevelCancellable?.cancel()
                            testAudioLevelCancellable = nil
                            testAudioLevel = 0.0
                            testHotkeyHarness.isTranscribing = false
                            testAudioRecorder = nil
                            testError = error.localizedDescription
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                testPhase = .done
                            }
                            recorder.cleanup()
                        }
                    }
                    try recorder.startRecording(deviceUID: appState.selectedMicrophoneID)
                    testAudioRecorder = recorder
                    testError = nil
                    testAudioLevelCancellable = recorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            testAudioLevel = level
                        }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .recording
                    }
                } catch {
                    testHotkeyHarness.resetSession()
                    testError = error.localizedDescription
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .done
                    }
                }

            case .stop:
                guard testPhase == .recording, let recorder = testAudioRecorder else { return }
                testAudioLevelCancellable?.cancel()
                testAudioLevelCancellable = nil
                testAudioLevel = 0.0
                testHotkeyHarness.isTranscribing = true

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    testPhase = .transcribing
                }
                recorder.stopRecording { url in
                    guard let url else {
                        Task { @MainActor in
                            testHotkeyHarness.isTranscribing = false
                            testAudioRecorder = nil
                            if testError == nil {
                                testError = "No audio file was created."
                            }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                testPhase = .done
                            }
                            recorder.cleanup()
                        }
                        return
                    }

                    Task {
                        do {
                            let transcript = try await appState.transcribeAudioForSetupTest(fileURL: url)
                            await MainActor.run {
                                testHotkeyHarness.isTranscribing = false
                                testAudioRecorder = nil
                                testTranscript = transcript
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    testPhase = .done
                                }
                            }
                        } catch {
                            await MainActor.run {
                                testHotkeyHarness.isTranscribing = false
                                testAudioRecorder = nil
                                testError = error.localizedDescription
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    testPhase = .done
                                }
                            }
                        }
                        await MainActor.run {
                            recorder.cleanup()
                        }
                    }
                }

            case .switchedToToggle:
                break
            }
        }

        do {
            try testHotkeyHarness.start(configuration: ShortcutConfiguration(
                hold: appState.holdShortcut,
                toggle: appState.toggleShortcut
            ), startDelay: appState.shortcutStartDelay)
        } catch {
            testError = error.localizedDescription
            testPhase = .done
        }
    }

    private func stopTestHotkeyMonitoring() {
        testHotkeyHarness.stop()
        testAudioLevelCancellable?.cancel()
        testAudioLevelCancellable = nil
        if let recorder = testAudioRecorder, recorder.isRecording {
            recorder.cancelRecording()
        }
        testAudioRecorder = nil
    }

    private func resetTest() {
        testPhase = .idle
        testTranscript = ""
        testError = nil
        testAudioLevel = 0.0
        testMicPulsing = true
        testHotkeyHarness.isTranscribing = false
        testHotkeyHarness.resetSession()
        if let recorder = testAudioRecorder {
            if recorder.isRecording {
                recorder.cancelRecording()
            }
            testAudioRecorder = nil
        }
    }

}

private struct InlineTranscribingDots: View {
    @State private var activeDot = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(WordPressWorkspaceBrand.blue.opacity(activeDot == index ? 1.0 : 0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(activeDot == index ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: activeDot)
            }
        }
        .onReceive(timer) { _ in
            activeDot = (activeDot + 1) % 3
        }
    }
}

struct HowToRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(WordPressWorkspaceBrand.blue)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
