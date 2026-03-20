import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "PipelinedSpeaker")

/// Bridges Claude streaming output to text-to-speech by accumulating text deltas,
/// splitting on sentence boundaries, and speaking each sentence as soon as it is
/// complete. Sentences are queued and played in order for natural pacing.
///
/// Supports barge-in: external callers can invoke ``bargeIn()`` to immediately
/// stop the current speech and return what has been spoken so far.
actor PipelinedSpeaker {
    // MARK: - Dependencies

    private let ttsService: any TTSService
    private let voiceId: String
    private let sentenceSplitter: SentenceSplitter

    // MARK: - State

    private var currentSpeakTask: Task<Void, Error>?
    private var bargedIn: Bool = false

    // MARK: - Initialization

    /// Creates a new pipelined speaker.
    ///
    /// - Parameters:
    ///   - ttsService: The TTS service used to speak each sentence.
    ///   - voiceId: The voice identifier to pass to the TTS service.
    ///   - sentenceSplitter: The splitter used to detect sentence boundaries. Defaults to a new instance.
    init(
        ttsService: any TTSService,
        voiceId: String,
        sentenceSplitter: SentenceSplitter = SentenceSplitter()
    ) {
        self.ttsService = ttsService
        self.voiceId = voiceId
        self.sentenceSplitter = sentenceSplitter
    }

    // MARK: - Public API

    /// Consumes a Claude streaming response and speaks each sentence as it becomes available.
    ///
    /// Text deltas are accumulated into a buffer. As complete sentences are detected,
    /// they are immediately dispatched to the TTS service. Each sentence awaits completion
    /// before the next begins, ensuring correct playback order.
    ///
    /// If ``bargeIn()`` is called during playback, the stream is consumed silently
    /// (to capture the full text) but no further sentences are spoken.
    ///
    /// - Parameters:
    ///   - stream: The Claude streaming event source producing text deltas.
    ///   - onAudioLevel: A callback invoked with playback audio levels for visualization.
    /// - Returns: The full assembled text from the stream.
    /// - Throws: ``AppError`` if the TTS service or stream encounters an error.
    func speakStream(
        _ stream: AsyncThrowingStream<ClaudeStreamEvent, Error>,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws -> String {
        bargedIn = false
        var buffer = ""
        var fullText = ""
        var pendingSentences: [String] = []

        logger.info("Starting pipelined speech from Claude stream")

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                buffer += delta
                fullText += delta

                // If barged in, keep consuming stream for full text but don't speak
                guard !bargedIn else { continue }

                let result = sentenceSplitter.extract(from: buffer)
                buffer = result.remainder
                pendingSentences = pendingSentences + result.sentences

                // Speak all ready sentences in order
                while let sentence = pendingSentences.first, !bargedIn {
                    pendingSentences = Array(pendingSentences.dropFirst())
                    try await speakSentence(sentence, onAudioLevel: onAudioLevel)
                }

            case .messageComplete:
                logger.debug("Stream complete, flushing remaining buffer")

            case .error(let message):
                logger.error("Stream error during pipelined speech: \(message)")
                throw AppError.apiServerError(statusCode: 0, message: message)
            }
        }

        // Flush remaining text only if not barged in
        if !bargedIn {
            let remainingText = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingText.isEmpty {
                try await speakSentence(remainingText, onAudioLevel: onAudioLevel)
            }

            for sentence in pendingSentences {
                try await speakSentence(sentence, onAudioLevel: onAudioLevel)
            }
        }

        let wasBargedIn = bargedIn
        logger.info("Pipelined speech finished (\(fullText.count) chars, bargedIn: \(wasBargedIn))")
        return fullText
    }

    /// Immediately stops speech playback, allowing the trainee to interrupt.
    /// The stream will continue being consumed silently to capture the full text.
    func bargeIn() async {
        guard !bargedIn else { return }
        bargedIn = true
        currentSpeakTask?.cancel()
        currentSpeakTask = nil
        await ttsService.stopSpeaking()
        logger.info("Barge-in: speech interrupted by trainee")
    }

    /// Whether the speaker was interrupted by a barge-in during the last stream.
    var wasBargedIn: Bool { bargedIn }

    /// Stops the current speech pipeline, cancelling any in-progress TTS.
    func stop() async {
        currentSpeakTask?.cancel()
        currentSpeakTask = nil
        await ttsService.stopSpeaking()
        logger.info("Pipelined speaker stopped")
    }

    // MARK: - Private Helpers

    private func speakSentence(
        _ sentence: String,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        logger.debug("Speaking sentence: \(sentence.prefix(60))...")

        let task = Task {
            try await ttsService.speak(
                text: sentence,
                voiceId: voiceId,
                onAudioLevel: onAudioLevel
            )
        }
        currentSpeakTask = task

        try await task.value
        currentSpeakTask = nil
    }
}
