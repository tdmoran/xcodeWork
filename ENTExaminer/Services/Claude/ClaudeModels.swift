import Foundation

enum ClaudeModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case haiku = "claude-haiku-4-5"
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-6"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku: return "Haiku 4.5"
        case .sonnet: return "Sonnet 4.6"
        case .opus: return "Opus 4.6"
        }
    }

    var description: String {
        switch self {
        case .haiku: return "Fast and lightweight — ideal for most examinations"
        case .sonnet: return "Balanced intelligence and speed — recommended for technical content"
        case .opus: return "Deepest reasoning — best for complex, specialized material"
        }
    }

    var costTier: String {
        switch self {
        case .haiku: return "$"
        case .sonnet: return "$$"
        case .opus: return "$$$"
        }
    }

    var contextWindow: Int {
        switch self {
        case .haiku: return 200_000
        case .sonnet: return 200_000
        case .opus: return 200_000
        }
    }
}

// MARK: - API Request/Response Types

struct ClaudeMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [ClaudeMessage]
    let stream: Bool
    let outputConfig: OutputConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
        case outputConfig = "output_config"
    }

    struct OutputConfig: Encodable {
        let format: OutputFormat

        struct OutputFormat: Encodable {
            let type: String
            let schema: JSONSchemaValue?
        }
    }
}

struct ClaudeMessage: Codable, Sendable {
    let role: Role
    let content: [ContentBlock]

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    enum ContentBlock: Codable, Sendable {
        case text(String)
        case document(DocumentBlock)

        struct DocumentBlock: Codable, Sendable {
            let type: String
            let source: Source

            struct Source: Codable, Sendable {
                let type: String
                let mediaType: String
                let data: String

                enum CodingKeys: String, CodingKey {
                    case type
                    case mediaType = "media_type"
                    case data
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case type, text, source
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .document(let doc):
                try container.encode(doc.type, forKey: .type)
                try container.encode(doc.source, forKey: .source)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                let text = try container.decode(String.self, forKey: .text)
                self = .text(text)
            default:
                let source = try container.decode(DocumentBlock.Source.self, forKey: .source)
                self = .document(DocumentBlock(type: type, source: source))
            }
        }
    }
}

struct ClaudeResponse: Decodable {
    let id: String
    let content: [ContentItem]
    let usage: Usage

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    var textContent: String {
        content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
    }
}

// MARK: - Streaming Event Types

enum ClaudeStreamEvent: Sendable {
    case textDelta(String)
    case messageComplete(ClaudeStreamUsage)
    case error(String)
}

struct ClaudeStreamUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - JSON Schema Helper

indirect enum JSONSchemaValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONSchemaValue])
    case object([String: JSONSchemaValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
