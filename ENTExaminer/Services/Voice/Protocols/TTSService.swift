import Foundation

/// A text-to-speech service that converts text into audible speech,
/// reporting audio levels for waveform visualization during playback.
protocol TTSService: Sendable {
    /// Speaks the given text using the specified voice.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize into speech.
    ///   - voiceId: The identifier for the voice to use.
    ///   - onAudioLevel: A callback invoked with the current playback audio level (0.0-1.0).
    /// - Throws: ``AppError`` if the API key is missing, the request fails, or audio playback fails.
    func speak(
        text: String,
        voiceId: String,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws

    /// Stops any currently playing speech and cancels the active stream.
    func stopSpeaking() async

    /// Pauses any currently playing speech. Call ``resumeSpeaking()`` to continue.
    func pauseSpeaking() async

    /// Resumes speech that was previously paused with ``pauseSpeaking()``.
    func resumeSpeaking() async
}
