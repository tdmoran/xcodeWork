import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "Retry")

struct RetryHandler: Sendable {
    let maxAttempts: Int
    let initialDelay: Duration

    init(maxAttempts: Int = 3, initialDelay: Duration = .milliseconds(500)) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
    }

    func execute<T: Sendable>(operation: @Sendable () async throws -> T) async throws -> T {
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as AppError where error.isRetryable {
                if attempt == maxAttempts {
                    logger.warning("All \(maxAttempts) retry attempts exhausted")
                    throw error
                }
                logger.info("Attempt \(attempt) failed, retrying in \(delay)...")
                try await Task.sleep(for: delay)
                let currentMs = delay.components.seconds * 1000 + delay.components.attoseconds / 1_000_000_000_000_000
                delay = .milliseconds(currentMs * 2)
            }
        }

        fatalError("Unreachable: retry loop must return or throw")
    }
}
