import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "ElevenLabsTTS")

/// ElevenLabs text-to-speech service that streams audio from the REST API
/// and feeds chunks to ``AudioPipeline`` for low-latency playback.
actor ElevenLabsTTSService: TTSService {
    // MARK: - Configuration

    private static let baseURL = URL(string: "https://api.elevenlabs.io/v1/text-to-speech")!
    private static let modelId = "eleven_flash_v2_5"
    private static let defaultStability: Double = 0.7
    private static let defaultSimilarityBoost: Double = 0.8
    private static let streamChunkSize = 8192

    // MARK: - Dependencies

    private let apiKeyProvider: @Sendable () async -> String?
    private let audioPipeline: AudioPipeline
    private let session: URLSession

    // MARK: - State

    private var activeStreamTask: Task<Void, Error>?

    // MARK: - Initialization

    /// Creates a new ElevenLabs TTS service.
    ///
    /// - Parameters:
    ///   - apiKeyProvider: An async closure that returns the ElevenLabs API key, or nil if not configured.
    ///   - audioPipeline: The audio pipeline used for playback of streamed audio chunks.
    ///   - session: The URL session to use for HTTP requests. Defaults to `.shared`.
    init(
        apiKeyProvider: @escaping @Sendable () async -> String?,
        audioPipeline: AudioPipeline,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.audioPipeline = audioPipeline
        self.session = session
    }

    // MARK: - TTSService

    func speak(
        text: String,
        voiceId: String,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        // Cancel any in-progress speech before starting new
        cancelActiveStream()

        // Ensure audio engine is running for playback
        NSLog("[ElevenLabsTTS] speak() called with text: %@", String(text.prefix(60)))
        
        // Write to debug log
        let debugUrl = URL(fileURLWithPath: "/tmp/entexaminer_audio.log")
        let debugLine = "\(Date()): TTS speak() called: \(text.prefix(50))\n"
        if let data = debugLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugUrl.path) {
                if let handle = try? FileHandle(forWritingTo: debugUrl) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: debugUrl)
            }
        }
        
        try await audioPipeline.startPlayback()

        let apiKey = try await requireAPIKey()
        let request = try buildRequest(text: text, voiceId: voiceId, apiKey: apiKey)

        logger.info("Starting TTS stream for \(text.prefix(50))...")

        let streamTask = Task { [session, audioPipeline] in
            let (bytes, response) = try await session.bytes(for: request)

            try Self.validateResponse(response)

            // Buffer incoming bytes and flush in chunks for smooth playback
            let chunkSize = Self.streamChunkSize
            var accumulatedData = Data()
            accumulatedData.reserveCapacity(chunkSize * 2)
            var totalBytes = 0

            for try await byte in bytes {
                if Task.isCancelled { break }
                accumulatedData.append(byte)

                if accumulatedData.count >= chunkSize {
                    let chunk = accumulatedData
                    accumulatedData = Data()
                    accumulatedData.reserveCapacity(chunkSize * 2)
                    totalBytes += chunk.count

                    try await audioPipeline.playAudioChunk(chunk, format: .pcm24kHz)

                    let level = Self.estimateAudioLevel(from: chunk)
                    onAudioLevel(level)
                }
            }

            // Play any remaining bytes
            if !accumulatedData.isEmpty, !Task.isCancelled {
                totalBytes += accumulatedData.count
                try await audioPipeline.playAudioChunk(accumulatedData, format: .pcm24kHz)
                let level = Self.estimateAudioLevel(from: accumulatedData)
                onAudioLevel(level)
            }

            // Wait for all queued audio to finish playing
            await audioPipeline.waitForPlaybackCompletion()

            // Signal silence when done
            onAudioLevel(0)
            logger.info("TTS stream completed (\(totalBytes) bytes)")
        }

        activeStreamTask = streamTask

        // Await completion so the caller knows when speech finishes
        try await streamTask.value
        activeStreamTask = nil
    }

    func stopSpeaking() async {
        cancelActiveStream()
        logger.info("TTS playback stopped by request")
    }

    // MARK: - Private Helpers

    private func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
    }

    private func requireAPIKey() async throws -> String {
        guard let key = await apiKeyProvider() else {
            throw AppError.apiKeyMissing(service: .elevenLabs)
        }
        return key
    }

    private func buildRequest(
        text: String,
        voiceId: String,
        apiKey: String
    ) throws -> URLRequest {
        // Use output_format=pcm_24000 for raw PCM that streams correctly
        // (MP3 chunks aren't valid standalone files for AVAudioFile)
        var components = URLComponents(url: Self.baseURL
            .appendingPathComponent(voiceId)
            .appendingPathComponent("stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = TTSRequestBody(
            text: text,
            modelId: Self.modelId,
            voiceSettings: VoiceSettings(
                stability: Self.defaultStability,
                similarityBoost: Self.defaultSimilarityBoost
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        return request
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.apiNetworkError("Invalid response type from ElevenLabs")
        }

        logger.debug("ElevenLabs response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init) ?? 30
                throw AppError.apiRateLimited(retryAfterSeconds: retryAfter)
            }

            throw AppError.apiServerError(
                statusCode: httpResponse.statusCode,
                message: "ElevenLabs TTS request failed"
            )
        }
    }

    /// Estimates a rough audio level from MP3 data bytes for visualization.
    /// This is an approximation based on byte magnitude since decoding MP3
    /// frames on the fly is expensive. The AudioPipeline provides precise
    /// levels during actual playback.
    private static func estimateAudioLevel(from data: Data) -> Float {
        guard !data.isEmpty else { return 0 }

        var sum: Float = 0
        let sampleStride = max(1, data.count / 256)

        for i in stride(from: 0, to: data.count, by: sampleStride) {
            let sample = Float(data[i])
            // Center around 128 (MP3 byte midpoint) and normalize
            let centered = abs(sample - 128) / 128
            sum += centered
        }

        let sampleCount = Float(data.count / sampleStride)
        let average = sum / max(sampleCount, 1)

        // Scale to a perceptually useful range, clamped to 0..1
        return min(1, average * 2.5)
    }
}

// MARK: - Request Types

private struct TTSRequestBody: Encodable {
    let text: String
    let modelId: String
    let voiceSettings: VoiceSettings

    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
        case voiceSettings = "voice_settings"
    }
}

private struct VoiceSettings: Encodable {
    let stability: Double
    let similarityBoost: Double

    enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
    }
}
