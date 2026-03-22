import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "SSEClient")

struct SSEEvent: Sendable {
    let event: String?
    let data: String
}

struct SSEClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = method
                    request.httpBody = body

                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AppError.apiNetworkError("Invalid response type")
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        throw AppError.apiServerError(
                            statusCode: httpResponse.statusCode,
                            message: body
                        )
                    }

                    var currentEvent: String?
                    var currentData = ""

                    // Note: bytes.lines skips empty lines, so we cannot rely on
                    // blank-line dispatch per the SSE spec. Instead, dispatch the
                    // previous event whenever a new "event:" line arrives (which
                    // signals the start of a new SSE block).
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event:") {
                            // A new event block starting — flush the previous one
                            if !currentData.isEmpty {
                                let event = SSEEvent(
                                    event: currentEvent,
                                    data: currentData.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                                continuation.yield(event)
                            }
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            currentData = ""
                        } else if line.hasPrefix("data:") {
                            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if !currentData.isEmpty {
                                currentData += "\n"
                            }
                            currentData += data
                        }
                        // Ignore "id:", "retry:", and comments (":")
                    }

                    // Flush any remaining event after the stream ends
                    if !currentData.isEmpty {
                        let event = SSEEvent(
                            event: currentEvent,
                            data: currentData.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        logger.error("SSE stream error: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
