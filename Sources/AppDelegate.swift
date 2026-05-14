import Combine
import CoreGraphics
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

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

private final class WordPressAgentWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if Self.isPasteKeyEvent(event), requestImagePasteIntoComposer() {
            return
        }

        super.sendEvent(event)
    }

    private func requestImagePasteIntoComposer() -> Bool {
        let request = WordPressAgentComposerPasteRequest()
        NotificationCenter.default.post(name: .pasteImageIntoWordPressAgentComposer, object: request)
        return request.handled
    }

    private static func isPasteKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let flags = event.modifierFlags
        guard flags.contains(.command),
              !flags.contains(.option),
              !flags.contains(.control),
              !flags.contains(.shift) else {
            return false
        }

        return event.keyCode == 9 || event.charactersIgnoringModifiers?.lowercased() == "v"
    }
}

private final class StatusItemDropView: NSView {
    static let preferredSize = NSSize(width: NSStatusBar.system.thickness, height: NSStatusBar.system.thickness)

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?
    var onOpenFileURLs: (([URL]) -> Void)?
    var onImageDragEntered: (() -> Void)?
    var onImageDragEnded: (() -> Void)?

    var statusImage: NSImage? {
        didSet {
            imageView.image = statusImage
        }
    }

    private let imageView = NSImageView()
    private var isDropTargeted = false {
        didSet {
            guard oldValue != isDropTargeted else { return }
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ImageDropPasteboardReader.readableTypes)

        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        imageView.isEditable = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard isDropTargeted else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).setFill()
        bounds.insetBy(dx: 2, dy: 2).roundedRect(radius: 5).fill()
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onSecondaryClick?()
        } else {
            onPrimaryClick?()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard).isEmpty else {
            return []
        }
        isDropTargeted = true
        onImageDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
        onImageDragEnded?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        isDropTargeted = false
        onOpenFileURLs?(urls)
        return true
    }
}

private final class ImageDropOverlayView: NSView {
    var onOpenFileURLs: (([URL]) -> Void)?
    var onTargetedChange: ((Bool) -> Void)?
    var onDragEnded: (() -> Void)?

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drop images to upload")
    private let subtitleLabel = NSTextField(labelWithString: "WP Workspace will ask before uploading")
    private var isDropTargeted = false {
        didSet {
            guard oldValue != isDropTargeted else { return }
            onTargetedChange?(isDropTargeted)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ImageDropPasteboardReader.readableTypes)

        imageView.image = NSImage(systemSymbolName: "arrow.down.to.line.compact", accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = isDropTargeted
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22)
            : NSColor.windowBackgroundColor.withAlphaComponent(0.94)
        background.setFill()
        bounds.roundedRect(radius: 16).fill()

        let strokeColor = isDropTargeted
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.65)
            : NSColor.separatorColor.withAlphaComponent(0.7)
        strokeColor.setStroke()
        let path = bounds.insetBy(dx: 0.5, dy: 0.5).roundedRect(radius: 16)
        path.lineWidth = 1
        path.stroke()
    }

    override func layout() {
        super.layout()

        imageView.frame = NSRect(x: (bounds.width - 30) / 2, y: bounds.height - 42, width: 30, height: 30)
        titleLabel.frame = NSRect(x: 16, y: 34, width: bounds.width - 32, height: 20)
        subtitleLabel.frame = NSRect(x: 16, y: 16, width: bounds.width - 32, height: 16)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard).isEmpty else {
            return []
        }
        isDropTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
        onDragEnded?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = ImageDropPasteboardReader.supportedImageFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        isDropTargeted = false
        onOpenFileURLs?(urls)
        return true
    }
}

private enum ImageDropPasteboardReader {
    static let readableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]

    static func supportedImageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
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

        let urlStringURLs = pasteboard.string(forType: .URL)
            .flatMap(URL.init(string:))
            .map { [$0] } ?? []

        var seenPaths = Set<String>()
        let allURLs = urls + legacyFileURLs + fileURLStringURLs + urlStringURLs
        let uniqueURLs = allURLs.filter { url in
            guard url.isFileURL else { return false }
            return seenPaths.insert(url.standardizedFileURL.path).inserted
        }

        return ImageImportProcessor.supportedImageFileURLs(from: uniqueURLs)
    }
}

private extension NSRect {
    func roundedRect(radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: self, xRadius: radius, yRadius: radius)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var agentWindow: NSWindow?
    private var agentUtilityOverlayWindow: NSWindow?
    private var imageImportWindow: NSWindow?
    private var imageDropOverlayWindow: NSWindow?
    private var imageDropOverlayCloseWorkItem: DispatchWorkItem?
    private var isImageDropOverlayTargeted = false
    private var statusItem: NSStatusItem?
    private var statusItemView: StatusItemDropView?
    private var statusIconCancellable: AnyCancellable?
    private var agentPreviewCancellable: AnyCancellable?
    private var menuBarIconVisibilityObserver: NSObjectProtocol?
    private var localMenuBarDragMonitor: Any?
    private var globalMenuBarDragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        configureStatusItem()
        installStatusItemObservers()
        installAgentPreviewObserver()
        installMenuBarDragMonitors()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowImageUploadPicker),
            name: .showImageUploadPicker,
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
        removeMenuBarDragMonitors()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard appState.hasCompletedSetup else { return true }
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenedImageURLs(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleOpenedImageURLs(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
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

    @objc private func handleShowImageUploadPicker() {
        selectImagesForUpload()
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
            closeImageDropOverlay()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
                self.statusItemView = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.length = StatusItemDropView.preferredSize.width

            let statusView = StatusItemDropView(frame: NSRect(origin: .zero, size: StatusItemDropView.preferredSize))
            statusView.onPrimaryClick = { [weak self] in
                self?.handleStatusItemClick(nil)
            }
            statusView.onSecondaryClick = { [weak self] in
                self?.showStatusMenu()
            }
            statusView.onOpenFileURLs = { [weak self] urls in
                self?.closeImageDropOverlay()
                self?.handleOpenedImageURLs(urls)
            }
            statusView.onImageDragEntered = { [weak self] in
                self?.showImageDropOverlay()
            }
            statusView.onImageDragEnded = { [weak self] in
                self?.scheduleImageDropOverlayClose(after: 0.2, force: true)
            }
            item.setValue(statusView, forKey: "view")

            statusItem = item
            statusItemView = statusView
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

    private func installMenuBarDragMonitors() {
        guard localMenuBarDragMonitor == nil, globalMenuBarDragMonitor == nil else { return }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        localMenuBarDragMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleMenuBarDragMonitorEvent(event)
            return event
        }
        globalMenuBarDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleMenuBarDragMonitorEvent(event)
        }
    }

    private func removeMenuBarDragMonitors() {
        if let localMenuBarDragMonitor {
            NSEvent.removeMonitor(localMenuBarDragMonitor)
            self.localMenuBarDragMonitor = nil
        }
        if let globalMenuBarDragMonitor {
            NSEvent.removeMonitor(globalMenuBarDragMonitor)
            self.globalMenuBarDragMonitor = nil
        }
    }

    private func handleMenuBarDragMonitorEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard isMouseNearStatusItemForDrop(),
                  !ImageDropPasteboardReader.supportedImageFileURLs(from: NSPasteboard(name: .drag)).isEmpty else {
                scheduleImageDropOverlayClose(after: 0.45)
                return
            }
            showImageDropOverlay()
        case .leftMouseUp:
            scheduleImageDropOverlayClose(after: 0.2, force: true)
        default:
            break
        }
    }

    private func isMouseNearStatusItemForDrop() -> Bool {
        guard let statusItemView,
              let window = statusItemView.window else {
            return false
        }

        let viewRect = statusItemView.convert(statusItemView.bounds, to: nil)
        let screenRect = window.convertToScreen(viewRect)
        let sensorRect = screenRect.insetBy(dx: -130, dy: -86)
        return sensorRect.contains(NSEvent.mouseLocation)
    }

    private func showImageDropOverlay() {
        guard statusItemView?.window != nil else { return }

        imageDropOverlayCloseWorkItem?.cancel()
        imageDropOverlayCloseWorkItem = nil

        if let imageDropOverlayWindow {
            positionImageDropOverlay(imageDropOverlayWindow)
            imageDropOverlayWindow.orderFrontRegardless()
            return
        }

        let overlaySize = NSSize(width: 260, height: 92)
        let overlayView = ImageDropOverlayView(frame: NSRect(origin: .zero, size: overlaySize))
        overlayView.onOpenFileURLs = { [weak self] urls in
            self?.closeImageDropOverlay()
            self?.handleOpenedImageURLs(urls)
        }
        overlayView.onTargetedChange = { [weak self] isTargeted in
            self?.isImageDropOverlayTargeted = isTargeted
            if isTargeted {
                self?.imageDropOverlayCloseWorkItem?.cancel()
                self?.imageDropOverlayCloseWorkItem = nil
            } else {
                self?.scheduleImageDropOverlayClose(after: 0.45)
            }
        }
        overlayView.onDragEnded = { [weak self] in
            self?.scheduleImageDropOverlayClose(after: 0.2, force: true)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = overlayView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        imageDropOverlayWindow = panel
        positionImageDropOverlay(panel)
        panel.orderFrontRegardless()
    }

    private func positionImageDropOverlay(_ window: NSWindow) {
        guard let statusItemView,
              let statusWindow = statusItemView.window else {
            return
        }

        let statusRect = statusWindow.convertToScreen(statusItemView.convert(statusItemView.bounds, to: nil))
        let targetScreen = statusWindow.screen ?? NSScreen.screens.first { $0.frame.intersects(statusRect) } ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? statusRect
        let size = window.frame.size
        let originX = min(
            max(statusRect.midX - size.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        let originY = min(
            statusRect.minY - size.height - 8,
            visibleFrame.maxY - size.height - 8
        )
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func scheduleImageDropOverlayClose(after delay: TimeInterval, force: Bool = false) {
        imageDropOverlayCloseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if force || (!self.isImageDropOverlayTargeted && !self.isMouseNearStatusItemForDrop()) {
                self.closeImageDropOverlay()
            }
        }
        imageDropOverlayCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func closeImageDropOverlay() {
        imageDropOverlayCloseWorkItem?.cancel()
        imageDropOverlayCloseWorkItem = nil
        isImageDropOverlayTargeted = false
        imageDropOverlayWindow?.close()
        imageDropOverlayWindow = nil
    }

    private var shouldShowMenuBarIcon: Bool {
        if UserDefaults.standard.object(forKey: "show_menu_bar_icon") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "show_menu_bar_icon")
    }

    private func updateStatusItemIcon() {
        let image: NSImage?
        if appState.isRecording {
            image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "WP Workspace")
        } else if appState.isTranscribing {
            image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "WP Workspace")
        } else {
            image = Self.menuBarWordPressLogoImage()
        }

        image?.isTemplate = true
        let toolTip = appState.isWordPressAgentEnabled
            ? "Open WordPress Agent. Drop images to upload."
            : "WP Workspace. Drop images to upload."

        if let statusItemView {
            statusItemView.statusImage = image
            statusItemView.toolTip = toolTip
            return
        }

        guard let button = statusItem?.button else { return }
        button.image = image
        button.toolTip = toolTip
    }

    private static func menuBarWordPressLogoImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarWordPressLogo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "w.circle", accessibilityDescription: "WP Workspace")
        }

        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        if let statusItemView {
            let menu = makeStatusMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusItemView.bounds.minY), in: statusItemView)
        } else {
            statusItem.menu = makeStatusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func makeStatusMenu() -> NSMenu {
        appState.refreshLatestExternalAppSnapshot()

        let menu = NSMenu()
        menu.autoenablesItems = false

        addDisabledItem("WP Workspace v\(appVersion)", to: menu)
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

        let screenshotItem = actionItem("Capture Screenshot...", imageName: "camera.viewfinder") { [weak self] in
            self?.captureScreenshotForUpload()
        }
        screenshotItem.isEnabled = !appState.isRecording && !appState.isTranscribing
        menu.addItem(screenshotItem)

        let uploadImagesItem = actionItem("Upload Images...", imageName: "photo.on.rectangle.angled") { [weak self] in
            self?.selectImagesForUpload()
        }
        uploadImagesItem.isEnabled = appState.isWordPressComSignedIn
            && !appState.isRecording
            && !appState.isTranscribing
        menu.addItem(uploadImagesItem)

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
        menu.addItem(submenuItem(title: "Microphone", submenu: microphoneMenu()))

        menu.addItem(.separator())
        menu.addItem(actionItem("Settings") {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        })

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit WP Workspace", keyEquivalent: "q") {
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

        let useDefaultItem = actionItem("Use Default Site") { [weak self] in
            self?.appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
        }
        useDefaultItem.state = override == nil ? .on : .off
        submenu.addItem(useDefaultItem)

        let pinItem = actionItem("Pin Default Site to This App") { [weak self] in
            self?.appState.assignSelectedWordPressComSiteToLatestExternalApp()
        }
        pinItem.isEnabled = appState.selectedWordPressComSiteID != nil
        submenu.addItem(pinItem)

        if override != nil {
            submenu.addItem(actionItem("Remove App-Specific Site") { [weak self] in
                self?.appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
            })
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem("Manage Sites in Settings...") {
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
        disabledItem.isEnabled = true
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
        let siteName = site?.displayName ?? "No site selected"
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
        window.title = "WP Workspace"
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
            if self?.setupWindow == nil
                && self?.agentWindow == nil
                && self?.agentUtilityOverlayWindow == nil
                && self?.imageImportWindow == nil {
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
            if self?.setupWindow == nil
                && self?.settingsWindow == nil
                && self?.agentWindow == nil
                && self?.imageImportWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func dismissWordPressAgentUtilityOverlay(restoreActivationPolicy: Bool = true) {
        appState.setWordPressAgentUtilityOverlayFocused(false)
        agentUtilityOverlayWindow?.close()
        agentUtilityOverlayWindow = nil
        if restoreActivationPolicy && setupWindow == nil && settingsWindow == nil && agentWindow == nil && imageImportWindow == nil {
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
            expandAgentWindowForPreviewIfNeeded()
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

        let window = WordPressAgentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "WordPress Agent"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = appState.wordpressAgentPreview == nil
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 620)
        window.center()
        agentWindow = window
        expandAgentWindowForPreviewIfNeeded(animated: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

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
                && self?.agentUtilityOverlayWindow == nil
                && self?.imageImportWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func handleOpenedImageURLs(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        let imageURLs = ImageImportProcessor.supportedImageFileURLs(from: fileURLs)
        guard !imageURLs.isEmpty else {
            appState.errorMessage = "WP Workspace can open image files for WordPress.com upload."
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.showImageImportWindow(fileURLs: imageURLs)
        }
    }

    private func captureScreenshotForUpload() {
        closeImageDropOverlay()

        guard ensureScreenCapturePermissionForScreenshot() else { return }

        let screenshotURL: URL
        do {
            screenshotURL = try makeScreenshotCaptureURL()
        } catch {
            appState.errorMessage = "Could not prepare a screenshot file: \(error.localizedDescription)"
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.runScreenshotCapture(to: screenshotURL)
        }
    }

    private func selectImagesForUpload() {
        closeImageDropOverlay()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }
        handleOpenedImageURLs(panel.urls)
    }

    private func ensureScreenCapturePermissionForScreenshot() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else {
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            showScreenCapturePermissionAlert()
        }
        return granted
    }

    private func showScreenCapturePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "WP Workspace needs Screen Recording permission to capture a selected screenshot area. Enable WP Workspace in System Settings, then try Capture Screenshot again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func runScreenshotCapture(to fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Int32, Error>
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-s", "-x", "-d", "-tpng", fileURL.path]
                try process.run()
                process.waitUntilExit()
                result = .success(process.terminationStatus)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                self?.handleScreenshotCaptureResult(result, fileURL: fileURL)
            }
        }
    }

    private func handleScreenshotCaptureResult(_ result: Result<Int32, Error>, fileURL: URL) {
        switch result {
        case .success:
            guard isNonEmptyFile(at: fileURL) else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            handleOpenedImageURLs([fileURL])
        case .failure(let error):
            try? FileManager.default.removeItem(at: fileURL)
            appState.errorMessage = "Screenshot capture failed: \(error.localizedDescription)"
        }
    }

    private func makeScreenshotCaptureURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WPWorkspaceScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("wpworkspace-screenshot-\(UUID().uuidString).png")
    }

    private func isNonEmptyFile(at url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? NSNumber
        return (size?.intValue ?? 0) > 0
    }

    private func showImageImportWindow(fileURLs: [URL]) {
        NSApp.setActivationPolicy(.regular)

        if let imageImportWindow {
            imageImportWindow.close()
            self.imageImportWindow = nil
        }

        let importView = ImageImportView(
            fileURLs: fileURLs,
            onCancel: { [weak self] in
                self?.imageImportWindow?.close()
            },
            onComplete: { [weak self] conversationID in
                self?.imageImportWindow?.close()
                self?.imageImportWindow = nil
                if let conversationID {
                    self?.showWordPressAgentWindow(conversationID: conversationID)
                }
            }
        )
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Upload Images"
        window.contentView = NSHostingView(rootView: importView)
        window.isReleasedWhenClosed = false
        window.center()
        imageImportWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.imageImportWindow = nil
            if self?.setupWindow == nil
                && self?.settingsWindow == nil
                && self?.agentWindow == nil
                && self?.agentUtilityOverlayWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func installAgentPreviewObserver() {
        agentPreviewCancellable = appState.$wordpressAgentPreview
            .receive(on: RunLoop.main)
            .sink { [weak self] preview in
                self?.updateAgentWindowMovability(hasPreview: preview != nil)
                if preview != nil {
                    self?.expandAgentWindowForPreviewIfNeeded()
                }
            }
    }

    private func updateAgentWindowMovability(hasPreview: Bool? = nil) {
        agentWindow?.isMovableByWindowBackground = !(hasPreview ?? (appState.wordpressAgentPreview != nil))
    }

    private func expandAgentWindowForPreviewIfNeeded(animated: Bool = true) {
        guard appState.wordpressAgentPreview != nil,
              let agentWindow else {
            return
        }

        let minimumPreviewWidth: CGFloat = 1120
        guard agentWindow.frame.width < minimumPreviewWidth else { return }

        var frame = agentWindow.frame
        frame.origin.x -= (minimumPreviewWidth - frame.width) / 2
        frame.size.width = minimumPreviewWidth
        agentWindow.setFrame(frame, display: true, animate: animated)
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
        window.title = "WP Workspace"
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
        appState.startHotkeyMonitoring()
        appState.startAccessibilityPolling()
        if !AXIsProcessTrusted() {
            appState.showAccessibilityAlert()
        }

        if appState.isWordPressComSignedIn && appState.selectedWordPressComSiteID != nil {
            showWordPressAgentWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
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
