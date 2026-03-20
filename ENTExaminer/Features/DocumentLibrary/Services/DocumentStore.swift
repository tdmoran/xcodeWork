import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "DocumentStore")

/// Persists document library metadata and manages document file storage.
///
/// Directory layout:
/// - Documents/Library/          — active document files
/// - Documents/Library/Archive/  — archived document files
/// - Documents/Library/Cache/    — extracted text cache (keyed by content hash)
/// - Documents/Library/metadata.json — library index
actor DocumentStore {
    static let shared = DocumentStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var libraryRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ENTExaminer/Library", isDirectory: true)
    }

    private var archiveRoot: URL {
        libraryRoot.appendingPathComponent("Archive", isDirectory: true)
    }

    var cacheRoot: URL {
        libraryRoot.appendingPathComponent("Cache", isDirectory: true)
    }

    private var metadataURL: URL {
        libraryRoot.appendingPathComponent("metadata.json")
    }

    private var sessionsURL: URL {
        libraryRoot.appendingPathComponent("sessions.json")
    }

    // MARK: - Initialization

    private init() {}

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    // MARK: - Library CRUD

    func loadLibrary() throws -> [LibraryDocument] {
        try ensureDirectories()

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return []
        }

        let data = try Data(contentsOf: metadataURL)
        return try decoder.decode([LibraryDocument].self, from: data)
    }

    func saveLibrary(_ documents: [LibraryDocument]) throws {
        try ensureDirectories()
        let data = try encoder.encode(documents)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Document File Management

    /// Imports a document file into the library, returning the stored file name.
    func importFile(from sourceURL: URL, documentId: UUID) throws -> String {
        try ensureDirectories()

        let ext = sourceURL.pathExtension
        let storedName = "\(documentId.uuidString).\(ext)"
        let destinationURL = libraryRoot.appendingPathComponent(storedName)

        // Access security-scoped resource if needed
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        logger.info("Imported document to \(storedName)")
        return storedName
    }

    /// Returns the URL for a stored document file.
    func fileURL(for document: LibraryDocument) -> URL {
        if document.isArchived {
            return archiveRoot.appendingPathComponent(document.sourceFileName)
        }
        return libraryRoot.appendingPathComponent(document.sourceFileName)
    }

    /// Archives a document by moving its file to the archive directory.
    func archiveFile(for document: LibraryDocument) throws {
        let source = libraryRoot.appendingPathComponent(document.sourceFileName)
        let destination = archiveRoot.appendingPathComponent(document.sourceFileName)

        guard fileManager.fileExists(atPath: source.path) else { return }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        logger.info("Archived document: \(document.sourceFileName)")
    }

    /// Restores a document from archive to the active library.
    func restoreFile(for document: LibraryDocument) throws {
        let source = archiveRoot.appendingPathComponent(document.sourceFileName)
        let destination = libraryRoot.appendingPathComponent(document.sourceFileName)

        guard fileManager.fileExists(atPath: source.path) else { return }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        logger.info("Restored document: \(document.sourceFileName)")
    }

    /// Permanently deletes a document's file from disk and removes any cached text.
    func deleteFile(for document: LibraryDocument, contentHash: String? = nil) throws {
        let url = fileURL(for: document)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            logger.info("Deleted document file: \(document.sourceFileName)")
        }

        if let hash = contentHash {
            removeCachedText(for: hash)
        }
    }

    // MARK: - Text Extraction Cache

    /// Returns the file URL for a cache entry keyed by content hash.
    private func cacheFileURL(for contentHash: String) -> URL {
        cacheRoot.appendingPathComponent("\(contentHash).txt")
    }

    /// Retrieves previously cached extracted text for the given content hash.
    /// Returns `nil` if no cache entry exists.
    func cachedText(for contentHash: String) -> String? {
        let url = cacheFileURL(for: contentHash)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            logger.debug("Cache hit for hash \(contentHash.prefix(12))…")
            return text
        } catch {
            logger.warning("Failed to read cache for hash \(contentHash.prefix(12))…: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stores extracted text in the cache keyed by content hash.
    func cacheText(_ text: String, for contentHash: String) {
        do {
            try ensureDirectories()
            let url = cacheFileURL(for: contentHash)
            try text.write(to: url, atomically: true, encoding: .utf8)
            logger.debug("Cached text for hash \(contentHash.prefix(12))… (\(text.count) chars)")
        } catch {
            logger.warning("Failed to cache text for hash \(contentHash.prefix(12))…: \(error.localizedDescription)")
        }
    }

    /// Removes a cache entry for the given content hash, if it exists.
    private func removeCachedText(for contentHash: String) {
        let url = cacheFileURL(for: contentHash)
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
            logger.info("Removed cache for hash \(contentHash.prefix(12))…")
        } catch {
            logger.warning("Failed to remove cache for hash \(contentHash.prefix(12))…: \(error.localizedDescription)")
        }
    }

    // MARK: - Exam Session Records

    func loadSessions() throws -> [ExamSessionRecord] {
        try ensureDirectories()

        guard fileManager.fileExists(atPath: sessionsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: sessionsURL)
        return try decoder.decode([ExamSessionRecord].self, from: data)
    }

    func saveSessions(_ sessions: [ExamSessionRecord]) throws {
        try ensureDirectories()
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsURL, options: .atomic)
    }

    func addSession(_ session: ExamSessionRecord) throws {
        var sessions = (try? loadSessions()) ?? []
        sessions = sessions + [session]
        try saveSessions(sessions)
    }
}
