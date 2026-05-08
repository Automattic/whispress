import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("WP Workspace v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            Divider()

            if !appState.isWordPressComSignedIn || appState.selectedWordPressComSiteID == nil {
                Button {
                    appState.selectedSettingsTab = .wordpressCom
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                } label: {
                    Label("WordPress.com Sign-In Needed", systemImage: "person.crop.circle.badge.exclamationmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.blue)

                Divider()
            }

            // Accessibility warning
            if !appState.hasAccessibility {
                Button {
                    appState.showAccessibilityAlert()
                } label: {
                    Label("Accessibility Required", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red)

                Divider()
            }

            // Status
            if appState.isRecording {
                Label("Recording...", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else if appState.isTranscribing {
                Label(appState.debugStatusMessage, systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                Text(appState.shortcutStatusText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            if shouldShowCurrentAppConfigSection {
                Divider()
                currentAppConfigSection
                Divider()
            }

            // Manual toggle
            Button(appState.isRecording ? "Stop Recording" : "Start Dictating") {
                appState.toggleRecording()
            }
            .disabled(appState.isTranscribing)

            if let hotkeyError = appState.hotkeyMonitoringErrorMessage {
                Divider()
                Text(hotkeyError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            if let error = appState.errorMessage {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            if !appState.lastAgentResponse.isEmpty && !appState.isRecording && !appState.isTranscribing {
                Divider()
                Label("WordPress Agent", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 280, alignment: .leading)

                Text(appState.lastAgentResponse.count > 160
                    ? String(appState.lastAgentResponse.prefix(160)) + "..."
                    : appState.lastAgentResponse)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .lineLimit(5)
                    .frame(maxWidth: 280, alignment: .leading)

                Button("Copy Reply") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastAgentResponse, forType: .string)
                }
            }

            if !appState.isRecording && !appState.isTranscribing {
                Divider()
                Button {
                    appState.showWordPressAgentWindow()
                } label: {
                    Label("Open WordPress Agent", systemImage: "sparkles")
                }
                .disabled(!appState.isWordPressComSignedIn)
            }

            if !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing {
                Divider()
                Text(appState.lastTranscript.count > 35
                    ? String(appState.lastTranscript.prefix(35)) + "…"
                    : appState.lastTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .lineLimit(4)
                    .frame(maxWidth: 280, alignment: .leading)

                Button("Copy Again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
                }
            }

            Divider()

            Menu("Hold Shortcut") {
                Button {
                    _ = appState.setShortcut(.disabled, for: .hold)
                } label: {
                    if appState.holdShortcut.isDisabled {
                        Text("✓ Disabled")
                    } else {
                        Text("  Disabled")
                    }
                }
                .disabled(appState.toggleShortcut.isDisabled)

                ForEach(ShortcutPreset.allCases) { preset in
                    Button {
                        _ = appState.setShortcut(preset.binding, for: .hold)
                    } label: {
                        if appState.holdShortcut == preset.binding {
                            Text("✓ \(preset.title)")
                        } else {
                            Text("  \(preset.title)")
                        }
                    }
                    .disabled(preset.binding == appState.toggleShortcut)
                }

                if let savedCustomShortcut = appState.savedCustomShortcut(for: .hold) {
                    Divider()
                    Button {
                        _ = appState.setShortcut(savedCustomShortcut, for: .hold)
                    } label: {
                        if appState.holdShortcut == savedCustomShortcut {
                            Text("✓ Custom: \(savedCustomShortcut.displayName)")
                        } else {
                            Text("  Custom: \(savedCustomShortcut.displayName)")
                        }
                    }
                }

                Divider()
                Button("Customize…") {
                    appState.selectedSettingsTab = .keyBindings
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }

            Menu("Toggle Shortcut") {
                Button {
                    _ = appState.setShortcut(.disabled, for: .toggle)
                } label: {
                    if appState.toggleShortcut.isDisabled {
                        Text("✓ Disabled")
                    } else {
                        Text("  Disabled")
                    }
                }
                .disabled(appState.holdShortcut.isDisabled)

                ForEach(ShortcutPreset.allCases) { preset in
                    Button {
                        _ = appState.setShortcut(preset.binding, for: .toggle)
                    } label: {
                        if appState.toggleShortcut == preset.binding {
                            Text("✓ \(preset.title)")
                        } else {
                            Text("  \(preset.title)")
                        }
                    }
                    .disabled(preset.binding == appState.holdShortcut)
                }

                if let savedCustomShortcut = appState.savedCustomShortcut(for: .toggle) {
                    Divider()
                    Button {
                        _ = appState.setShortcut(savedCustomShortcut, for: .toggle)
                    } label: {
                        if appState.toggleShortcut == savedCustomShortcut {
                            Text("✓ Custom: \(savedCustomShortcut.displayName)")
                        } else {
                            Text("  Custom: \(savedCustomShortcut.displayName)")
                        }
                    }
                }

                Divider()
                Button("Customize…") {
                    appState.selectedSettingsTab = .keyBindings
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }

            Menu("Microphone") {
                Button {
                    appState.selectedMicrophoneID = "default"
                } label: {
                    if appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty {
                        Text("✓ System Default")
                    } else {
                        Text("  System Default")
                    }
                }
                ForEach(appState.availableMicrophones) { device in
                    Button {
                        appState.selectedMicrophoneID = device.uid
                    } label: {
                        if appState.selectedMicrophoneID == device.uid {
                            Text("✓ \(device.name)")
                        } else {
                            Text("  \(device.name)")
                        }
                    }
                }
            }

            Button("Re-run Setup...") {
                NotificationCenter.default.post(name: .showSetup, object: nil)
            }

            Button("Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }

            Divider()

            Button(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") {
                appState.toggleDebugOverlay()
            }

            Button("Quit WP Workspace") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear {
            appState.refreshLatestExternalAppSnapshot()
        }
    }

    @ViewBuilder
    private var currentAppConfigSection: some View {
        if let snapshot = appState.latestExternalAppSnapshot,
           let bundleIdentifier = snapshot.bundleIdentifier {
            let override = appState.wordPressComAppSiteOverride(for: bundleIdentifier)
            let effectiveSite = appState.effectiveWordPressComSite(for: bundleIdentifier)

            Menu {
                Text(bundleIdentifier)
                Text(configSummary(site: effectiveSite, isOverride: override != nil))

                Divider()

                Menu("Use Site for This App") {
                    Button {
                        appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
                    } label: {
                        checkedMenuText(
                            "Use Default Site",
                            isSelected: override == nil
                        )
                    }

                    Divider()

                    ForEach(appState.wordpressComSites) { site in
                        Button {
                            appState.setWordPressComAppSiteOverride(
                                bundleIdentifier: bundleIdentifier,
                                appName: snapshot.appName,
                                siteID: site.id
                            )
                        } label: {
                            checkedMenuText(
                                site.displayName,
                                isSelected: override?.siteID == site.id
                            )
                        }
                    }
                }

                Divider()

                Button("Pin Default Site to This App") {
                    appState.assignSelectedWordPressComSiteToLatestExternalApp()
                }
                .disabled(appState.selectedWordPressComSiteID == nil)

                if override != nil {
                    Button("Remove App-Specific Site") {
                        appState.removeWordPressComAppSiteOverride(bundleIdentifier: bundleIdentifier)
                    }
                }
            } label: {
                Label(
                    "App: \(snapshot.appName ?? bundleIdentifier)",
                    systemImage: override == nil ? "app" : "pin.fill"
                )
            }
        } else {
            Label("App: Unknown", systemImage: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private var shouldShowCurrentAppConfigSection: Bool {
        appState.isWordPressComSignedIn && !appState.wordpressComSites.isEmpty
    }

    private func configSummary(site: WPCOMSite?, isOverride: Bool) -> String {
        let siteName = site?.displayName ?? "No site selected"
        return isOverride ? "Pinned: \(siteName)" : "Default: \(siteName)"
    }

    private func checkedMenuText(_ title: String, isSelected: Bool) -> Text {
        Text(isSelected ? "✓ \(title)" : "  \(title)")
    }
}
