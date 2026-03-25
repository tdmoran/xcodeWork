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
    private var currentStreamTask: Task<String, Error>?
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
        logger.info("Starting pipelined speech from Claude stream")
        let splitter = sentenceSplitter

        let streamTask = Task<String, Error> {
            var buffer = ""
            var fullText = ""
            var pendingSentences: [String] = []

            do {
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        buffer += delta
                        fullText += delta

                        guard !self.wasBargedIn else {
                            throw CancellationError()
                        }

                        let result = splitter.extract(from: buffer)
                        buffer = result.remainder
                        pendingSentences = pendingSentences + result.sentences

                        while let sentence = pendingSentences.first {
                            guard !self.wasBargedIn else {
                                throw CancellationError()
                            }

                            pendingSentences.removeFirst()
                            try await self.speakSentence(sentence, onAudioLevel: onAudioLevel)
                        }

                    case .messageComplete:
                        logger.debug("Stream complete, flushing remaining buffer")

                    case .error(let message):
                        logger.error("Stream error during pipelined speech: \(message)")
                        throw AppError.apiServerError(statusCode: 0, message: message)
                    }
                }

                guard !self.wasBargedIn else {
                    throw CancellationError()
                }

                let remainingText = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainingText.isEmpty {
                    try await self.speakSentence(remainingText, onAudioLevel: onAudioLevel)
                }

                for sentence in pendingSentences {
                    guard !self.wasBargedIn else {
                        throw CancellationError()
                    }
                    try await self.speakSentence(sentence, onAudioLevel: onAudioLevel)
                }

                return fullText
            } catch is CancellationError {
                return fullText
            }
        }
        currentStreamTask = streamTask
        defer { currentStreamTask = nil }

        let spokenText = try await streamTask.value

        let wasBargedIn = bargedIn
        logger.info("Pipelined speech finished (\(spokenText.count) chars, bargedIn: \(wasBargedIn))")
        return spokenText
    }

    /// Immediately stops speech playback, allowing the trainee to interrupt.
    /// The stream will continue being consumed silently to capture the full text.
    func bargeIn() async {
        guard !bargedIn else { return }
        bargedIn = true
        currentSpeakTask?.cancel()
        currentSpeakTask = nil
        currentStreamTask?.cancel()
        await ttsService.stopSpeaking()
        logger.info("Barge-in: speech interrupted by trainee")
    }

    /// Whether the speaker was interrupted by a barge-in during the last stream.
    var wasBargedIn: Bool { bargedIn }

    /// Pauses speech playback. The stream continues buffering but audio output is suspended.
    func pause() async {
        await ttsService.pauseSpeaking()
        logger.info("Pipelined speaker paused")
    }

    /// Resumes speech playback from where it was paused.
    func resume() async {
        await ttsService.resumeSpeaking()
        logger.info("Pipelined speaker resumed")
    }

    /// Stops the current speech pipeline, cancelling any in-progress TTS.
    func stop() async {
        currentSpeakTask?.cancel()
        currentSpeakTask = nil
        currentStreamTask?.cancel()
        currentStreamTask = nil
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
