import SwiftUI

struct PipelineDebugContentView: View {
    let statusMessage: String
    let postProcessingStatus: String
    let contextSummary: String
    let rawTranscript: String
    let postProcessedTranscript: String
    let postProcessingPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !statusMessage.isEmpty {
                debugRow(title: "Status", value: statusMessage)
            }

            if !postProcessingStatus.isEmpty {
                debugRow(title: "Server Processing", value: postProcessingStatus)
            }

            if !postProcessingPrompt.isEmpty {
                debugRow(title: "Transcribe Skill", value: postProcessingPrompt, copyText: postProcessingPrompt)
            }

            if !contextSummary.isEmpty {
                debugRow(title: "Context", value: contextSummary)
            }

            if !rawTranscript.isEmpty {
                debugRow(title: "Raw Transcript", value: rawTranscript, copyText: rawTranscript)
            }

            if !postProcessedTranscript.isEmpty {
                debugRow(title: "Final Text", value: postProcessedTranscript, copyText: postProcessedTranscript)
            }

            if contextSummary.isEmpty && rawTranscript.isEmpty && postProcessedTranscript.isEmpty && postProcessingPrompt.isEmpty {
                Text("No debug data for this entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func debugRow(title: String, value: String, copyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.bold())
            ScrollView {
                Text(value)
                    .textSelection(.enabled)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            if let copyText {
                Button("Copy \(title)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                }
                .font(.body)
            }
        }
    }

}
