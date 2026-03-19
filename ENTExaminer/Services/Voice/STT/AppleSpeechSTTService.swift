import AVFoundation
import OSLog
import Speech

private let logger = Logger(subsystem: "com.entexaminer", category: "AppleSpeechSTT")

// MARK: - Apple Speech STT Service

/// A speech-to-text service using Apple's `Speech` framework.
///
/// This actor manages its own `AVAudioEngine` and installs an input tap to feed
/// `AVAudioPCMBuffer` objects directly to `SFSpeechAudioBufferRecognitionRequest`.
/// A separate `AVAudioEngine` is used (rather than sharing `AudioPipeline`'s engine)
/// because `SFSpeechRecognizer` requires buffers in the native microphone format.
///
/// Voice activity detection (via `EnergyVAD`) determines when the user has stopped
/// speaking; after a configurable silence timeout, recognition is finalized and
/// the completed transcript is returned.
actor AppleSpeechSTTService: STTService {
    // MARK: - Configuration

    private let locale: Locale
    private let silenceTimeout: TimeInterval
    private let energyThreshold: Float
    private let audioPipeline: AudioPipeline?

    // MARK: - Engine State

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isCurrentlyListening: Bool = false

    // MARK: - VAD State

    private var vad: EnergyVAD

    // MARK: - Initialization

    /// Creates a new Apple Speech STT service.
    ///
    /// - Parameters:
    ///   - locale: The locale for speech recognition (default: current).
    ///   - silenceTimeout: Seconds of silence after speech before finalizing (default: 5.0).
    ///   - energyThreshold: RMS energy below which audio is classified as silence (default: 0.008).
    ///   - audioPipeline: Optional reference to stop playback engine before capturing.
    init(
        locale: Locale = .current,
        silenceTimeout: TimeInterval = 5.0,
        energyThreshold: Float = 0.008,
        audioPipeline: AudioPipeline? = nil
    ) {
        self.locale = locale
        self.silenceTimeout = silenceTimeout
        self.energyThreshold = energyThreshold
        self.audioPipeline = audioPipeline
        self.vad = EnergyVAD(
            silenceThreshold: silenceTimeout,
            energyThreshold: energyThreshold
        )
    }

    // MARK: - STTService

    func listen(
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws -> String {
        // Force cleanup of any stale previous session
        if isCurrentlyListening {
            logger.warning("listen() called while already listening; cleaning up previous session")
            tearDown()
        }

        // Step 1: Stop any other audio engine that might hold the mic
        if let pipeline = audioPipeline {
            await pipeline.stopCapture()
            logger.info("Stopped AudioPipeline before STT capture")
        }

        // Step 2: Ensure authorization
        try await requestSpeechAuthorization()

        // Step 3: Validate recognizer availability
        let recognizer = try createRecognizer()

        // Step 4: Set up audio engine and recognition
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AppError.noAudioInputDevice
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            logger.info("Using on-device speech recognition")
        } else {
            logger.info("On-device recognition not available; using server-based recognition")
        }

        // Step 4: Start recognition and listen via a continuation
        do {
            let transcript: String = try await withTaskCancellationHandler {
                try await performRecognition(
                    recognizer: recognizer,
                    request: request,
                    engine: engine,
                    inputNode: inputNode,
                    nativeFormat: nativeFormat,
                    onPartialTranscript: onPartialTranscript,
                    onAudioLevel: onAudioLevel
                )
            } onCancel: {
                Task { await self.tearDown() }
            }

            // Always clean up after successful recognition
            tearDown()
            return transcript
        } catch {
            // Always clean up on error too
            tearDown()
            throw error
        }
    }

    func stopListening() async {
        tearDown()
    }

    // MARK: - Authorization

    private func requestSpeechAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()

        switch status {
        case .authorized:
            return

        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            guard granted else {
                throw AppError.speechRecognitionDenied
            }

        case .denied, .restricted:
            throw AppError.speechRecognitionDenied

        @unknown default:
            throw AppError.speechRecognitionDenied
        }

        // Also verify microphone access
        #if os(macOS)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw AppError.microphoneAccessDenied }
        case .denied, .restricted:
            throw AppError.microphoneAccessDenied
        @unknown default:
            throw AppError.microphoneAccessDenied
        }
        #else
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            break
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { throw AppError.microphoneAccessDenied }
        case .denied:
            throw AppError.microphoneAccessDenied
        @unknown default:
            throw AppError.microphoneAccessDenied
        }
        #endif
    }

    // MARK: - Recognizer Setup

    private func createRecognizer() throws -> SFSpeechRecognizer {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppError.speechRecognitionUnavailable(
                "No speech recognizer available for locale '\(locale.identifier)'"
            )
        }

        guard recognizer.isAvailable else {
            throw AppError.speechRecognitionUnavailable(
                "Speech recognizer for '\(locale.identifier)' is currently unavailable"
            )
        }

        return recognizer
    }

    // MARK: - Recognition Loop

    private func performRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        engine: AVAudioEngine,
        inputNode: AVAudioInputNode,
        nativeFormat: AVAudioFormat,
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws -> String {
        // Shared mutable state for the recognition callback — protected by the continuation
        // pattern (only one resume is allowed).
        let transcriptHolder = TranscriptHolder()

        // Reset VAD state for this session
        vad.reset()

        // Store engine references for cleanup
        self.audioEngine = engine
        self.recognitionRequest = request
        self.isCurrentlyListening = true

        return try await withCheckedThrowingContinuation { continuation in
            // Start the recognition task
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    transcriptHolder.update(text)
                    onPartialTranscript(text)

                    if result.isFinal {
                        let finalText = transcriptHolder.current
                        logger.info("Recognition finalized: \(finalText.prefix(80))...")
                        transcriptHolder.finalize(with: continuation, transcript: finalText)
                    }
                }

                if let error {
                    // Ignore cancellation errors during teardown
                    let nsError = error as NSError
                    let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216

                    if isCancellation {
                        // Return whatever transcript we have so far
                        let currentText = transcriptHolder.current
                        logger.info("Recognition cancelled; returning partial transcript")
                        transcriptHolder.finalize(with: continuation, transcript: currentText)
                    } else {
                        logger.error("Recognition error: \(error.localizedDescription)")
                        transcriptHolder.fail(
                            with: continuation,
                            error: AppError.speechRecognitionFailed(error.localizedDescription)
                        )
                    }
                }
            }

            self.recognitionTask = task

            // Install input tap — this closure runs on the real-time audio thread.
            // We do minimal work: append buffer to the request and compute level.
            // VAD processing is dispatched off the audio thread.
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: nativeFormat
            ) { [weak task] buffer, _ in
                // Feed buffer to speech recognizer (thread-safe per Apple docs)
                request.append(buffer)

                // Compute audio level (lightweight vDSP operation, safe on audio thread)
                let level = EnergyVAD.computeNormalizedLevel(buffer)
                onAudioLevel(level)

                // Dispatch VAD check off the real-time thread
                let bufferCopy = Self.copyBuffer(buffer)
                Task { [weak self] in
                    guard let self else { return }
                    let vadResult = await self.processVADBuffer(bufferCopy)

                    if case .silenceTimeout = vadResult {
                        logger.debug("VAD silence timeout — ending recognition")
                        task?.finish()
                    }
                }
            }

            // Start the audio engine
            engine.prepare()
            do {
                try engine.start()
                logger.info("Audio engine started for speech recognition")
            } catch {
                inputNode.removeTap(onBus: 0)
                self.isCurrentlyListening = false
                self.audioEngine = nil
                self.recognitionRequest = nil
                transcriptHolder.fail(
                    with: continuation,
                    error: AppError.audioEngineFailure(
                        "Failed to start audio engine: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    /// Process a buffer through the VAD on the actor's executor (off the audio thread).
    private func processVADBuffer(_ buffer: AVAudioPCMBuffer) -> VADResult {
        vad.processBuffer(buffer)
    }

    // MARK: - Cleanup

    private func tearDown() {
        guard isCurrentlyListening else { return }

        logger.info("Tearing down speech recognition session")

        // End the recognition request (signals no more audio)
        recognitionRequest?.endAudio()

        // Cancel the recognition task
        recognitionTask?.cancel()

        // Remove tap and stop engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        // Clear references
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isCurrentlyListening = false
    }

    // MARK: - Buffer Utilities

    /// Create a copy of an `AVAudioPCMBuffer` so it can be safely passed across threads.
    /// The original buffer's memory is only valid for the duration of the audio tap callback.
    private static func copyBuffer(_ original: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: original.format,
            frameCapacity: original.frameCapacity
        ) else {
            // Return the original if copy fails (edge case); VAD will just get stale data
            return original
        }

        copy.frameLength = original.frameLength

        guard let srcChannels = original.floatChannelData,
              let dstChannels = copy.floatChannelData else {
            return copy
        }

        let channelCount = Int(original.format.channelCount)
        let frameCount = Int(original.frameLength)

        for channel in 0..<channelCount {
            dstChannels[channel].update(from: srcChannels[channel], count: frameCount)
        }

        return copy
    }
}

// MARK: - Transcript Holder

/// Thread-safe holder for the recognition transcript that ensures the continuation
/// is resumed exactly once, even if multiple callbacks fire.
private final class TranscriptHolder: @unchecked Sendable {
    private var _current: String = ""
    private var _hasResumed: Bool = false
    private let lock = NSLock()

    var current: String {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    func update(_ text: String) {
        lock.lock()
        _current = text
        lock.unlock()
    }

    func finalize(
        with continuation: CheckedContinuation<String, any Error>,
        transcript: String
    ) {
        lock.lock()
        guard !_hasResumed else {
            lock.unlock()
            return
        }
        _hasResumed = true
        lock.unlock()

        continuation.resume(returning: transcript)
    }

    func fail(
        with continuation: CheckedContinuation<String, any Error>,
        error: any Error
    ) {
        lock.lock()
        guard !_hasResumed else {
            lock.unlock()
            return
        }
        _hasResumed = true
        lock.unlock()

        continuation.resume(throwing: error)
    }
}
