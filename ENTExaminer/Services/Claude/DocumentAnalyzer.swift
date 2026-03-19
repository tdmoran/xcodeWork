import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "DocumentAnalyzer")

struct DocumentAnalyzer: Sendable {
    private let client: ClaudeAPIClient
    private let retryHandler: RetryHandler

    init(client: ClaudeAPIClient, retryHandler: RetryHandler = RetryHandler()) {
        self.client = client
        self.retryHandler = retryHandler
    }

    func analyze(
        document: ParsedDocument,
        model: ClaudeModel
    ) async throws -> DocumentAnalysis {
        logger.info("Analyzing document: \(document.metadata.title ?? "untitled") with \(model.displayName)")

        let systemPrompt = """
        You are analyzing a document to prepare for an oral examination. \
        Extract the key topics, concepts, and testable knowledge from this document.

        Respond with valid JSON matching this exact structure:
        {
            "topics": [
                {
                    "name": "Topic Name",
                    "importance": 0.8,
                    "keyConcepts": ["concept1", "concept2"],
                    "difficulty": "intermediate",
                    "subtopics": ["subtopic1", "subtopic2"]
                }
            ],
            "documentSummary": "Brief summary of the document",
            "suggestedQuestionCount": 15,
            "estimatedDurationMinutes": 20,
            "difficultyAssessment": "intermediate"
        }

        Importance is 0.0-1.0. Difficulty is "foundational", "intermediate", or "advanced".
        Identify 3-8 major topics. Each topic should have 2-5 key concepts.
        """

        // Guard against empty content
        let documentText = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !documentText.isEmpty else {
            throw AppError.documentEmpty
        }

        // Truncate to stay within context window (~150k chars ≈ ~37k tokens, leaving room for system prompt + response)
        let maxChars = 150_000
        let truncatedText = documentText.count > maxChars
            ? String(documentText.prefix(maxChars)) + "\n\n[Document truncated at \(maxChars) characters]"
            : documentText

        logger.info("Sending \(truncatedText.count) characters to Claude for analysis")

        let userMessage = ClaudeMessage(
            role: .user,
            content: [.text("Analyze this document for examination:\n\n\(truncatedText)")]
        )

        let response = try await retryHandler.execute {
            try await client.complete(
                model: model,
                system: systemPrompt,
                messages: [userMessage],
                maxTokens: 4096
            )
        }

        guard let jsonText = response.content.first?.text,
              let data = jsonText.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "No analysis content returned")
        }

        // Try to extract JSON from potential markdown code blocks
        let cleanJSON = extractJSON(from: jsonText)
        guard let cleanData = cleanJSON.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "Could not parse analysis response")
        }

        let analysis = try JSONDecoder().decode(DocumentAnalysis.self, from: cleanData)
        logger.info("Analysis complete: \(analysis.topics.count) topics identified")
        return analysis
    }

    private func extractJSON(from text: String) -> String {
        // Strip markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Analysis Models

struct DocumentAnalysis: Codable, Sendable, Equatable {
    let topics: [ExamTopic]
    let documentSummary: String
    let suggestedQuestionCount: Int
    let estimatedDurationMinutes: Int
    let difficultyAssessment: String
}

struct ExamTopic: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let importance: Double
    let keyConcepts: [String]
    let difficulty: Difficulty
    let subtopics: [String]

    var id: String { name }

    enum Difficulty: String, Codable, Sendable, Equatable, CaseIterable {
        case foundational
        case intermediate
        case advanced

        var displayName: String {
            rawValue.capitalized
        }
    }
}
