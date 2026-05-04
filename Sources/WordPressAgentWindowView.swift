import SwiftUI

struct WordPressAgentWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var draftMessage = ""

    private var selectedConversation: WordPressAgentConversation? {
        appState.selectedWordPressAgentConversation
    }

    var body: some View {
        HStack(spacing: 0) {
            conversationSidebar
                .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                transcript

                Divider()

                composer
                    .padding(12)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var conversationSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WordPress Agent", systemImage: "sparkles")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if appState.sortedWordPressAgentConversations.isEmpty {
                Text("No sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.sortedWordPressAgentConversations) { conversation in
                            Button {
                                appState.selectWordPressAgentConversation(conversation.id)
                            } label: {
                                ConversationSidebarRow(
                                    conversation: conversation,
                                    isSelected: conversation.id == selectedConversation?.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }

            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var header: some View {
        if let selectedConversation {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedConversation.title)
                        .font(.headline)
                    Text(selectedConversation.key.agentID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedConversation.isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } else {
            HStack {
                Text("WordPress Agent")
                    .font(.headline)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if let selectedConversation {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(selectedConversation.messages) { message in
                            WordPressAgentMessageRow(message: message)
                                .id(message.id)
                        }

                        if selectedConversation.isSending {
                            WordPressAgentTypingRow()
                        }

                        if let errorMessage = selectedConversation.errorMessage, !errorMessage.isEmpty {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: selectedConversation.messages.count) { _ in
                    if let lastMessageID = selectedConversation.messages.last?.id {
                        proxy.scrollTo(lastMessageID, anchor: .bottom)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No WordPress Agent session yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draftMessage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendDraftMessage)
                .disabled(selectedConversation == nil || selectedConversation?.isSending == true)

            Button {
                sendDraftMessage()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .help("Send")
            .disabled(
                draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || selectedConversation == nil
                || selectedConversation?.isSending == true
            )
        }
    }

    private func sendDraftMessage() {
        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        let conversationID = selectedConversation?.id
        draftMessage = ""
        appState.sendWordPressAgentChatMessage(trimmedMessage, conversationID: conversationID)
    }
}

private struct ConversationSidebarRow: View {
    let conversation: WordPressAgentConversation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(conversation.messages.last?.text ?? conversation.key.agentID)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
    }
}

private struct WordPressAgentMessageRow: View {
    let message: WordPressAgentMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
                MarkdownMessageText(text: message.text)

                HStack(spacing: 6) {
                    Text(message.role == .agent ? "Agent" : message.role.rawValue.capitalized)
                    if let state = message.state, !state.isEmpty {
                        Text(state)
                    }
                    Text(message.date, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(backgroundColor)
            .cornerRadius(8)
            .frame(maxWidth: 460, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.14)
        case .agent:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.red.opacity(0.10)
        }
    }
}

private struct WordPressAgentTypingRow: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Agent is typing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownMessageText: View {
    let text: String

    var body: some View {
        if let attributedText = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributedText)
                .textSelection(.enabled)
                .font(.body)
        } else {
            Text(text)
                .textSelection(.enabled)
                .font(.body)
        }
    }
}
