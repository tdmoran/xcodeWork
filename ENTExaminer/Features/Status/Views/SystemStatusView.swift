import AVFoundation
import Speech
import SwiftUI

// MARK: - System Status View

struct SystemStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var checks: [StatusCheck] = StatusCheck.initial
    @State private var isRunning = false
    @State private var hasRun = false

    // Live STT test state
    @State private var sttTestActive = false
    @State private var sttTranscript = ""
    @State private var sttMicLevel: Float = 0
    @State private var sttTestTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                checklistSection
                sttLiveTestSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Status")
                .font(.largeTitle.bold())

            Text("Run a quick pre-flight check before your next examination.")
                .foregroundStyle(.secondary)

            Button {
                Task { await runAllChecks() }
            } label: {
                Label(hasRun ? "Re-run All Checks" : "Run All Checks",
                      systemImage: "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
            .padding(.top, 4)
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach($checks) { $check in
                StatusCheckRow(check: check)
                if check.id != checks.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Live STT Test

    private var sttLiveTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Speech-to-Text Test")
                .font(.headline)

            Text("Tap Start, speak a sentence, and verify the transcript appears below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    if sttTestActive {
                        stopSTTTest()
                    } else {
                        startSTTTest()
                    }
                } label: {
                    Label(sttTestActive ? "Stop" : "Start Listening",
                          systemImage: sttTestActive ? "stop.circle.fill" : "mic.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(sttTestActive ? .red : .green)

                if sttTestActive {
                    MicLevelBar(level: sttMicLevel)
                        .frame(width: 120, height: 20)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .opacity(sttTestActive ? 1 : 0)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: sttTestActive
                            )
                        Text("Listening...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !sttTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcript:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(sttTranscript)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if sttTestActive && sttTranscript.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for speech...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onDisappear {
            stopSTTTest()
        }
    }

    // MARK: - Run All Checks

    private func runAllChecks() async {
        isRunning = true
        hasRun = true

        // Reset all to running
        for i in checks.indices {
            checks[i].state = .running
        }

        // 1. Microphone permission
        await runCheck(id: "mic") {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            switch status {
            case .authorized:
                return .passed("Microphone access granted")
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                return granted
                    ? .passed("Microphone access granted")
                    : .failed("Microphone access denied")
            case .denied, .restricted:
                return .failed("Microphone access denied — check System Settings > Privacy > Microphone")
            @unknown default:
                return .warning("Unknown microphone permission state")
            }
        }

        // 2. Speech recognition permission
        await runCheck(id: "speech-auth") {
            let status = SFSpeechRecognizer.authorizationStatus()
            switch status {
            case .authorized:
                return .passed("Speech recognition authorized")
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { newStatus in
                        switch newStatus {
                        case .authorized:
                            continuation.resume(returning: .passed("Speech recognition authorized"))
                        default:
                            continuation.resume(returning: .failed("Speech recognition denied — check System Settings > Privacy > Speech Recognition"))
                        }
                    }
                }
            case .denied, .restricted:
                return .failed("Speech recognition denied — check System Settings > Privacy > Speech Recognition")
            @unknown default:
                return .warning("Unknown speech recognition state")
            }
        }

        // 3. Speech recognizer availability + on-device support
        await runCheck(id: "speech-engine") {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
                return .failed("Speech recognizer unavailable for en-US")
            }
            guard recognizer.isAvailable else {
                return .failed("Speech recognizer is not currently available")
            }
            if recognizer.supportsOnDeviceRecognition {
                return .passed("On-device recognition available (works offline)")
            } else {
                return .warning("On-device recognition not available — requires network for speech-to-text")
            }
        }

        // 4. Anthropic API
        await runCheck(id: "anthropic") {
            guard let apiKey = try? await KeychainManager.shared.retrieve(account: KeychainManager.anthropicAccount),
                  !apiKey.isEmpty else {
                return .failed("No Anthropic API key configured — add one in Settings > API Keys")
            }

            // Make a minimal API call to verify connectivity
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": ClaudeModel.haiku.rawValue,
                "max_tokens": 1,
                "messages": [["role": "user", "content": [["type": "text", "text": "Hi"]]]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        return .passed("Anthropic API responding (HTTP \(http.statusCode))")
                    } else if http.statusCode == 401 {
                        return .failed("Anthropic API key is invalid (HTTP 401)")
                    } else if http.statusCode == 429 {
                        return .warning("Anthropic API rate limited — but reachable (HTTP 429)")
                    } else {
                        return .warning("Anthropic API returned HTTP \(http.statusCode)")
                    }
                }
                return .warning("Unexpected response type")
            } catch {
                return .failed("Cannot reach Anthropic API — \(error.localizedDescription)")
            }
        }

        // 5. ElevenLabs API
        await runCheck(id: "elevenlabs") {
            guard let apiKey = try? await KeychainManager.shared.retrieve(account: KeychainManager.elevenLabsAccount),
                  !apiKey.isEmpty else {
                if appState.voiceEngine == .apple {
                    return .passed("ElevenLabs not configured (using Apple TTS — not required)")
                }
                return .failed("No ElevenLabs API key configured — add one in Settings > API Keys")
            }

            var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        return .passed("ElevenLabs API responding (HTTP \(http.statusCode))")
                    } else if http.statusCode == 401 {
                        return .failed("ElevenLabs API key is invalid (HTTP 401)")
                    } else {
                        return .warning("ElevenLabs API returned HTTP \(http.statusCode)")
                    }
                }
                return .warning("Unexpected response type")
            } catch {
                return .failed("Cannot reach ElevenLabs API — \(error.localizedDescription)")
            }
        }

        // 6. Audio output
        await runCheck(id: "audio-output") {
            #if os(macOS)
            let engine = AVAudioEngine()
            let output = engine.outputNode
            let format = output.outputFormat(forBus: 0)
            if format.channelCount > 0 && format.sampleRate > 0 {
                return .passed("Audio output available (\(Int(format.sampleRate)) Hz, \(format.channelCount) ch)")
            } else {
                return .failed("No audio output device detected")
            }
            #else
            let session = AVAudioSession.sharedInstance()
            if session.currentRoute.outputs.isEmpty {
                return .failed("No audio output route available")
            }
            let output = session.currentRoute.outputs.first!
            return .passed("Audio output: \(output.portName)")
            #endif
        }

        isRunning = false
    }

    private func runCheck(id: String, check: () async -> CheckState) async {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].state = .running
        let result = await check()
        checks[index].state = result
    }

    // MARK: - Live STT Test

    private func startSTTTest() {
        sttTranscript = ""
        sttTestActive = true

        sttTestTask = Task {
            do {
                let sttService = AppleSpeechSTTService(audioPipeline: appState.audioPipeline)
                let transcript = try await sttService.listen(
                    onPartialTranscript: { @Sendable partial in
                        Task { @MainActor in
                            sttTranscript = partial
                        }
                    },
                    onAudioLevel: { @Sendable level in
                        Task { @MainActor in
                            sttMicLevel = level
                        }
                    }
                )
                await MainActor.run {
                    sttTranscript = transcript
                    sttTestActive = false
                }
            } catch {
                await MainActor.run {
                    if sttTranscript.isEmpty {
                        sttTranscript = "Error: \(error.localizedDescription)"
                    }
                    sttTestActive = false
                }
            }
        }
    }

    private func stopSTTTest() {
        sttTestTask?.cancel()
        sttTestTask = nil
        sttTestActive = false
        sttMicLevel = 0
    }
}

// MARK: - Data Model

enum CheckState: Equatable {
    case idle
    case running
    case passed(String)
    case warning(String)
    case failed(String)

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .running: return .blue
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }

    var detail: String? {
        switch self {
        case .passed(let msg), .warning(let msg), .failed(let msg): return msg
        case .idle, .running: return nil
        }
    }
}

struct StatusCheck: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var state: CheckState = .idle

    static var initial: [StatusCheck] {
        [
            StatusCheck(id: "mic", title: "Microphone Access", systemImage: "mic.fill"),
            StatusCheck(id: "speech-auth", title: "Speech Recognition Permission", systemImage: "ear.fill"),
            StatusCheck(id: "speech-engine", title: "Speech Engine (On-Device)", systemImage: "cpu"),
            StatusCheck(id: "anthropic", title: "Anthropic API", systemImage: "network"),
            StatusCheck(id: "elevenlabs", title: "ElevenLabs API", systemImage: "cloud.fill"),
            StatusCheck(id: "audio-output", title: "Audio Output", systemImage: "speaker.wave.2.fill"),
        ]
    }
}

// MARK: - Status Check Row

struct StatusCheckRow: View {
    let check: StatusCheck

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: check.systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.medium))

                if let detail = check.state.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(check.state.color == .green ? .secondary : check.state.color)
                }
            }

            Spacer()

            Group {
                if case .running = check.state {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: check.state.icon)
                        .foregroundStyle(check.state.color)
                        .font(.title3)
                }
            }
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
