import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "ClaudeAPI")

struct ClaudeAPIClient: Sendable {
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private let apiVersion = "2023-06-01"
    private let sseClient: SSEClient
    private let httpClient: HTTPClient
    private let apiKeyProvider: @Sendable () async -> String?

    init(
        apiKeyProvider: @escaping @Sendable () async -> String?,
        httpClient: HTTPClient = HTTPClient(),
        sseClient: SSEClient = SSEClient()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.httpClient = httpClient
        self.sseClient = sseClient
    }

    // MARK: - Non-Streaming

    func complete(
        model: ClaudeModel,
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 4096
    ) async throws -> ClaudeResponse {
        let apiKey = try await requireAPIKey()
        let sanitized = Self.sanitizeMessages(messages)

        let request = ClaudeMessagesRequest(
            model: model.rawValue,
            maxTokens: maxTokens,
            system: system.isEmpty ? "You are a helpful assistant." : system,
            messages: sanitized,
            stream: false,
            outputConfig: nil
        )

        // Debug: dump request to file for troubleshooting
        if let debugData = try? JSONEncoder().encode(request) {
            let debugURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude_request_debug.json")
            try? debugData.write(to: debugURL)
            logger.info("Debug request written to \(debugURL.path)")
        }

        return try await httpClient.request(
            url: baseURL.appendingPathComponent("messages"),
            method: .post,
            headers: authHeaders(apiKey: apiKey),
            body: request,
            responseType: ClaudeResponse.self
        )
    }

    // MARK: - Structured Output

    func completeStructured<T: Decodable>(
        model: ClaudeModel,
        system: String,
        messages: [ClaudeMessage],
        schema: JSONSchemaValue,
        maxTokens: Int = 4096,
        responseType: T.Type
    ) async throws -> T {
        let apiKey = try await requireAPIKey()

        let request = ClaudeMessagesRequest(
            model: model.rawValue,
            maxTokens: maxTokens,
            system: system,
            messages: messages,
            stream: false,
            outputConfig: .init(format: .init(type: "json_schema", schema: schema))
        )

        let response = try await httpClient.request(
            url: baseURL.appendingPathComponent("messages"),
            method: .post,
            headers: authHeaders(apiKey: apiKey),
            body: request,
            responseType: ClaudeResponse.self
        )

        guard let text = response.content.first?.text,
              let data = text.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "No text content in response")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Streaming

    func stream(
        model: ClaudeModel,
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try await requireAPIKey()

                    let sanitized = Self.sanitizeMessages(messages)
                    let request = ClaudeMessagesRequest(
                        model: model.rawValue,
                        maxTokens: maxTokens,
                        system: system.isEmpty ? "You are a helpful assistant." : system,
                        messages: sanitized,
                        stream: true,
                        outputConfig: nil
                    )

                    let body = try JSONEncoder().encode(request)

                    let events = sseClient.stream(
                        url: baseURL.appendingPathComponent("messages"),
                        method: "POST",
                        headers: authHeaders(apiKey: apiKey),
                        body: body
                    )

                    for try await event in events {
                        if Task.isCancelled { break }

                        guard let parsed = parseStreamEvent(event) else { continue }
                        continuation.yield(parsed)
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    /// Filters out empty text content blocks that Claude's API rejects.
    private static func sanitizeMessages(_ messages: [ClaudeMessage]) -> [ClaudeMessage] {
        messages.map { message in
            let filtered = message.content.compactMap { block -> ClaudeMessage.ContentBlock? in
                if case .text(let text) = block {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { return nil }
                    return .text(trimmed)
                }
                return block
            }
            // Ensure at least one content block per message
            let safeContent = filtered.isEmpty ? [ClaudeMessage.ContentBlock.text("(no content)")] : filtered
            return ClaudeMessage(role: message.role, content: safeContent)
        }
    }

    private func requireAPIKey() async throws -> String {
        guard let key = await apiKeyProvider() else {
            throw AppError.apiKeyMissing(service: .anthropic)
        }
        return key
    }

    private func authHeaders(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": apiVersion,
            "content-type": "application/json",
        ]
    }

    private func parseStreamEvent(_ event: SSEEvent) -> ClaudeStreamEvent? {
        guard let data = event.data.data(using: .utf8) else { return nil }

        switch event.event {
        case "content_block_delta":
            struct Delta: Decodable {
                let delta: DeltaContent
                struct DeltaContent: Decodable {
                    let type: String
                    let text: String?
                }
            }
            guard let delta = try? JSONDecoder().decode(Delta.self, from: data),
                  delta.delta.type == "text_delta",
                  let text = delta.delta.text else { return nil }
            return .textDelta(text)

        case "message_delta":
            struct MessageDelta: Decodable {
                let usage: Usage?
                struct Usage: Decodable {
                    let outputTokens: Int
                    enum CodingKeys: String, CodingKey {
                        case outputTokens = "output_tokens"
                    }
                }
            }
            guard let parsed = try? JSONDecoder().decode(MessageDelta.self, from: data),
                  let usage = parsed.usage else { return nil }
            return .messageComplete(ClaudeStreamUsage(
                inputTokens: 0,
                outputTokens: usage.outputTokens
            ))

        case "error":
            struct ErrorEvent: Decodable {
                let error: ErrorDetail
                struct ErrorDetail: Decodable {
                    let message: String
                }
            }
            if let parsed = try? JSONDecoder().decode(ErrorEvent.self, from: data) {
                return .error(parsed.error.message)
            }
            return .error("Unknown streaming error")

        default:
            return nil
        }
    }
}
