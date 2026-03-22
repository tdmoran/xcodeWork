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

    // MARK: - Cached State

    private var hasAuthorized: Bool = false
    private var cachedRecognizer: SFSpeechRecognizer?

    // Thread-safe stop flag — can be set from any thread/actor via requestStop()
    private let stopFlag = StopFlag()

    /// Thread-safe, non-isolated stop flag. Can be called from any context.
    final class StopFlag: @unchecked Sendable {
        private var _stopped = false
        private let lock = NSLock()

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _stopped
        }

        func stop() {
            lock.lock()
            _stopped = true
            lock.unlock()
        }

        func reset() {
            lock.lock()
            _stopped = false
            lock.unlock()
        }
    }

    // MARK: - VAD State

    private var vad: EnergyVAD

    // MARK: - Initialization

    /// Creates a new Apple Speech STT service.
    ///
    /// - Parameters:
    ///   - locale: The locale for speech recognition (default: current).
    ///   - silenceTimeout: Seconds of silence after speech before finalizing (default: 1.2).
    ///   - energyThreshold: RMS energy below which audio is classified as silence (default: 0.04).
    ///   - audioPipeline: Optional reference to stop playback engine before capturing.
    init(
        locale: Locale = .current,
        silenceTimeout: TimeInterval = 1.2,
        energyThreshold: Float = 0.04,
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
        // Reset stop flag at the start of each listen session
        stopFlag.reset()

        // Force cleanup of any stale previous session
        if isCurrentlyListening {
            logger.warning("listen() called while already listening; cleaning up previous session")
            tearDown()
        }

        // Step 1: Stop any other audio engine that might hold the audio device
        if let pipeline = audioPipeline {
            await pipeline.stopCapture()
            await pipeline.stopPlayback()
            logger.info("Stopped AudioPipeline before STT capture")
        }

        // Step 2: Ensure authorization (cached after first call)
        if !hasAuthorized {
            try await requestSpeechAuthorization()
            hasAuthorized = true
        }

        // Step 3: Validate recognizer availability
        let recognizer = try cachedRecognizer ?? createRecognizer()
        if cachedRecognizer == nil { cachedRecognizer = recognizer }

        // Step 4: Set up audio engine and recognition
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw AppError.audioEngineFailure("Audio session configuration failed: \(error.localizedDescription)")
        }
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AppError.noAudioInputDevice
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

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
        logger.info("stopListening called — setting stop flag")
        requestStop()
    }

    /// Non-isolated: can be called from any actor/thread to request immediate stop.
    nonisolated func requestStop() {
        stopFlag.stop()
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

        // Capture stop flag and a weak ref to the recognition task for the audio tap
        let capturedStopFlag = self.stopFlag
        weak var weakRecogTask: SFSpeechRecognitionTask?
        var stopHandled = false

        // Install input tap BEFORE starting recognition so audio is flowing
        // when the recognizer begins. This prevents "No speech detected" errors.
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nativeFormat
        ) { buffer, _ in
            // Check stop flag on every buffer (~40x/sec) — no actor hop needed
            if capturedStopFlag.isStopped && !stopHandled {
                stopHandled = true
                logger.debug("Stop flag detected in audio tap — finishing recognition")
                request.endAudio()
                weakRecogTask?.finish()
                return
            }

            // Feed buffer to speech recognizer (thread-safe per Apple docs)
            request.append(buffer)

            // Compute audio level for visualization
            let level = EnergyVAD.computeNormalizedLevel(buffer)
            onAudioLevel(level)
        }

        // Start the audio engine BEFORE the recognition task
        engine.prepare()
        do {
            try engine.start()
            logger.info("Audio engine started for speech recognition")
        } catch {
            inputNode.removeTap(onBus: 0)
            self.isCurrentlyListening = false
            self.audioEngine = nil
            self.recognitionRequest = nil
            throw AppError.audioEngineFailure(
                "Failed to start audio engine: \(error.localizedDescription)"
            )
        }

        // Transcript-based silence detection: if the transcript hasn't changed
        // for silenceTimeout seconds after speech was detected, finish recognition.
        // This is far more reliable than energy-based VAD on mobile devices where
        // voice processing skews RMS levels.
        let timeout = self.silenceTimeout

        // Now start recognition — audio is already flowing
        return try await withCheckedThrowingContinuation { continuation in
            var silenceTimer: Timer?

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

                    // Only update if the new text is meaningful
                    if !trimmed.isEmpty {
                        transcriptHolder.update(text)
                        onPartialTranscript(transcriptHolder.current)

                        // Reset the silence timer — transcript just changed
                        silenceTimer?.invalidate()
                        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                            logger.debug("Transcript silence timeout — ending recognition")
                            self?.recognitionTask?.finish()
                        }
                    }

                    if result.isFinal {
                        silenceTimer?.invalidate()
                        let finalText = transcriptHolder.current
                        logger.info("Recognition finalized: \(finalText.prefix(80))...")
                        transcriptHolder.finalize(with: continuation, transcript: finalText)
                    }
                }

                if let error {
                    silenceTimer?.invalidate()
                    let nsError = error as NSError
                    let isCancellation = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216

                    if isCancellation {
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
            weakRecogTask = task
        }
    }

    /// Process a buffer through the VAD on the actor's executor (off the audio thread).
    private func processVADBuffer(_ buffer: AVAudioPCMBuffer) -> VADResult {
        vad.processBuffer(buffer)
    }

    /// Finish the current recognition task (called from VAD when silence timeout is reached).
    private func finishRecognitionTask() {
        recognitionTask?.finish()
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
///
/// Apple's speech recognizer resets its internal buffer during long utterances,
/// sending a drastically shorter transcript that erases earlier content. This
/// holder detects resets (>50% length drop) and accumulates segments so the
/// full answer is preserved across recognizer restarts.
private final class TranscriptHolder: @unchecked Sendable {
    private var _committed: String = ""   // Accumulated segments from previous resets
    private var _pending: String = ""     // Current segment being built
    private var _pendingPeak: Int = 0     // Peak length of current segment
    private var _hasResumed: Bool = false
    private let lock = NSLock()

    /// The full transcript: committed segments + current pending segment.
    var current: String {
        lock.lock()
        defer { lock.unlock() }
        let committed = _committed
        let pending = _pending
        if committed.isEmpty { return pending }
        if pending.isEmpty { return committed }
        return committed + " " + pending
    }

    func update(_ text: String) {
        lock.lock()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLength = trimmed.count

        if newLength == 0 {
            // Ignore empty updates
            lock.unlock()
            return
        }

        // Detect a recognizer reset: new text is drastically shorter than the
        // peak of the current segment. Commit the current segment and start fresh.
        if _pendingPeak > 20 && newLength < _pendingPeak / 2 {
            // Commit the current pending segment
            if !_pending.isEmpty {
                _committed = _committed.isEmpty
                    ? _pending
                    : _committed + " " + _pending
            }
            _pending = text
            _pendingPeak = newLength
        } else {
            // Normal update — the recognizer is refining the current segment
            _pending = text
            _pendingPeak = max(_pendingPeak, newLength)
        }

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
