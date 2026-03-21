import Foundation
import Testing
@testable import ENTExaminer

@Suite("DocumentStore")
struct DocumentStoreTests {

    @Test("Cache and retrieve text")
    func cacheAndRetrieveText() async {
        let store = DocumentStore.shared
        let hash = "test_hash_\(UUID().uuidString)"
        let text = "This is cached document text for testing."

        await store.cacheText(text, for: hash)
        let retrieved = await store.cachedText(for: hash)

        #expect(retrieved == text)
    }

    @Test("Cache miss returns nil")
    func cacheMissReturnsNil() async {
        let store = DocumentStore.shared
        let result = await store.cachedText(for: "nonexistent_hash_\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test("Cache overwrites previous entry")
    func cacheOverwrites() async {
        let store = DocumentStore.shared
        let hash = "overwrite_test_\(UUID().uuidString)"

        await store.cacheText("Original text", for: hash)
        await store.cacheText("Updated text", for: hash)

        let retrieved = await store.cachedText(for: hash)
        #expect(retrieved == "Updated text")
    }

    @Test("Cache empty text")
    func cacheEmptyText() async {
        let store = DocumentStore.shared
        let hash = "empty_test_\(UUID().uuidString)"

        await store.cacheText("", for: hash)
        let retrieved = await store.cachedText(for: hash)
        #expect(retrieved == "")
    }

    @Test("Load library returns array")
    func loadLibrary() async throws {
        let store = DocumentStore.shared
        let docs = try await store.loadLibrary()
        #expect(docs != nil as [LibraryDocument]?)
    }

    @Test("Save and load library round-trips")
    func saveAndLoadLibrary() async throws {
        let store = DocumentStore.shared

        let testDoc = LibraryDocument(
            id: UUID(),
            title: "Test Document",
            sourceFileName: "test.txt",
            format: .plainText,
            fileSize: 1024,
            addedDate: Date(),
            contentPreview: "Test preview"
        )

        var existing = (try? await store.loadLibrary()) ?? []
        existing = existing + [testDoc]
        try await store.saveLibrary(existing)

        let loaded = try await store.loadLibrary()
        let found = loaded.first(where: { $0.id == testDoc.id })
        #expect(found != nil)
        #expect(found?.title == "Test Document")

        // Clean up
        let cleaned = loaded.filter { $0.id != testDoc.id }
        try await store.saveLibrary(cleaned)
    }

    @Test("Add and load exam session")
    func addAndLoadSession() async throws {
        let store = DocumentStore.shared
        let session = ExamSessionRecord(
            id: UUID(),
            documentId: UUID(),
            date: Date(),
            duration: 300,
            overallScore: 0.85,
            topicsCovered: ["Anatomy", "Physiology"],
            modelUsed: "Haiku 4.5"
        )

        try await store.addSession(session)

        let sessions = try await store.loadSessions()
        let found = sessions.first(where: { $0.id == session.id })
        #expect(found != nil)
        #expect(found?.overallScore == 0.85)
    }
}
