import AVFoundation
import Accelerate
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "AudioPipeline")

// MARK: - Public Types

enum AudioFormat: Sendable {
    case pcm16kHz
    case pcm24kHz
    case mp3
}

enum VoiceActivityEvent: Sendable, Equatable {
    case speechStarted
    case speechEnded(durationSeconds: Double)
}

// MARK: - Audio Pipeline Actor

actor AudioPipeline {
    // MARK: - Constants

    private static let captureRate: Double = 16_000
    private static let bandCount: Int = 32
    private static let ringBufferCapacity: Int = 16_000 * 2 * 5  // 5 seconds of Int16 mono at 16kHz
    private static let chunkSize: Int = 16_000 * 2 / 10          // 100ms chunks (3200 bytes)
    private static let vadEnergyThreshold: Float = 0.015
    private static let vadSilenceTimeout: TimeInterval = 0.8
    private static let levelsPollInterval: TimeInterval = 1.0 / 30.0  // 30 fps for visualization

    // MARK: - Audio Engine State

    private var engine: AVAudioEngine?
    private var playbackMixerNode: AVAudioMixerNode?
    private var playbackPlayerNode: AVAudioPlayerNode?

    // MARK: - Lock-Free Shared State (written by render thread, read by actor)

    private let ringBuffer = SPSCRingBuffer(capacity: AudioPipeline.ringBufferCapacity)
    private let currentLevels = AtomicFloatArray(count: AudioPipeline.bandCount)
    private let currentEnergy = AtomicFloatArray(count: 1)
    private let isEngineRunning = AtomicBool(false)

    // MARK: - Stream Continuations

    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var levelsContinuation: AsyncStream<[Float]>.Continuation?
    private var vadContinuation: AsyncStream<VoiceActivityEvent>.Continuation?

    // MARK: - VAD State

    private var isSpeechActive: Bool = false
    private var speechStartTime: Date?
    private var lastAboveThresholdTime: Date?

    // MARK: - Task Handles

    private var chunkEmitterTask: Task<Void, Never>?
    private var levelsEmitterTask: Task<Void, Never>?
    private var vadEmitterTask: Task<Void, Never>?

    // MARK: - Public Properties

    private(set) var isCapturing: Bool = false

    /// Outbound PCM audio chunks (16kHz, mono, Int16) for STT.
    nonisolated let capturedAudio: AsyncStream<Data>

    /// Audio level bands (32 floats, 0.0-1.0) for waveform visualization.
    nonisolated let audioLevels: AsyncStream<[Float]>

    /// Voice activity events indicating speech start and end.
    nonisolated let voiceActivity: AsyncStream<VoiceActivityEvent>

    // MARK: - Initialization

    init() {
        var audioCont: AsyncStream<Data>.Continuation!
        self.capturedAudio = AsyncStream { audioCont = $0 }

        var levelsCont: AsyncStream<[Float]>.Continuation!
        self.audioLevels = AsyncStream { levelsCont = $0 }

        var vadCont: AsyncStream<VoiceActivityEvent>.Continuation!
        self.voiceActivity = AsyncStream { vadCont = $0 }

        self.audioContinuation = audioCont
        self.levelsContinuation = levelsCont
        self.vadContinuation = vadCont
    }

    deinit {
        audioContinuation?.finish()
        levelsContinuation?.finish()
        vadContinuation?.finish()
    }

    // MARK: - Microphone Permission

    func requestMicrophonePermission() async throws {
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw AppError.microphoneAccessDenied
            }
        case .denied, .restricted:
            throw AppError.microphoneAccessDenied
        @unknown default:
            throw AppError.microphoneAccessDenied
        }
        #else
        let session = AVAudioSession.sharedInstance()
        let permission = session.recordPermission
        switch permission {
        case .granted:
            return
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                throw AppError.microphoneAccessDenied
            }
        case .denied:
            throw AppError.microphoneAccessDenied
        @unknown default:
            throw AppError.microphoneAccessDenied
        }
        #endif
    }

    // MARK: - Playback-Only Mode

    /// Starts the audio engine for playback only (no mic capture).
    /// Call this before using `playAudioChunk` if `startCapture` hasn't been called.
    func startPlayback() async throws {
        guard engine == nil || !(engine?.isRunning ?? false) else {
            logger.info("Engine already running, playback ready")
            return
        }

        let audioEngine = AVAudioEngine()

        let mixerNode = AVAudioMixerNode()
        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(mixerNode)
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mixerNode, format: nil)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: nil)

        audioEngine.prepare()
        try audioEngine.start()

        self.engine = audioEngine
        self.playbackMixerNode = mixerNode
        self.playbackPlayerNode = playerNode

        logger.info("Audio engine started in playback-only mode")
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        guard !isCapturing else {
            logger.warning("startCapture called while already capturing")
            return
        }

        try await requestMicrophonePermission()

        let audioEngine = AVAudioEngine()

        #if os(iOS)
        try configureAudioSession()
        #endif

        // Enable voice processing for echo cancellation on the input node.
        // This must be set before connecting nodes or starting the engine.
        let inputNode = audioEngine.inputNode
        guard inputNode.inputFormat(forBus: 0).channelCount > 0 else {
            throw AppError.noAudioInputDevice
        }

        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            logger.warning("Voice processing unavailable: \(error.localizedDescription)")
            // Continue without echo cancellation — degraded but functional
        }

        // Set up playback nodes
        let mixerNode = AVAudioMixerNode()
        let playerNode = AVAudioPlayerNode()
        audioEngine.attach(mixerNode)
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mixerNode, format: nil)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: nil)

        // Install a tap on the input for capture and analysis
        let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.captureRate,
            channels: 1,
            interleaved: true
        )
        guard let captureFormat else {
            throw AppError.audioEngineFailure("Could not create capture audio format")
        }

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AppError.noAudioInputDevice
        }

        // We need a converter from the native input format to our target 16kHz Int16 mono
        guard let converter = AVAudioConverter(from: nativeFormat, to: captureFormat) else {
            throw AppError.audioEngineFailure(
                "Cannot create audio converter from \(nativeFormat) to \(captureFormat)"
            )
        }

        let ringBuf = self.ringBuffer
        let levels = self.currentLevels
        let energy = self.currentEnergy
        let bandCount = Self.bandCount

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nativeFormat
        ) { [ringBuf, levels, energy, bandCount] buffer, _ in
            // --- Real-time audio callback thread ---
            // No allocations, no locks (except the trivial os_unfair_lock in AtomicFloatArray),
            // no Objective-C messaging, no Swift runtime calls that could block.

            Self.processInputBuffer(
                buffer,
                converter: converter,
                captureFormat: captureFormat,
                ringBuffer: ringBuf,
                levels: levels,
                energy: energy,
                bandCount: bandCount
            )
        }

        // Prepare and start
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AppError.audioEngineFailure("Engine failed to start: \(error.localizedDescription)")
        }

        self.engine = audioEngine
        self.playbackMixerNode = mixerNode
        self.playbackPlayerNode = playerNode
        self.isCapturing = true
        self.isEngineRunning.store(true)

        startChunkEmitter()
        startLevelsEmitter()
        startVADEmitter()

        logger.info("Audio capture started (rate=\(Self.captureRate), echo cancellation enabled)")
    }

    func stopCapture() {
        guard isCapturing else { return }

        chunkEmitterTask?.cancel()
        levelsEmitterTask?.cancel()
        vadEmitterTask?.cancel()
        chunkEmitterTask = nil
        levelsEmitterTask = nil
        vadEmitterTask = nil

        engine?.inputNode.removeTap(onBus: 0)
        playbackPlayerNode?.stop()
        engine?.stop()

        isEngineRunning.store(false)
        isCapturing = false

        // Reset VAD state
        if isSpeechActive, let startTime = speechStartTime {
            let duration = Date().timeIntervalSince(startTime)
            vadContinuation?.yield(.speechEnded(durationSeconds: duration))
        }
        isSpeechActive = false
        speechStartTime = nil
        lastAboveThresholdTime = nil

        engine = nil
        playbackMixerNode = nil
        playbackPlayerNode = nil

        logger.info("Audio capture stopped")
    }

    // MARK: - Playback

    func playAudioChunk(_ data: Data, format: AudioFormat) async throws {
        guard let playerNode = playbackPlayerNode, let engine, engine.isRunning else {
            throw AppError.audioEngineFailure("Audio engine is not running for playback")
        }

        let pcmBuffer: AVAudioPCMBuffer

        switch format {
        case .pcm16kHz:
            pcmBuffer = try Self.pcmBufferFromInt16Data(data, sampleRate: 16000)

        case .pcm24kHz:
            pcmBuffer = try Self.pcmBufferFromInt16Data(data, sampleRate: 24000)

        case .mp3:
            pcmBuffer = try await Self.pcmBufferFromCompressedData(data)
        }

        // Start playing BEFORE scheduling (or it deadlocks)
        if !playerNode.isPlaying {
            playerNode.play()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(pcmBuffer) {
                continuation.resume()
            }
        }
    }

    // MARK: - Real-Time Audio Processing (static, no actor isolation)

    /// Process an input buffer on the real-time audio thread. This method is deliberately static
    /// and captures only Sendable, lock-free types to avoid any actor hop.
    private static func processInputBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        captureFormat: AVAudioFormat,
        ringBuffer: SPSCRingBuffer,
        levels: AtomicFloatArray,
        energy: AtomicFloatArray,
        bandCount: Int
    ) {
        // Compute frequency-band levels for visualization from the native float buffer
        if let floatData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            computeBandLevels(
                floatData,
                frameCount: frameCount,
                bandCount: bandCount,
                levels: levels,
                energy: energy
            )
        }

        // Convert to 16kHz Int16 mono and write to ring buffer
        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (captureFormat.sampleRate / buffer.format.sampleRate)
        ) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: captureFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else { return }

        let byteCount = Int(outputBuffer.frameLength) * 2  // Int16 = 2 bytes
        if let int16Data = outputBuffer.int16ChannelData?[0] {
            ringBuffer.write(int16Data, count: byteCount)
        }
    }

    /// Compute per-band energy levels using vDSP for efficient FFT-like band analysis.
    private static func computeBandLevels(
        _ samples: UnsafePointer<Float>,
        frameCount: Int,
        bandCount: Int,
        levels: AtomicFloatArray,
        energy: AtomicFloatArray
    ) {
        guard frameCount > 0 else { return }

        // Compute RMS energy for VAD
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))
        var rmsArray: [Float] = [rms]
        rmsArray.withUnsafeBufferPointer { buf in
            energy.write(buf.baseAddress!, count: 1)
        }

        // Split into bands and compute per-band RMS
        let samplesPerBand = max(1, frameCount / bandCount)
        var bandValues = [Float](repeating: 0, count: bandCount)

        for band in 0..<bandCount {
            let start = band * samplesPerBand
            let end = min(start + samplesPerBand, frameCount)
            let count = end - start
            guard count > 0 else { continue }

            var bandRMS: Float = 0
            vDSP_rmsqv(samples.advanced(by: start), 1, &bandRMS, vDSP_Length(count))

            // Apply logarithmic scaling for perceptual accuracy, clamped to 0..1
            let db = 20 * log10(max(bandRMS, 1e-7))
            let normalized = max(0, min(1, (db + 60) / 60))  // -60dB to 0dB mapped to 0..1
            bandValues[band] = normalized
        }

        bandValues.withUnsafeBufferPointer { buf in
            levels.write(buf.baseAddress!, count: bandCount)
        }
    }

    // MARK: - Emitter Tasks

    /// Periodically drains the ring buffer and yields PCM data chunks to the async stream.
    private func startChunkEmitter() {
        chunkEmitterTask = Task { [weak self, ringBuffer] in
            let chunkSize = Self.chunkSize
            let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { readBuffer.deallocate() }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))

                let available = ringBuffer.availableToRead
                guard available >= chunkSize else { continue }

                // Read in chunk-sized pieces
                var offset = 0
                while offset + chunkSize <= available, !Task.isCancelled {
                    let bytesRead = ringBuffer.read(into: readBuffer, count: chunkSize)
                    guard bytesRead == chunkSize else { break }

                    let data = Data(bytes: readBuffer, count: chunkSize)

                    guard let self else { return }
                    await self.yieldAudioChunk(data)
                    offset += chunkSize
                }
            }
        }
    }

    private func yieldAudioChunk(_ data: Data) {
        audioContinuation?.yield(data)
    }

    /// Polls the atomic levels array and publishes to the async stream at ~30fps.
    private func startLevelsEmitter() {
        levelsEmitterTask = Task { [weak self, currentLevels] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))

                let values = currentLevels.read()

                guard let self else { return }
                await self.yieldLevels(values)
            }
        }
    }

    private func yieldLevels(_ values: [Float]) {
        levelsContinuation?.yield(values)
    }

    /// Polls energy and emits voice activity events based on threshold crossing.
    private func startVADEmitter() {
        vadEmitterTask = Task { [weak self, currentEnergy] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))

                let energyValues = currentEnergy.read()
                let rms = energyValues.first ?? 0

                guard let self else { return }
                await self.processVAD(rms: rms)
            }
        }
    }

    private func processVAD(rms: Float) {
        let now = Date()
        let isAboveThreshold = rms > Self.vadEnergyThreshold

        if isAboveThreshold {
            lastAboveThresholdTime = now
        }

        if isAboveThreshold, !isSpeechActive {
            // Speech onset
            isSpeechActive = true
            speechStartTime = now
            vadContinuation?.yield(.speechStarted)
            logger.debug("VAD: speech started (rms=\(rms))")

        } else if isSpeechActive, !isAboveThreshold {
            // Check if silence has persisted past the timeout
            let silenceDuration: TimeInterval
            if let lastActive = lastAboveThresholdTime {
                silenceDuration = now.timeIntervalSince(lastActive)
            } else {
                silenceDuration = Self.vadSilenceTimeout + 1
            }

            if silenceDuration >= Self.vadSilenceTimeout {
                let speechDuration = speechStartTime.map { now.timeIntervalSince($0) } ?? 0
                isSpeechActive = false
                speechStartTime = nil
                lastAboveThresholdTime = nil
                vadContinuation?.yield(.speechEnded(durationSeconds: speechDuration))
                logger.debug("VAD: speech ended (duration=\(speechDuration)s)")
            }
        }
    }

    // MARK: - Audio Format Conversion Helpers

    /// Create a PCM buffer from raw Int16 data at 16kHz mono.
    private static func pcmBufferFromInt16Data(_ data: Data, sampleRate: Double = captureRate) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AppError.audioEngineFailure("Cannot create Int16 playback format")
        }

        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AppError.audioEngineFailure("Cannot allocate playback buffer")
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            if let src = raw.baseAddress, let dst = buffer.int16ChannelData?[0] {
                dst.update(from: src.bindMemory(to: Int16.self, capacity: Int(frameCount)), count: Int(frameCount))
            }
        }

        return buffer
    }

    /// Decode compressed audio (MP3, AAC, etc.) into a PCM buffer for playback.
    private static func pcmBufferFromCompressedData(_ data: Data) async throws -> AVAudioPCMBuffer {
        // Write to a temporary file because AVAudioFile requires a URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        do {
            try data.write(to: tempURL)
        } catch {
            throw AppError.audioEngineFailure("Failed to write temp audio file: \(error.localizedDescription)")
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: tempURL)
        } catch {
            throw AppError.audioEngineFailure("Cannot decode audio data: \(error.localizedDescription)")
        }

        let processingFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            throw AppError.audioEngineFailure("Cannot allocate buffer for decoded audio")
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            throw AppError.audioEngineFailure("Failed to read decoded audio: \(error.localizedDescription)")
        }

        return buffer
    }

    // MARK: - iOS Audio Session

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setPreferredSampleRate(Self.captureRate)
            try session.setActive(true)
        } catch {
            throw AppError.audioEngineFailure("Audio session configuration failed: \(error.localizedDescription)")
        }
    }
    #endif
}
