import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Close button bar
            HStack {
                Spacer()
                Button("Done") {
                    appState.showSettings = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding(12)
            }

            TabView {
                GeneralSettingsView()
                    .environment(appState)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                APIKeysSettingsView()
                    .tabItem {
                        Label("API Keys", systemImage: "key.fill")
                    }

                VoiceSettingsView()
                    .tabItem {
                        Label("Voice", systemImage: "waveform")
                    }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 400)
        #endif
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("AI Model") {
                Picker("Default Model", selection: $state.selectedModel) {
                    ForEach(ClaudeModel.allCases) { model in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(model.displayName)
                                Spacer()
                                Text(model.costTier)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif

                Text(appState.selectedModel.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Previews

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView()
                .environment(PreviewData.makePreviewAppState())
                .previewDisplayName("Settings")

            VoiceSettingsView()
                .frame(width: 480, height: 300)
                .previewDisplayName("Voice Settings")
        }
    }
}
#endif

// MARK: - API Keys Settings

struct APIKeysSettingsView: View {
    @State private var anthropicKey = ""
    @State private var elevenLabsKey = ""
    @State private var anthropicStatus: KeyStatus = .unknown
    @State private var elevenLabsStatus: KeyStatus = .unknown

    enum KeyStatus {
        case unknown, validating, valid, invalid
    }

    var body: some View {
        Form {
            Section("Anthropic API Key") {
                HStack {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Validate") {
                        Task { await validateAnthropicKey() }
                    }
                    .disabled(anthropicKey.isEmpty)

                    statusIcon(anthropicStatus)
                }
            }

            Section("ElevenLabs API Key") {
                HStack {
                    SecureField("API key...", text: $elevenLabsKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Validate") {
                        Task { await validateElevenLabsKey() }
                    }
                    .disabled(elevenLabsKey.isEmpty)

                    statusIcon(elevenLabsStatus)
                }
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text("Keys are stored securely in Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save Keys") {
                        Task { await saveKeys() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadExistingKeys() }
    }

    @ViewBuilder
    private func statusIcon(_ status: KeyStatus) -> some View {
        switch status {
        case .unknown:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .validating:
            ProgressView()
                .controlSize(.small)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func loadExistingKeys() async {
        if let key = try? await KeychainManager.shared.retrieve(account: KeychainManager.anthropicAccount) {
            anthropicKey = key
            anthropicStatus = .valid
        }
        if let key = try? await KeychainManager.shared.retrieve(account: KeychainManager.elevenLabsAccount) {
            elevenLabsKey = key
            elevenLabsStatus = .valid
        }
    }

    private func validateAnthropicKey() async {
        anthropicStatus = .validating
        // Simple validation: check key format
        anthropicStatus = anthropicKey.hasPrefix("sk-ant-") ? .valid : .invalid
    }

    private func validateElevenLabsKey() async {
        elevenLabsStatus = .validating
        // Simple validation: check key is not empty
        elevenLabsStatus = elevenLabsKey.count > 10 ? .valid : .invalid
    }

    private func saveKeys() async {
        if !anthropicKey.isEmpty {
            try? await KeychainManager.shared.store(key: anthropicKey, account: KeychainManager.anthropicAccount)
        }
        if !elevenLabsKey.isEmpty {
            try? await KeychainManager.shared.store(key: elevenLabsKey, account: KeychainManager.elevenLabsAccount)
        }
    }
}

// MARK: - Voice Settings

struct VoiceSettingsView: View {
    @State private var selectedVoice = "default"

    var body: some View {
        Form {
            Section("Examiner Voice") {
                Picker("Voice", selection: $selectedVoice) {
                    Text("Default (Rachel)").tag("default")
                    Text("George").tag("george")
                    Text("Emily").tag("emily")
                    Text("Adam").tag("adam")
                }

                Text("Voice selection requires an active ElevenLabs API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
