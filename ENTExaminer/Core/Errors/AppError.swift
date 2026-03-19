import Foundation

enum APIService: String, Sendable {
    case anthropic = "Anthropic"
    case elevenLabs = "ElevenLabs"
}

enum AppError: LocalizedError, Equatable {
    // Document errors
    case unsupportedFormat(String)
    case parseFailure(String)
    case documentTooLarge(sizeMB: Double, limitMB: Double)
    case documentEmpty

    // API errors
    case apiKeyMissing(service: APIService)
    case apiRateLimited(retryAfterSeconds: Int)
    case apiServerError(statusCode: Int, message: String)
    case apiNetworkError(String)
    case apiResponseInvalid(detail: String)

    // Audio errors
    case microphoneAccessDenied
    case audioEngineFailure(String)
    case noAudioInputDevice

    // Examination errors
    case examinationInterrupted(reason: String)
    case evaluationFailed(turnIndex: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "The file format '\(format)' is not supported."
        case .parseFailure(let detail):
            return "Could not read the document: \(detail)"
        case .documentTooLarge(let size, let limit):
            return "Document is too large (\(String(format: "%.1f", size)) MB). Maximum is \(String(format: "%.1f", limit)) MB."
        case .documentEmpty:
            return "The document appears to be empty."
        case .apiKeyMissing(let service):
            return "\(service.rawValue) API key is not configured."
        case .apiRateLimited(let seconds):
            return "Rate limited. Please wait \(seconds) seconds."
        case .apiServerError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .apiNetworkError(let detail):
            return "Network error: \(detail)"
        case .apiResponseInvalid(let detail):
            return "Unexpected API response: \(detail)"
        case .microphoneAccessDenied:
            return "Microphone access is required for voice examination."
        case .audioEngineFailure(let detail):
            return "Audio system error: \(detail)"
        case .noAudioInputDevice:
            return "No microphone found. Please connect a microphone."
        case .examinationInterrupted(let reason):
            return "Examination interrupted: \(reason)"
        case .evaluationFailed(let turn):
            return "Could not evaluate response for question \(turn + 1)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedFormat:
            return "Try converting the file to PDF, DOCX, or TXT format."
        case .parseFailure:
            return "The file may be corrupted. Try opening it in another application first."
        case .documentTooLarge:
            return "Try splitting the document into smaller sections."
        case .documentEmpty:
            return "Make sure the file contains readable text content."
        case .apiKeyMissing:
            return "Open Settings to add your API key."
        case .apiRateLimited:
            return "The examination will resume automatically."
        case .apiServerError:
            return "This is usually temporary. Try again in a moment."
        case .apiNetworkError:
            return "Check your internet connection and try again."
        case .apiResponseInvalid:
            return "Try switching to a different AI model in Settings."
        case .microphoneAccessDenied:
            return "Open System Settings > Privacy & Security > Microphone and enable access for ENTExaminer."
        case .audioEngineFailure:
            return "Try restarting the application."
        case .noAudioInputDevice:
            return "Connect a microphone or headset and try again."
        case .examinationInterrupted:
            return "You can resume from where you left off."
        case .evaluationFailed:
            return "The question will be skipped. Your overall score is not affected."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .apiRateLimited, .apiServerError, .apiNetworkError:
            return true
        default:
            return false
        }
    }
}
