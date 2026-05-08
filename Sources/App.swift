import SwiftUI

@main
struct WPWorkspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        WordPressWorkspaceBrand.registerFonts()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
