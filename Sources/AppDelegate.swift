import Combine
import SwiftUI
import UserNotifications

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        keyEquivalent: String = "",
        imageName: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction), keyEquivalent: keyEquivalent)
        target = self
        if let imageName {
            image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            image?.isTemplate = true
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction() {
        handler()
    }
}

private final class AgentUtilityOverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var agentWindow: NSWindow?
    private var agentUtilityOverlayWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusIconCancellable: AnyCancellable?
    private var menuBarIconVisibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        configureStatusItem()
        installStatusItemObservers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSetup),
            name: .showSetup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettings),
            name: .showSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowWordPressAgent),
            name: .showWordPressAgent,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowWordPressAgentUtilityOverlay),
            name: .showWordPressAgentUtilityOverlay,
            object: nil
        )

        if !appState.hasCompletedSetup {
            showSetupWindow()
        } else {
            appState.startHotkeyMonitoring()
            appState.startAccessibilityPolling()
            if !AXIsProcessTrusted() {
                appState.showAccessibilityAlert()
            }
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let menuBarIconVisibilityObserver {
            NotificationCenter.default.removeObserver(menuBarIconVisibilityObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard appState.hasCompletedSetup else { return true }
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    @objc func handleShowSetup() {
        appState.hasCompletedSetup = false
        appState.stopAccessibilityPolling()
        appState.stopHotkeyMonitoring()
        showSetupWindow()
    }

    @objc private func handleShowSettings() {
        showSettingsWindow()
    }

    @objc private func handleShowWordPressAgent(_ notification: Notification) {
        showWordPressAgentWindow(conversationID: notification.userInfo?["conversationID"] as? String)
    }

    @objc private func handleShowWordPressAgentUtilityOverlay() {
        showWordPressAgentUtilityOverlay()
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || !appState.isWordPressAgentEnabled {
            showStatusMenu()
            return
        }

        showWordPressAgentWindow()
    }

    private func configureStatusItem() {
        guard shouldShowMenuBarIcon else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(handleStatusItemClick(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        }

        updateStatusItemIcon()
    }

    private func installStatusItemObservers() {
        statusIconCancellable = Publishers.CombineLatest3(
            appState.$isRecording,
            appState.$isTranscribing,
            appState.$isWordPressAgentEnabled
        )
            .sink { [weak self] _, _, _ in
                self?.updateStatusItemIcon()
            }

        menuBarIconVisibilityObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureStatusItem()
        }
    }

    private var shouldShowMenuBarIcon: Bool {
        if UserDefaults.standard.object(forKey: "show_menu_bar_icon") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "show_menu_bar_icon")
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let iconName: String
        if appState.isRecording {
            iconName = "record.circle"
        } else if appState.isTranscribing {
            iconName = "ellipsis.circle"
        } else {
            iconName = "waveform"
        }

        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "WhisPress")
        image?.isTemplate = true
        button.image = image
        button.toolTip = appState.isWordPressAgentEnabled
            ? "Open WordPress Agent"
            : "WhisPress"
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        statusItem.menu = makeStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusMenu() -> NSMenu {
        appState.refreshLatestExternalAppSnapshot()

        let menu = NSMenu()
        menu.autoenablesItems = false

        addDisabledItem("WhisPress v\(appVersion)", to: menu)
        menu.addItem(.separator())

        if !appState.isWordPressComSignedIn || appState.selectedWordPressComSiteID == nil {
            menu.addItem(actionItem("WordPress.com Sign-In Needed", imageName: "person.crop.circle.badge.exclamationmark") { [weak self] in
                self?.appState.selectedSettingsTab = .wordpressCom
                NotificationCenter.default.post(name: .showSettings, object: nil)
            })
            menu.addItem(.separator())
        }

        if !appState.hasAccessibility {
            menu.addItem(actionItem("Accessibility Required", imageName: "exclamationmark.triangle.fill") { [weak self] in
                self?.appState.showAccessibilityAlert()
            })
            menu.addItem(.separator())
        }

        addDisabledItem(statusMenuTitle, to: menu)

        menu.addItem(.separator())
        let openOverlayItem = actionItem("Quick Ask WordPress Agent", imageName: "text.bubble") { [weak self] in
            self?.showWordPressAgentUtilityOverlay()
        }
        openOverlayItem.isEnabled = appState.isWordPressComSignedIn
            && !appState.isRecording
            && !appState.isTranscribing
        menu.addItem(openOverlayItem)

        if let appConfigItem = currentAppConfigMenuItem() {
            menu.addItem(.separator())
            menu.addItem(appConfigItem)
        }

        menu.addItem(.separator())
        let dictationTitle = appState.isRecording ? "Stop Recording" : "Start Dictating"
        let dictationItem = actionItem(dictationTitle) { [weak self] in
            self?.appState.toggleRecording()
        }
        dictationItem.isEnabled = !appState.isTranscribing
        menu.addItem(dictationItem)

        if let hotkeyError = appState.hotkeyMonitoringErrorMessage, !hotkeyError.isEmpty {
            addDisabledItem(truncateMenuText(hotkeyError), to: menu)
        }

        if let error = appState.errorMessage, !error.isEmpty {
            addDisabledItem(truncateMenuText(error), to: menu)
        }

        if !appState.lastAgentResponse.isEmpty && !appState.isRecording && !appState.isTranscribing {
            menu.addItem(.separator())
            addDisabledItem("WordPress Agent: \(truncateMenuText(appState.lastAgentResponse, maxLength: 72))", to: menu)
            menu.addItem(actionItem("Copy Reply") { [weak self] in
                guard let response = self?.appState.lastAgentResponse else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(response, forType: .string)
            })
        }

        if !appState.isRecording && !appState.isTranscribing {
            menu.addItem(.separator())
            let openAgentItem = actionItem("Open WordPress Agent", imageName: "sparkles") { [weak self] in
                self?.showWordPressAgentWindow()
            }
            openAgentItem.isEnabled = appState.isWordPressComSignedIn
            menu.addItem(openAgentItem)
        }

        if !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing {
            menu.addItem(.separator())
            addDisabledItem(truncateMenuText(appState.lastTranscript, maxLength: 50), to: menu)
            menu.addItem(actionItem("Copy Again") { [weak self] in
                guard let transcript = self?.appState.lastTranscript else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            })
        }

        menu.addItem(.separator())
        menu.addItem(submenuItem(title: "Hold Shortcut", submenu: shortcutMenu(for: .hold)))
        menu.addItem(submenuItem(title: "Toggle Shortcut", submenu: shortcutMenu(for: .toggle)))
        menu.addItem(submenuItem(title: "Agent Overlay Shortcut", submenu: shortcutMenu(for: .agentUtilityOverlay)))
        menu.addItem(submenuItem(title: "Microphone", submenu: microphoneMenu()))

        menu.addItem(.separator())
        menu.addItem(actionItem("Re-run Setup...") {
            NotificationCenter.default.post(name: .showSetup, object: nil)
        })
        menu.addItem(actionItem("Settings") {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        })

        menu.addItem(.separator())
        menu.addItem(actionItem(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") { [weak self] in
            self?.appState.toggleDebugOverlay()
        })
        menu.addItem(actionItem("Quit WhisPress", keyEquivalent: "q") {
            NSApplication.shared.terminate(nil)
        })

        return menu
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var statusMenuTitle: String {
        if appState.isRecording {
            return "Recording..."
        }
        if appState.isTranscribing {
            return appState.debugStatusMessage
        }
        return appState.shortcutStatusText
    }

    private func currentAppConfigMenuItem() -> NSMenuItem? {
        guard appState.isWordPressComSignedIn,
              !appState.wordpressComSites.isEmpty,
              let snapshot = appState.latestExternalAppSnapshot,
              let bundleIdentifier = snapshot.bundleIdentifier else {
            return nil
        }

        let override = appState.wordPressComAppSiteOverride(for: bundleIdentifier)
        let effectiveSite = appState.effectiveWordPressComSite(for: bundleIdentifier)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        addDisabledItem(bundleIdentifier, to: submenu)
        addDisabledItem(configSummary(site: effectiveSite, isOverride: override != nil), to: submenu)
        submenu.addItem(.separator())

        let useDefaultItem = actionItem("Use Default Workspace") { [weak self] in
            self?.appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
        }
        useDefaultItem.state = override == nil ? .on : .off
        submenu.addItem(useDefaultItem)

        let pinItem = actionItem("Pin Default Workspace to This App") { [weak self] in
            self?.appState.assignSelectedWordPressComSiteToLatestExternalApp()
        }
        pinItem.isEnabled = appState.selectedWordPressComSiteID != nil
        submenu.addItem(pinItem)

        if override != nil {
            submenu.addItem(actionItem("Remove App-Specific Workspace") { [weak self] in
                self?.appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
            })
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem("Manage Workspaces in Settings...") {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        })

        let item = submenuItem(
            title: "App: \(snapshot.appName ?? bundleIdentifier)",
            submenu: submenu
        )
        item.image = NSImage(systemSymbolName: override == nil ? "app" : "pin.fill", accessibilityDescription: nil)
        item.image?.isTemplate = true
        return item
    }

    private func shortcutMenu(for role: ShortcutRole) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let currentBinding: ShortcutBinding
        let otherBindings: [ShortcutBinding]
        switch role {
        case .hold:
            currentBinding = appState.holdShortcut
            otherBindings = [appState.toggleShortcut, appState.agentUtilityOverlayShortcut]
        case .toggle:
            currentBinding = appState.toggleShortcut
            otherBindings = [appState.holdShortcut, appState.agentUtilityOverlayShortcut]
        case .agentUtilityOverlay:
            currentBinding = appState.agentUtilityOverlayShortcut
            otherBindings = [appState.holdShortcut, appState.toggleShortcut]
        }

        let disabledItem = actionItem("Disabled") { [weak self] in
            _ = self?.appState.setShortcut(.disabled, for: role)
        }
        disabledItem.state = currentBinding.isDisabled ? .on : .off
        disabledItem.isEnabled = role == .agentUtilityOverlay
            || !(role == .hold ? appState.toggleShortcut : appState.holdShortcut).isDisabled
        menu.addItem(disabledItem)

        for preset in ShortcutPreset.allCases {
            let item = actionItem(preset.title) { [weak self] in
                _ = self?.appState.setShortcut(preset.binding, for: role)
            }
            item.state = currentBinding == preset.binding ? .on : .off
            item.isEnabled = !otherBindings.contains { preset.binding.conflicts(with: $0) }
            menu.addItem(item)
        }

        if let savedCustomShortcut = appState.savedCustomShortcut(for: role) {
            menu.addItem(.separator())
            let item = actionItem("Custom: \(savedCustomShortcut.displayName)") { [weak self] in
                _ = self?.appState.setShortcut(savedCustomShortcut, for: role)
            }
            item.state = currentBinding == savedCustomShortcut ? .on : .off
            item.isEnabled = !otherBindings.contains { savedCustomShortcut.conflicts(with: $0) }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Customize...") {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        })
        return menu
    }

    private func microphoneMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let systemDefaultItem = actionItem("System Default") { [weak self] in
            self?.appState.selectedMicrophoneID = "default"
        }
        systemDefaultItem.state = appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty
            ? .on
            : .off
        menu.addItem(systemDefaultItem)

        for device in appState.availableMicrophones {
            let item = actionItem(device.name) { [weak self] in
                self?.appState.selectedMicrophoneID = device.uid
            }
            item.state = appState.selectedMicrophoneID == device.uid ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func actionItem(
        _ title: String,
        keyEquivalent: String = "",
        imageName: String? = nil,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        ActionMenuItem(
            title: title,
            keyEquivalent: keyEquivalent,
            imageName: imageName,
            handler: handler
        )
    }

    private func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func addDisabledItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func configSummary(site: WPCOMSite?, isOverride: Bool) -> String {
        let siteName = site?.displayName ?? "No workspace selected"
        return isOverride ? "Pinned: \(siteName)" : "Default: \(siteName)"
    }

    private func truncateMenuText(_ text: String, maxLength: Int = 90) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)

        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if settingsWindow == nil {
            presentSettingsWindow()
        } else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func presentSettingsWindow() {
        let settingsView = SettingsView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisPress"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
            if self?.setupWindow == nil && self?.agentWindow == nil && self?.agentUtilityOverlayWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func showWordPressAgentUtilityOverlay() {
        guard appState.isWordPressComSignedIn else {
            appState.selectedSettingsTab = .wordpressCom
            showSettingsWindow()
            return
        }

        NSApp.setActivationPolicy(.regular)

        if let agentUtilityOverlayWindow, agentUtilityOverlayWindow.isVisible {
            agentUtilityOverlayWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.setWordPressAgentUtilityOverlayFocused(agentUtilityOverlayWindow.isKeyWindow)
            return
        }

        if agentUtilityOverlayWindow == nil {
            presentWordPressAgentUtilityOverlay()
        } else {
            agentUtilityOverlayWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.setWordPressAgentUtilityOverlayFocused(agentUtilityOverlayWindow?.isKeyWindow == true)
        }
    }

    private func presentWordPressAgentUtilityOverlay() {
        let overlayView = WordPressAgentUtilityOverlayView(
            onSubmit: { [weak self] conversationID in
                self?.dismissWordPressAgentUtilityOverlay(restoreActivationPolicy: false)
                self?.showWordPressAgentWindow(conversationID: conversationID)
            },
            onDismiss: { [weak self] in
                self?.dismissWordPressAgentUtilityOverlay()
            }
        )
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        let contentSize = NSSize(width: 560, height: 96)
        hostingView.setFrameSize(contentSize)
        let window = AgentUtilityOverlayPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Ask WordPress Agent"
        window.contentView = hostingView
        window.onCancel = { [weak self] in
            self?.dismissWordPressAgentUtilityOverlay()
        }
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        positionAgentUtilityOverlay(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        agentUtilityOverlayWindow = window
        appState.setWordPressAgentUtilityOverlayFocused(window.isKeyWindow)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentUtilityOverlayFocused(true)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentUtilityOverlayFocused(false)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentUtilityOverlayFocused(false)
            self?.agentUtilityOverlayWindow = nil
            if self?.setupWindow == nil && self?.settingsWindow == nil && self?.agentWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func dismissWordPressAgentUtilityOverlay(restoreActivationPolicy: Bool = true) {
        appState.setWordPressAgentUtilityOverlayFocused(false)
        agentUtilityOverlayWindow?.close()
        agentUtilityOverlayWindow = nil
        if restoreActivationPolicy && setupWindow == nil && settingsWindow == nil && agentWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func positionAgentUtilityOverlay(_ window: NSWindow) {
        let screenFrame = screenForAgentUtilityOverlay.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: min(screenFrame.maxY - size.height - 72, screenFrame.midY + 120)
        )
        window.setFrameOrigin(origin)
    }

    private var screenForAgentUtilityOverlay: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showWordPressAgentWindow(conversationID: String? = nil) {
        dismissWordPressAgentUtilityOverlay(restoreActivationPolicy: false)
        NSApp.setActivationPolicy(.regular)

        if let conversationID {
            appState.selectWordPressAgentConversation(conversationID)
        } else {
            _ = appState.startWordPressAgentConversation()
        }

        if let agentWindow, agentWindow.isVisible {
            agentWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.setWordPressAgentWindowFocused(agentWindow.isKeyWindow)
            return
        }

        if agentWindow == nil {
            presentWordPressAgentWindow()
        } else {
            agentWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.setWordPressAgentWindowFocused(agentWindow?.isKeyWindow == true)
        }
    }

    private func presentWordPressAgentWindow() {
        let agentView = WordPressAgentWindowView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: agentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "WordPress Agent"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 620)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        agentWindow = window
        appState.setWordPressAgentWindowFocused(window.isKeyWindow)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentWindowFocused(true)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentWindowFocused(false)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.appState.setWordPressAgentWindowFocused(false)
            self?.agentWindow = nil
            if self?.setupWindow == nil
                && self?.settingsWindow == nil
                && self?.agentUtilityOverlayWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }


    func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)

        let setupView = SetupView(onComplete: { [weak self] in
            self?.completeSetup()
        })
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisPress"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: setupView)
        window.minSize = NSSize(width: 520, height: 680)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        self.setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func completeSetup() {
        appState.hasCompletedSetup = true
        setupWindow?.close()
        setupWindow = nil
        NSApp.setActivationPolicy(.accessory)
        appState.startHotkeyMonitoring()
        appState.startAccessibilityPolling()
        if !AXIsProcessTrusted() {
            appState.showAccessibilityAlert()
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let conversationID = response.notification.request.content.userInfo["conversationID"] as? String
        DispatchQueue.main.async { [weak self] in
            self?.showWordPressAgentWindow(conversationID: conversationID)
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
