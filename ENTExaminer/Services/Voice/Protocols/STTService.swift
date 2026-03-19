import Foundation

/// A speech-to-text service that captures audio from the microphone
/// and returns a final transcript when the user finishes speaking.
protocol STTService: Sendable {
    /// Listens for speech and returns the final transcript when done.
    ///
    /// - Parameters:
    ///   - onPartialTranscript: A callback invoked with intermediate transcript text as recognition progresses.
    ///   - onAudioLevel: A callback invoked with the current microphone audio level (0.0-1.0).
    /// - Returns: The final, complete transcript of what the user said.
    /// - Throws: ``AppError`` if microphone access is denied, the audio engine fails, or the API errors.
    func listen(
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws -> String

    /// Stops listening and finalizes the current recognition session.
    func stopListening() async
}
