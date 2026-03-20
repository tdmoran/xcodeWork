import Foundation

// MARK: - Chunking Strategy

/// Determines how a document is split into chunks for context windows.
enum ChunkingStrategy: String, Sendable, CaseIterable {
    /// Split by page boundaries (best for page-oriented documents like PDFs).
    case byPage
    /// Split by section headings.
    case bySection
    /// Split by paragraph boundaries.
    case byParagraph
    /// Auto-detect the best strategy based on document structure.
    case smart
}

// MARK: - Document Chunk

/// A segment of a parsed document sized for inclusion in a Claude context window.
struct DocumentChunk: Sendable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let pageRange: ClosedRange<Int>?
    let estimatedTokens: Int
    let sectionTitle: String?

    init(
        id: UUID = UUID(),
        text: String,
        pageRange: ClosedRange<Int>? = nil,
        estimatedTokens: Int? = nil,
        sectionTitle: String? = nil
    ) {
        self.id = id
        self.text = text
        self.pageRange = pageRange
        self.estimatedTokens = estimatedTokens ?? (text.count / 4)
        self.sectionTitle = sectionTitle
    }
}

// MARK: - Document Chunker

/// Splits a `ParsedDocument` into manageable chunks for Claude context windows.
///
/// This is a pure, stateless service. All methods produce new values
/// without mutating any shared state.
struct DocumentChunker: Sendable {

    /// Target chunk size in estimated tokens (~4 chars per token).
    let targetTokens: Int

    /// Overlap in estimated tokens to preserve context across chunk boundaries.
    let overlapTokens: Int

    /// Characters per estimated token (rough heuristic for English text).
    private static let charsPerToken: Int = 4

    init(targetTokens: Int = 4_000, overlapTokens: Int = 200) {
        self.targetTokens = max(targetTokens, 100)
        self.overlapTokens = max(min(overlapTokens, targetTokens / 4), 0)
    }

    // MARK: - Public API

    /// Chunks a parsed document using the specified strategy.
    func chunk(_ document: ParsedDocument, strategy: ChunkingStrategy = .smart) -> [DocumentChunk] {
        let resolvedStrategy = strategy == .smart
            ? detectBestStrategy(for: document)
            : strategy

        let chunks: [DocumentChunk]
        switch resolvedStrategy {
        case .byPage:
            chunks = chunkByPage(document)
        case .bySection:
            chunks = chunkBySection(document)
        case .byParagraph:
            chunks = chunkByParagraph(document)
        case .smart:
            // Already resolved above; unreachable but handled for exhaustiveness.
            chunks = chunkBySection(document)
        }

        return chunks
    }

    /// Finds chunks relevant to a given topic or question using keyword matching.
    ///
    /// Returns chunks sorted by descending relevance score. Chunks with no
    /// keyword matches are excluded.
    func relevantChunks(
        for query: String,
        in chunks: [DocumentChunk],
        maxResults: Int = 5
    ) -> [DocumentChunk] {
        let keywords = extractKeywords(from: query)

        guard !keywords.isEmpty else {
            return Array(chunks.prefix(maxResults))
        }

        let scored: [(chunk: DocumentChunk, score: Int)] = chunks.compactMap { chunk in
            let lowerText = chunk.text.lowercased()
            let score = keywords.reduce(0) { total, keyword in
                total + countOccurrences(of: keyword, in: lowerText)
            }
            return score > 0 ? (chunk, score) : nil
        }

        let sorted = scored
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map(\.chunk)

        return Array(sorted)
    }

    // MARK: - Strategy Detection

    private func detectBestStrategy(for document: ParsedDocument) -> ChunkingStrategy {
        let hasPages = document.sections.contains { $0.pageNumber != nil }
        let hasTitledSections = document.sections.contains { $0.title != nil }
        let sectionCount = document.sections.count

        // Prefer section boundaries when the document has titled sections.
        if hasTitledSections && sectionCount >= 2 {
            return .bySection
        }

        // Fall back to page boundaries for page-oriented documents.
        if hasPages && sectionCount >= 2 {
            return .byPage
        }

        // Otherwise split by paragraph.
        return .byParagraph
    }

    // MARK: - Page Chunking

    private func chunkByPage(_ document: ParsedDocument) -> [DocumentChunk] {
        let targetChars = targetTokens * Self.charsPerToken
        var result: [DocumentChunk] = []
        var buffer = ""
        var startPage: Int?
        var endPage: Int?

        for section in document.sections {
            let page = section.pageNumber

            let wouldExceed = buffer.count + section.content.count > targetChars && !buffer.isEmpty

            if wouldExceed {
                result.append(makeChunk(
                    text: buffer,
                    pageRange: pageRange(start: startPage, end: endPage),
                    sectionTitle: nil
                ))
                let overlap = overlapSuffix(from: buffer)
                buffer = overlap + section.content
                startPage = page
                endPage = page
            } else {
                if buffer.isEmpty {
                    startPage = page
                }
                if !buffer.isEmpty {
                    buffer += "\n\n"
                }
                buffer += section.content
                endPage = page
            }
        }

        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(makeChunk(
                text: buffer,
                pageRange: pageRange(start: startPage, end: endPage),
                sectionTitle: nil
            ))
        }

        return result
    }

    // MARK: - Section Chunking

    private func chunkBySection(_ document: ParsedDocument) -> [DocumentChunk] {
        let targetChars = targetTokens * Self.charsPerToken
        var result: [DocumentChunk] = []
        var buffer = ""
        var bufferTitle: String?
        var startPage: Int?
        var endPage: Int?

        for section in document.sections {
            let wouldExceed = buffer.count + section.content.count > targetChars && !buffer.isEmpty

            if wouldExceed {
                result.append(makeChunk(
                    text: buffer,
                    pageRange: pageRange(start: startPage, end: endPage),
                    sectionTitle: bufferTitle
                ))
                let overlap = overlapSuffix(from: buffer)
                buffer = overlap + section.content
                bufferTitle = section.title
                startPage = section.pageNumber
                endPage = section.pageNumber
            } else {
                if buffer.isEmpty {
                    bufferTitle = section.title
                    startPage = section.pageNumber
                }
                if !buffer.isEmpty {
                    buffer += "\n\n"
                }
                buffer += section.content
                endPage = section.pageNumber
            }
        }

        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(makeChunk(
                text: buffer,
                pageRange: pageRange(start: startPage, end: endPage),
                sectionTitle: bufferTitle
            ))
        }

        // If sections produced nothing (e.g. no sections), fall back to paragraph.
        if result.isEmpty && !document.text.isEmpty {
            return chunkByParagraph(document)
        }

        return result
    }

    // MARK: - Paragraph Chunking

    private func chunkByParagraph(_ document: ParsedDocument) -> [DocumentChunk] {
        let targetChars = targetTokens * Self.charsPerToken
        let paragraphs = splitIntoParagraphs(document.text)
        var result: [DocumentChunk] = []
        var buffer = ""

        for paragraph in paragraphs {
            let wouldExceed = buffer.count + paragraph.count > targetChars && !buffer.isEmpty

            if wouldExceed {
                result.append(makeChunk(text: buffer, pageRange: nil, sectionTitle: nil))
                let overlap = overlapSuffix(from: buffer)
                buffer = overlap + paragraph
            } else {
                if !buffer.isEmpty {
                    buffer += "\n\n"
                }
                buffer += paragraph
            }
        }

        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(makeChunk(text: buffer, pageRange: nil, sectionTitle: nil))
        }

        return result
    }

    // MARK: - Helpers

    private func makeChunk(
        text: String,
        pageRange: ClosedRange<Int>?,
        sectionTitle: String?
    ) -> DocumentChunk {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return DocumentChunk(
            text: trimmed,
            pageRange: pageRange,
            sectionTitle: sectionTitle
        )
    }

    private func pageRange(start: Int?, end: Int?) -> ClosedRange<Int>? {
        guard let s = start, let e = end else { return nil }
        return s...e
    }

    /// Returns the trailing overlap text from a buffer (approximately `overlapTokens` tokens).
    private func overlapSuffix(from text: String) -> String {
        let overlapChars = overlapTokens * Self.charsPerToken
        guard text.count > overlapChars else { return text }

        let startIndex = text.index(text.endIndex, offsetBy: -overlapChars)
        let suffix = String(text[startIndex...])

        // Try to break at a word boundary to avoid splitting mid-word.
        if let spaceIndex = suffix.firstIndex(of: " ") {
            return String(suffix[suffix.index(after: spaceIndex)...])
        }
        return suffix
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Extracts lowercase keywords from a query, filtering out common stop words.
    private func extractKeywords(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were", "be", "been",
            "being", "have", "has", "had", "do", "does", "did", "will",
            "would", "could", "should", "may", "might", "shall", "can",
            "of", "in", "to", "for", "with", "on", "at", "from", "by",
            "about", "as", "into", "through", "during", "before", "after",
            "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
            "neither", "each", "every", "all", "any", "few", "more", "most",
            "other", "some", "such", "no", "only", "own", "same", "than",
            "too", "very", "just", "because", "if", "when", "where", "how",
            "what", "which", "who", "whom", "this", "that", "these", "those",
            "it", "its", "i", "me", "my", "we", "our", "you", "your", "he",
            "him", "his", "she", "her", "they", "them", "their",
        ]

        let cleaned = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }

        // Deduplicate while preserving order.
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }
    }

    /// Counts non-overlapping occurrences of a substring in a string.
    private func countOccurrences(of substring: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }

        return count
    }
}
