import Combine
import SwiftUI
import UserNotifications

private struct StatusMenuPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            MenuBarView()
                .environmentObject(appState)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .frame(width: 320, height: 620)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var agentWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var menuBarPopover: NSPopover?
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

    @objc private func handleStatusItemClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || !appState.isWordPressAgentEnabled {
            toggleMenuBarPopover()
            return
        }

        menuBarPopover?.performClose(nil)
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
        statusIconCancellable = appState.$isRecording
            .combineLatest(appState.$isTranscribing)
            .sink { [weak self] _ in
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

    private func toggleMenuBarPopover() {
        guard let button = statusItem?.button else { return }

        if menuBarPopover?.isShown == true {
            menuBarPopover?.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: StatusMenuPopoverView()
                .environmentObject(appState)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        menuBarPopover = popover
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
            if self?.setupWindow == nil && self?.agentWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func showWordPressAgentWindow(conversationID: String? = nil) {
        NSApp.setActivationPolicy(.regular)

        appState.selectWordPressAgentConversation(conversationID)

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
            if self?.setupWindow == nil && self?.settingsWindow == nil {
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
