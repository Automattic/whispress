import SwiftUI

struct ImageImportView: View {
    @EnvironmentObject private var appState: AppState

    let fileURLs: [URL]
    let onCancel: () -> Void
    let onComplete: (String?) -> Void

    @State private var selectedSiteID: Int?
    @State private var resizePreset: ImageImportResizePreset
    @State private var convertsHEICToJPEG: Bool
    @State private var jpegQuality: Double
    @State private var anonymizesFilenames: Bool
    @State private var copiesLinks: Bool
    @State private var opensChat: Bool
    @State private var isUploading = false
    @State private var statusMessage: String?

    init(fileURLs: [URL], onCancel: @escaping () -> Void, onComplete: @escaping (String?) -> Void) {
        self.fileURLs = fileURLs
        self.onCancel = onCancel
        self.onComplete = onComplete
        _resizePreset = State(initialValue: Self.storedResizePreset())
        _convertsHEICToJPEG = State(initialValue: Self.storedConvertsHEICToJPEG())
        _jpegQuality = State(initialValue: Self.storedJPEGQuality())
        _anonymizesFilenames = State(initialValue: Self.storedAnonymizesFilenames())
        _copiesLinks = State(initialValue: Self.storedCopiesLinks())
        _opensChat = State(initialValue: Self.storedOpensChat())
    }

    private var selectedSite: WPCOMSite? {
        guard let selectedSiteID else { return nil }
        return appState.wordpressComSites.first { $0.id == selectedSiteID }
    }

    private var canUpload: Bool {
        appState.isWordPressComSignedIn
            && selectedSiteID != nil
            && !fileURLs.isEmpty
            && !isUploading
    }

    private var containsHEICLikeImage: Bool {
        ImageImportProcessor.containsHEICLikeImage(in: fileURLs)
    }

    private var showsJPEGQuality: Bool {
        containsHEICLikeImage && convertsHEICToJPEG
    }

    private var uploadButtonTitle: String {
        switch (copiesLinks, opensChat) {
        case (true, true):
            return "Upload, Copy Links & Open Chat"
        case (true, false):
            return "Upload & Copy Links"
        case (false, true):
            return "Upload & Open Chat"
        case (false, false):
            return "Upload"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 780, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedSiteID == nil {
                selectedSiteID = appState.selectedWordPressComSiteID ?? appState.wordpressComSites.first?.id
            }
            if appState.isWordPressComSignedIn && appState.wordpressComSites.isEmpty && !appState.isRefreshingWordPressComSites {
                appState.refreshWordPressComSitesFromUI()
            }
        }
        .onChange(of: appState.wordpressComSites) { sites in
            guard selectedSiteID == nil || !sites.contains(where: { $0.id == selectedSiteID }) else { return }
            selectedSiteID = appState.selectedWordPressComSiteID ?? sites.first?.id
        }
        .onDisappear {
            persistSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(red: 0.067, green: 0.467, blue: 0.800))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Upload Images")
                    .font(.system(size: 20, weight: .semibold))
                Text(fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cancel")
            .disabled(isUploading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var content: some View {
        HStack(spacing: 0) {
            imageGrid
                .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                workspaceSection
                processingSection
                actionsSection
                statusSection
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: 270, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 112, maximum: 132), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(fileURLs, id: \.self) { url in
                    ImageImportThumbnail(fileURL: url)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workspace", systemImage: "globe")
                .font(.system(size: 13, weight: .semibold))

            if appState.isWordPressComSignedIn {
                Picker("Workspace", selection: $selectedSiteID) {
                    ForEach(appState.wordpressComSites) { site in
                        Text(site.displayName).tag(Optional(site.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(isUploading || appState.wordpressComSites.isEmpty)

                Text(selectedSite?.url ?? appState.wordpressComStatusMessage ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                HStack {
                    Text("WordPress.com sign-in required")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign In") {
                        appState.signInToWordPressCom()
                    }
                    .disabled(appState.isSigningInToWordPressCom)
                }
            }
        }
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Processing", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))

            Picker("Resize", selection: $resizePreset) {
                ForEach(ImageImportResizePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .disabled(isUploading)

            if containsHEICLikeImage {
                Toggle("Convert HEIC/HEIF to JPEG", isOn: $convertsHEICToJPEG)
                    .disabled(isUploading)
            }

            Toggle("Anonymize filenames", isOn: $anonymizesFilenames)
                .disabled(isUploading)

            if showsJPEGQuality {
                HStack(spacing: 10) {
                    Text("JPEG Quality")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $jpegQuality, in: 0.5...1.0, step: 0.01)
                        .disabled(isUploading)
                    Text("\(Int(jpegQuality * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Upload and", systemImage: "checklist")
                .font(.system(size: 13, weight: .semibold))

            Toggle(fileURLs.count == 1 ? "Copy link" : "Copy links", isOn: $copiesLinks)
                .disabled(isUploading)

            Toggle("Open the chat", isOn: $opensChat)
                .disabled(isUploading)
        }
    }

    private var statusSection: some View {
        Group {
            if let statusMessage {
                Label {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    if isUploading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "info.circle")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .disabled(isUploading)

            Spacer()

            Button {
                upload()
            } label: {
                HStack(spacing: 7) {
                    if isUploading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.doc")
                    }
                    Text(isUploading ? "Uploading" : uploadButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canUpload)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func upload() {
        guard canUpload, let selectedSiteID else { return }

        isUploading = true
        statusMessage = "Preparing images..."

        let options = ImageImportProcessingOptions(
            resizePreset: resizePreset,
            convertsHEICToJPEG: containsHEICLikeImage && convertsHEICToJPEG,
            jpegQuality: jpegQuality,
            anonymizesFilenames: anonymizesFilenames
        )
        persistSettings()

        Task {
            do {
                let result = try await appState.importImagesIntoWordPressAgentChat(
                    fileURLs: fileURLs,
                    siteID: selectedSiteID,
                    options: options,
                    opensChat: opensChat
                ) { status in
                    await MainActor.run {
                        statusMessage = status
                    }
                }

                await MainActor.run {
                    if copiesLinks {
                        copyLinksToPasteboard(result.attachmentPageURLs)
                    }
                    isUploading = false
                    onComplete(opensChat ? result.conversationID : nil)
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }

    private func copyLinksToPasteboard(_ urls: [URL]) {
        let value = urls.map(\.absoluteString).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func persistSettings() {
        UserDefaults.standard.set(resizePreset.rawValue, forKey: Self.resizePresetStorageKey)
        UserDefaults.standard.set(convertsHEICToJPEG, forKey: Self.convertsHEICToJPEGStorageKey)
        UserDefaults.standard.set(jpegQuality, forKey: Self.jpegQualityStorageKey)
        UserDefaults.standard.set(anonymizesFilenames, forKey: Self.anonymizesFilenamesStorageKey)
        UserDefaults.standard.set(copiesLinks, forKey: Self.copiesLinksStorageKey)
        UserDefaults.standard.set(opensChat, forKey: Self.opensChatStorageKey)
    }

    private static let resizePresetStorageKey = "image_import_resize_preset"
    private static let convertsHEICToJPEGStorageKey = "image_import_converts_heic_to_jpeg"
    private static let jpegQualityStorageKey = "image_import_jpeg_quality"
    private static let anonymizesFilenamesStorageKey = "image_import_anonymizes_filenames"
    private static let copiesLinksStorageKey = "image_import_copies_links"
    private static let opensChatStorageKey = "image_import_opens_chat"

    private static func storedResizePreset() -> ImageImportResizePreset {
        ImageImportResizePreset(rawValue: UserDefaults.standard.integer(forKey: resizePresetStorageKey)) ?? .original
    }

    private static func storedConvertsHEICToJPEG() -> Bool {
        UserDefaults.standard.object(forKey: convertsHEICToJPEGStorageKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: convertsHEICToJPEGStorageKey)
    }

    private static func storedJPEGQuality() -> Double {
        let stored = UserDefaults.standard.double(forKey: jpegQualityStorageKey)
        return stored > 0 ? min(max(stored, 0.5), 1.0) : 0.88
    }

    private static func storedAnonymizesFilenames() -> Bool {
        UserDefaults.standard.bool(forKey: anonymizesFilenamesStorageKey)
    }

    private static func storedCopiesLinks() -> Bool {
        UserDefaults.standard.bool(forKey: copiesLinksStorageKey)
    }

    private static func storedOpensChat() -> Bool {
        UserDefaults.standard.object(forKey: opensChatStorageKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: opensChatStorageKey)
    }
}

private struct ImageImportThumbnail: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.06))

                if let image = NSImage(contentsOf: fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(fileURL.lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 112)
        }
        .help(fileURL.path)
    }
}
