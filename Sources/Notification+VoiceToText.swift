import Foundation

extension Notification.Name {
    static let showSetup = Notification.Name("showSetup")
    static let showSettings = Notification.Name("showSettings")
    static let showWordPressAgent = Notification.Name("showWordPressAgent")
    static let showWordPressAgentUtilityOverlay = Notification.Name("showWordPressAgentUtilityOverlay")
    static let showImageUploadPicker = Notification.Name("showImageUploadPicker")
    static let pasteImageIntoWordPressAgentComposer = Notification.Name("pasteImageIntoWordPressAgentComposer")
}

final class WordPressAgentComposerPasteRequest {
    var handled = false
}
