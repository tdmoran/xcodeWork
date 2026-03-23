import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
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
                    .environment(appState)
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
    @Environment(AppState.self) private var appState
    @State private var isTesting = false
    @State private var micLevel: Float = 0
    @State private var micTestTask: Task<Void, Never>?
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Voice Engine") {
                Picker("Engine", selection: $state.voiceEngine) {
                    ForEach(VoiceEngine.allCases, id: \.self) { engine in
                        Label(engine.displayName, systemImage: engine.systemImage)
                            .tag(engine)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif

                if appState.voiceEngine == .apple {
                    if !appleVoices.isEmpty {
                        Picker("System Voice", selection: $state.selectedAppleVoiceId) {
                            Text("Default (Best Available)")
                                .tag("")
                            ForEach(appleVoices, id: \.identifier) { voice in
                                Text("\(voice.name) (\(qualityLabel(voice.quality)))")
                                    .tag(voice.identifier)
                            }
                        }
                    }

                    Text("Uses Apple's built-in speech synthesis. No API key required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Requires an ElevenLabs API key configured in the API Keys tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                appleVoices = AppleTTSService.availableEnglishVoices()
            }

            Section("Examiner Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $state.examinerVolume, in: 0...1, step: 0.05)
                        .accessibilityLabel("Examiner volume")
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }

                Text("Volume: \(Int(appState.examinerVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: appState.examinerVolume) { _, newValue in
                Task { await appState.audioPipeline.setPlaybackVolume(newValue) }
            }

            Section("Microphone Test") {
                HStack {
                    Button {
                        if isTesting {
                            stopMicTest()
                        } else {
                            startMicTest()
                        }
                    } label: {
                        Label(isTesting ? "Stop Test" : "Test Microphone",
                              systemImage: isTesting ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isTesting ? .red : .blue)
                    .accessibilityLabel(isTesting ? "Stop microphone test" : "Start microphone test")

                    Spacer()

                    if isTesting {
                        MicLevelBar(level: micLevel)
                            .frame(height: 20)
                    }
                }

                if isTesting {
                    Text("Speak now — you should see the level bar respond")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Test your microphone before starting an examination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear {
            stopMicTest()
        }
    }

    private func startMicTest() {
        isTesting = true
        micTestTask = Task {
            do {
                let engine = AVAudioEngine()
                #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                #endif

                let inputNode = engine.inputNode
                let format = inputNode.outputFormat(forBus: 0)
                guard format.channelCount > 0 else {
                    await MainActor.run { isTesting = false }
                    return
                }

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    let level = EnergyVAD.computeNormalizedLevel(buffer)
                    Task { @MainActor in
                        micLevel = level
                    }
                }

                engine.prepare()
                try engine.start()

                // Run until cancelled
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(100))
                }

                inputNode.removeTap(onBus: 0)
                engine.stop()
            } catch {
                await MainActor.run { isTesting = false }
            }
        }
    }

    private func stopMicTest() {
        micTestTask?.cancel()
        micTestTask = nil
        isTesting = false
        micLevel = 0
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}

// MARK: - Mic Level Bar

import AVFoundation

struct MicLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }

    private var barColor: Color {
        if level > 0.7 { return .red }
        if level > 0.4 { return .orange }
        return .green
    }
}
