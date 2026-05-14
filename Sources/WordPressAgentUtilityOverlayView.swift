import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WordPressAgentUtilityOverlayView: View {
    @EnvironmentObject var appState: AppState

    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var draftMessage = ""
    @State private var pendingImageURLs: [URL] = []
    @State private var composerTextHeight: CGFloat = 44
    @FocusState private var isPromptFocused: Bool

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
        guard let activeSiteID else { return appState.selectedWordPressComSite }
        return appState.wordpressComSites.first(where: { $0.id == activeSiteID })
            ?? appState.selectedWordPressComSite
    }

    private var siteTitle: String {
        activeSite?.displayName ?? "Choose your site"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pendingImageURLs.isEmpty {
                UtilityOverlayAttachmentStrip(fileURLs: pendingImageURLs) { url in
                    pendingImageURLs.removeAll { $0 == url }
                }
            }

            composerTextView

            HStack(spacing: 12) {
                Button {
                    selectImages()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add images")
                .disabled(isComposerDisabled)

                Button {
                    appState.showWordPressAgentWindow()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .medium))
                        Text(siteTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 176, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open WordPress Agent")

                Spacer(minLength: 10)

                if selectedConversation?.isSending == true || appState.isTranscribing {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .help("Working")
                }

                Button {
                    appState.toggleRecording()
                } label: {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 28, height: 28)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.067, green: 0.467, blue: 0.800).opacity(0.72), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
        .onExitCommand {
            onDismiss()
        }
    }

    private var canSendMessage: Bool {
        (Self.containsNonWhitespace(draftMessage) || !pendingImageURLs.isEmpty)
        && !isComposerDisabled
    }

    private var isComposerDisabled: Bool {
        activeSiteID == nil
            || selectedConversation?.isSending == true
            || appState.isTranscribing
    }

    private var composerTextView: some View {
        ZStack(alignment: .topLeading) {
            AgentComposerTextView(
                text: $draftMessage,
                isFocused: Binding(
                    get: { isPromptFocused },
                    set: { isPromptFocused = $0 }
                ),
                height: $composerTextHeight,
                fontSize: 15,
                minimumHeight: 44,
                maximumHeight: 160,
                isDisabled: isComposerDisabled,
                onSubmit: sendDraftMessage
            )
            .frame(height: composerTextHeight)

            if draftMessage.isEmpty {
                Text("Ask WordPress Agent")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    private func sendDraftMessage() {
        guard canSendMessage else { return }
        let message = draftMessage
        let attachments = pendingImageURLs
        draftMessage = ""
        pendingImageURLs = []
        guard let conversationID = appState.submitWordPressAgentComposerMessage(
            message,
            attachments: attachments,
            siteID: activeSiteID,
            startsNewConversation: true
        ) else {
            draftMessage = message
            pendingImageURLs = attachments
            return
        }

        onSubmit(conversationID)
    }

    private static func containsNonWhitespace(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace && !$0.isNewline }
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
        isPromptFocused = true
    }
}

private struct UtilityOverlayAttachmentStrip: View {
    let fileURLs: [URL]
    let onRemove: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileURLs, id: \.self) { url in
                    UtilityOverlayAttachmentPill(fileURL: url) {
                        onRemove(url)
                    }
                }
            }
        }
        .frame(height: 34)
    }
}

private struct UtilityOverlayAttachmentPill: View {
    let fileURL: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            Text(fileURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.leading, 5)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AgentPalette.softControl)
        )
    }
}
