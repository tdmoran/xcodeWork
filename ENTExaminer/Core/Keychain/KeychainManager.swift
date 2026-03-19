import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "KeychainManager")

/// Stores API keys in the app's Application Support directory.
///
/// In a production, code-signed app distributed via the App Store or notarized DMG,
/// this should use the macOS Keychain (Security framework). During development with
/// `swift build` (unsigned binary), Keychain access triggers repeated password prompts.
/// This file-based store avoids that friction while keeping keys out of UserDefaults.
actor KeychainManager {
    static let shared = KeychainManager()

    static let anthropicAccount = "anthropic-api-key"
    static let elevenLabsAccount = "elevenlabs-api-key"

    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ENTExaminer", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir
    }

    func store(key: String, account: String) throws {
        let fileURL = storageURL.appendingPathComponent(account)
        let data = Data(key.utf8)

        // Write with restricted permissions (owner read/write only)
        try data.write(to: fileURL, options: [.atomic])

        // Set file permissions to 0600 (owner read/write only)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )

        logger.info("Stored key for account: \(account)")
    }

    func retrieve(account: String) throws -> String? {
        let fileURL = storageURL.appendingPathComponent(account)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let fileURL = storageURL.appendingPathComponent(account)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
        logger.info("Deleted key for account: \(account)")
    }

    func hasKey(account: String) -> Bool {
        let fileURL = storageURL.appendingPathComponent(account)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store key (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve key (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete key (status: \(status))"
        }
    }
}
