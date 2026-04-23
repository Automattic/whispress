import SwiftUI

struct PipelineDebugPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            PipelineDebugContentView(
                statusMessage: appState.debugStatusMessage,
                postProcessingStatus: appState.lastPostProcessingStatus,
                contextSummary: appState.lastContextSummary,
                rawTranscript: appState.lastRawTranscript,
                postProcessedTranscript: appState.lastPostProcessedTranscript,
                postProcessingPrompt: appState.lastPostProcessingPrompt
            )

            if appState.lastContextSummary.isEmpty && appState.lastRawTranscript.isEmpty {
                Text("Run a dictation pass to populate debug output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 620, height: 640, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pipeline Debug")
                .font(.title3)
            Text("Live data for the WordPress.com transcription pipeline.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
