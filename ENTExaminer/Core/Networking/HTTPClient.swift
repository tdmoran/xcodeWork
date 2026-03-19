import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "HTTPClient")

struct HTTPClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        body: (any Encodable)? = nil,
        responseType: T.Type
    ) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        logger.debug("HTTP \(method.rawValue) \(url.absoluteString)")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.apiNetworkError("Invalid response type")
        }

        logger.debug("HTTP \(httpResponse.statusCode) \(url.absoluteString)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"

            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init) ?? 30
                throw AppError.apiRateLimited(retryAfterSeconds: retryAfter)
            }

            throw AppError.apiServerError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }
}
