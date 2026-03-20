import Foundation

// MARK: - Saved Session Types

struct SavedDialogueMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String
    let timestamp: Date
}

struct SavedAssessment: Codable, Sendable, Equatable {
    let topicName: String
    let understanding: Double
    let confidence: Double
}

struct SavedExamSession: Codable, Sendable, Equatable {
    let id: UUID
    let documentId: UUID
    let documentTitle: String
    let savedDate: Date
    let elapsedTime: TimeInterval
    let isConversationalMode: Bool
    let dialogueMessages: [SavedDialogueMessage]
    let modelUsed: String
    let topicsCovered: [String]
    let assessmentScores: [SavedAssessment]
    let status: String
}

// MARK: - Persistence Errors

enum SessionPersistenceError: Error, LocalizedError {
    case sessionNotFound(UUID)
    case directoryCreationFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .directoryCreationFailed(let detail):
            return "Failed to create sessions directory: \(detail)"
        case .encodingFailed(let detail):
            return "Failed to encode session: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode session: \(detail)"
        case .deletionFailed(let detail):
            return "Failed to delete session: \(detail)"
        }
    }
}

// MARK: - Session Persistence Service

actor SessionPersistenceService {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        self.decoder = jsonDecoder
    }

    // MARK: - Directory Management

    private var sessionsDirectory: URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("ENTExaminer", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private func ensureDirectoryExists() throws {
        let directory = sessionsDirectory
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw SessionPersistenceError.directoryCreationFailed(error.localizedDescription)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Public API

    func saveSession(_ session: SavedExamSession) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw SessionPersistenceError.encodingFailed(error.localizedDescription)
        }

        let url = fileURL(for: session.id)
        try data.write(to: url, options: .atomic)
    }

    func loadSession(id: UUID) throws -> SavedExamSession {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SessionPersistenceError.sessionNotFound(id)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SessionPersistenceError.decodingFailed(error.localizedDescription)
        }

        do {
            return try decoder.decode(SavedExamSession.self, from: data)
        } catch {
            throw SessionPersistenceError.decodingFailed(error.localizedDescription)
        }
    }

    func listSessions() throws -> [SavedExamSession] {
        try ensureDirectoryExists()

        let directory = sessionsDirectory
        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            return []
        }

        let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }

        return jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(SavedExamSession.self, from: data)
            else { return nil }
            return session
        }
        .sorted { $0.savedDate > $1.savedDate }
    }

    func deleteSession(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SessionPersistenceError.sessionNotFound(id)
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw SessionPersistenceError.deletionFailed(error.localizedDescription)
        }
    }

    func sessionsForDocument(id: UUID) throws -> [SavedExamSession] {
        let allSessions = try listSessions()
        return allSessions.filter { $0.documentId == id }
    }
}
