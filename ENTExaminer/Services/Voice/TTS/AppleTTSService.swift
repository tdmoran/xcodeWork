import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "AppleTTS")

/// On-device text-to-speech service using Apple's AVSpeechSynthesizer.
/// Free alternative to ElevenLabs — no API key required.
@MainActor
final class AppleTTSService: NSObject, TTSService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?
    private var onAudioLevelCallback: (@Sendable (Float) -> Void)?
    private var levelTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTSService

    nonisolated func speak(
        text: String,
        voiceId: String,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        try await MainActor.run {
            // Cancel any in-progress speech
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.continuation = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                self.continuation = cont
                self.onAudioLevelCallback = onAudioLevel

                let utterance = AVSpeechUtterance(string: text)

                // Try to use the provided voiceId as an AVSpeechSynthesisVoice identifier
                if !voiceId.isEmpty,
                   let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                    utterance.voice = voice
                } else {
                    // Fall back to a good English voice
                    utterance.voice = Self.bestEnglishVoice()
                }

                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                utterance.pitchMultiplier = 1.0
                utterance.volume = 1.0

                #if os(iOS)
                // Ensure audio session is configured for playback
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
                try? session.setActive(true)
                #endif

                // Start a timer to simulate audio levels while speaking
                self.startLevelSimulation()

                logger.info("Starting Apple TTS for: \(text.prefix(50))...")
                self.synthesizer.speak(utterance)
            }
        }
    }

    nonisolated func stopSpeaking() async {
        await MainActor.run {
            self.stopLevelSimulation()
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            // Resume the continuation if it's still waiting
            if let cont = self.continuation {
                self.continuation = nil
                self.onAudioLevelCallback?(0)
                self.onAudioLevelCallback = nil
                cont.resume()
            }
            logger.info("Apple TTS stopped by request")
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.stopLevelSimulation()
            self.onAudioLevelCallback?(0)
            self.onAudioLevelCallback = nil
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume()
            }
            logger.info("Apple TTS finished speaking")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.stopLevelSimulation()
            self.onAudioLevelCallback?(0)
            self.onAudioLevelCallback = nil
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume()
            }
            logger.info("Apple TTS cancelled")
        }
    }

    // MARK: - Audio Level Simulation

    /// Since AVSpeechSynthesizer doesn't provide real-time audio levels,
    /// we simulate a gentle waveform while speaking.
    private func startLevelSimulation() {
        var tick: Double = 0
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.synthesizer.isSpeaking else { return }
                tick += 0.05
                // Generate a natural-looking waveform
                let base: Float = 0.3
                let wave = Float(sin(tick * 4.0) * 0.15 + sin(tick * 7.3) * 0.1)
                let level = min(1.0, max(0.0, base + wave))
                self.onAudioLevelCallback?(level)
            }
        }
    }

    private func stopLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - Voice Selection

    /// Returns the best available English voice, preferring premium/enhanced voices.
    static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        // Prefer premium quality voices
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        // Fall back to default English
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Returns a persona-specific default system voice when the user has not
    /// explicitly picked one in settings.
    static func preferredVoice(for persona: ExaminerPersona) -> AVSpeechSynthesisVoice? {
        let voices = availableEnglishVoices()
        guard !voices.isEmpty else {
            return AVSpeechSynthesisVoice(language: "en-US")
        }

        let preferredNames = persona.appleVoiceNameCandidates.map { $0.lowercased() }
        let languagePreferences = persona.appleVoiceLanguagePreferences
        let maleHints: Set<String> = ["aaron", "arthur", "daniel", "eddy", "fred", "jorge", "nathan", "reed", "rishi", "sandy"]
        let femaleHints: Set<String> = ["allison", "ava", "karen", "martha", "moira", "samantha", "serena", "shelley", "tessa", "victoria", "zoe"]

        return voices.max { lhs, rhs in
            score(lhs, preferredNames: preferredNames, languagePreferences: languagePreferences, maleHints: maleHints, femaleHints: femaleHints, gender: persona.voiceGender)
            < score(rhs, preferredNames: preferredNames, languagePreferences: languagePreferences, maleHints: maleHints, femaleHints: femaleHints, gender: persona.voiceGender)
        }
    }

    /// Returns available English voices suitable for the voice picker.
    static func availableEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { v1, v2 in
                // Sort by quality (premium first), then name
                if v1.quality.rawValue != v2.quality.rawValue {
                    return v1.quality.rawValue > v2.quality.rawValue
                }
                return v1.name < v2.name
            }
    }

    private static func score(
        _ voice: AVSpeechSynthesisVoice,
        preferredNames: [String],
        languagePreferences: [String],
        maleHints: Set<String>,
        femaleHints: Set<String>,
        gender: String
    ) -> Int {
        let lowercasedName = voice.name.lowercased()
        var score = 0

        if let nameIndex = preferredNames.firstIndex(of: lowercasedName) {
            score += 500 - (nameIndex * 50)
        }

        if let languageIndex = languagePreferences.firstIndex(where: { voice.language.hasPrefix($0) }) {
            score += 200 - (languageIndex * 30)
        }

        switch voice.quality {
        case .premium:
            score += 40
        case .enhanced:
            score += 20
        default:
            break
        }

        if gender == "male" {
            if maleHints.contains(lowercasedName) {
                score += 30
            } else if femaleHints.contains(lowercasedName) {
                score -= 20
            }
        } else if gender == "female" {
            if femaleHints.contains(lowercasedName) {
                score += 30
            } else if maleHints.contains(lowercasedName) {
                score -= 20
            }
        }

        return score
    }
}
