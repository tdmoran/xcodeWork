import Testing
@testable import ENTExaminer

@Suite("DocumentChunker")
struct DocumentChunkerTests {

    func makeDocument(text: String, sections: [DocumentSection] = []) -> ParsedDocument {
        ParsedDocument(
            text: text,
            sections: sections,
            metadata: FileMetadata(
                url: URL(fileURLWithPath: "/test.txt"),
                title: "Test",
                fileSize: Int64(text.utf8.count),
                pageCount: nil,
                format: .plainText
            ),
            contentHash: "testhash"
        )
    }

    @Test("Empty document returns no chunks")
    func emptyDocumentReturnsNoChunks() {
        let chunker = DocumentChunker()
        let doc = makeDocument(text: "")
        let chunks = chunker.chunk(doc, strategy: .byParagraph)
        #expect(chunks.isEmpty)
    }

    @Test("Small document returns single chunk")
    func smallDocumentReturnsSingleChunk() {
        let chunker = DocumentChunker(targetTokens: 4000)
        let text = "This is a short document with minimal content."
        let doc = makeDocument(text: text)
        let chunks = chunker.chunk(doc, strategy: .byParagraph)
        #expect(chunks.count == 1)
        #expect(chunks[0].text == text)
    }

    @Test("Large document produces multiple chunks")
    func largeDocumentProducesMultipleChunks() {
        let chunker = DocumentChunker(targetTokens: 50, overlapTokens: 10)
        let paragraph = String(repeating: "word ", count: 80)
        let text = paragraph + "\n\n" + paragraph + "\n\n" + paragraph
        let doc = makeDocument(text: text)
        let chunks = chunker.chunk(doc, strategy: .byParagraph)
        #expect(chunks.count > 1)
    }

    @Test("Section chunking respects boundaries")
    func sectionChunkingRespectsBoundaries() {
        let sections = [
            DocumentSection(title: "Intro", content: "Intro content.", pageNumber: 1),
            DocumentSection(title: "Methods", content: "Methods content.", pageNumber: 2),
            DocumentSection(title: "Results", content: "Results content.", pageNumber: 3),
        ]
        let text = sections.map(\.content).joined(separator: "\n\n")
        let doc = makeDocument(text: text, sections: sections)

        let chunker = DocumentChunker(targetTokens: 4000)
        let chunks = chunker.chunk(doc, strategy: .bySection)
        #expect(chunks.count == 1)
        #expect(chunks[0].sectionTitle == "Intro")
    }

    @Test("Page chunking includes page ranges")
    func pageChunkingUsesPageRanges() {
        let sections = (1...5).map { page in
            DocumentSection(title: "Page \(page)", content: "Content for page \(page)", pageNumber: page)
        }
        let text = sections.map(\.content).joined(separator: "\n\n")
        let doc = makeDocument(text: text, sections: sections)

        let chunker = DocumentChunker(targetTokens: 4000)
        let chunks = chunker.chunk(doc, strategy: .byPage)
        #expect(!chunks.isEmpty)
        #expect(chunks[0].pageRange != nil)
    }

    @Test("Relevant chunks finds keyword matches")
    func relevantChunksFindsMatches() {
        let chunker = DocumentChunker()
        let chunks = [
            DocumentChunk(text: "Photosynthesis converts light energy into chemical energy."),
            DocumentChunk(text: "Cell respiration produces ATP through glucose oxidation."),
            DocumentChunk(text: "DNA replication occurs during the S phase of the cell cycle."),
        ]

        let relevant = chunker.relevantChunks(for: "photosynthesis light energy", in: chunks, maxResults: 2)
        #expect(!relevant.isEmpty)
        #expect(relevant[0].text.contains("Photosynthesis"))
    }

    @Test("Relevant chunks excludes non-matching")
    func relevantChunksExcludesNoMatches() {
        let chunker = DocumentChunker()
        let chunks = [
            DocumentChunk(text: "This chunk is about bananas."),
            DocumentChunk(text: "This chunk is about oranges."),
        ]

        let relevant = chunker.relevantChunks(for: "quantum mechanics", in: chunks, maxResults: 5)
        #expect(relevant.isEmpty)
    }

    @Test("Empty query returns first chunks")
    func emptyQueryReturnsFirstChunks() {
        let chunker = DocumentChunker()
        let chunks = [
            DocumentChunk(text: "Chunk 1"),
            DocumentChunk(text: "Chunk 2"),
            DocumentChunk(text: "Chunk 3"),
        ]

        let relevant = chunker.relevantChunks(for: "", in: chunks, maxResults: 2)
        #expect(relevant.count == 2)
    }

    @Test("Token estimation is approximately correct")
    func tokenEstimation() {
        let text = String(repeating: "a", count: 400)
        let chunk = DocumentChunk(text: text)
        #expect(chunk.estimatedTokens == 100)
    }
}
