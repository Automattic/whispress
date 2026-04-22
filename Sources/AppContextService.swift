import Foundation
import ApplicationServices
import AppKit

struct AppSelectionSnapshot {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
}

struct AppContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String
    let contextPrompt: String?
    let screenshotDataURL: String?
    let screenshotMimeType: String?
    let screenshotError: String?

    var contextSummary: String {
        currentActivity
    }
}

final class AppContextService {
    func collectSelectionSnapshot() -> AppSelectionSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppSelectionSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return AppSelectionSnapshot(
            appName: frontmostApp.localizedName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: focusedWindowTitle(from: appElement) ?? frontmostApp.localizedName,
            selectedText: rawSelectedText(from: appElement)
        )
    }

    func collectContext() async -> AppContext {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                currentActivity: "You are dictating in an unrecognized context.",
                contextPrompt: nil,
                screenshotDataURL: nil,
                screenshotMimeType: nil,
                screenshotError: "No frontmost application"
            )
        }

        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = selectedText(from: appElement)
        let currentActivity = deterministicCurrentActivity(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            selectedText: selectedText,
            windowTitle: windowTitle
        )

        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            currentActivity: currentActivity,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )
    }

    private func deterministicCurrentActivity(
        appName: String?,
        bundleIdentifier: String?,
        selectedText: String?,
        windowTitle: String?
    ) -> String {
        let app = appName ?? "the active application"
        let window = windowTitle ?? "unknown window"
        let selection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "Selected text is available."
            : "No selected text was detected."
        let bundle = bundleIdentifier.map { " Bundle ID: \($0)." } ?? ""
        return "The user is dictating in \(app), window: \(window).\(bundle) \(selection)"
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        if let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) {
            return trimmedText(windowTitle)
        }

        return nil
    }

    private func selectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        if let selectedText = accessibilityString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        return nil
    }

    private func rawSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityRawString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        if let selectedText = accessibilityRawString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        return nil
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
        return trimmedText(stringValue)
    }

    private func accessibilityRawString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue.isEmpty ? nil : stringValue
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }
}
