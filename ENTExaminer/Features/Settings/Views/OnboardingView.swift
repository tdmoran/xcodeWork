import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var anthropicKey = ""
    @State private var elevenLabsKey = ""
    @State private var anthropicValid = false
    @State private var elevenLabsValid = false

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button {
                    appState.showOnboarding = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(12)
            }

            // Content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: apiKeysStep
                case 2: preferencesStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .push(from: .trailing),
                removal: .push(from: .leading)
            ))
            .animation(.easeInOut(duration: 0.3), value: step)

            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)
        }
        #if os(macOS)
        .frame(width: 500, height: 420)
        #endif
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text("Welcome to VocalCards")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-powered document examination\nwith voice interaction")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Get Started") {
                withAnimation { step = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
    }

    // MARK: - API Keys

    private var apiKeysStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Configuration")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API Key")
                    .font(.headline)

                HStack {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)

                    if anthropicValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ElevenLabs API Key")
                    .font(.headline)

                HStack {
                    SecureField("API key...", text: $elevenLabsKey)
                        .textFieldStyle(.roundedBorder)

                    if elevenLabsValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Keys are stored securely on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { step = 0 }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    Task { await saveKeysAndAdvance() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(anthropicKey.isEmpty)
            }
        }
        .padding(32)
    }

    // MARK: - Preferences

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            @Bindable var state = appState

            Text("Examination Preferences")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Model")
                    .font(.headline)

                Picker("Model", selection: $state.selectedModel) {
                    ForEach(ClaudeModel.allCases) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                Text(model.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.costTier)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.inline)
                #endif
                .labelsHidden()
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { step = 1 }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Examining") {
                    appState.showOnboarding = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func saveKeysAndAdvance() async {
        if !anthropicKey.isEmpty {
            try? await KeychainManager.shared.store(key: anthropicKey, account: KeychainManager.anthropicAccount)
            anthropicValid = true
        }
        if !elevenLabsKey.isEmpty {
            try? await KeychainManager.shared.store(key: elevenLabsKey, account: KeychainManager.elevenLabsAccount)
            elevenLabsValid = true
        }
        withAnimation { step = 2 }
    }
}

// MARK: - Previews

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environment(PreviewData.makePreviewAppState())
            .previewDisplayName("Onboarding")
    }
}
#endif
