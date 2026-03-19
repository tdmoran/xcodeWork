import Foundation
import UniformTypeIdentifiers

enum DocumentFormat: String, Sendable, CaseIterable {
    case pdf
    case docx
    case plainText
    case markdown
    case image

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .plainText: return "TXT"
        case .markdown: return "Markdown"
        case .image: return "Image"
        }
    }

    var utTypes: [UTType] {
        switch self {
        case .pdf: return [.pdf]
        case .docx: return [UTType("org.openxmlformats.wordprocessingml.document") ?? .data]
        case .plainText: return [.plainText, .utf8PlainText]
        case .markdown: return [UTType("net.daringfireball.markdown") ?? .plainText]
        case .image: return [.png, .jpeg, .heic, .tiff]
        }
    }

    static func detect(from url: URL) -> DocumentFormat? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .pdf
        case "docx": return .docx
        case "txt", "text": return .plainText
        case "md", "markdown": return .markdown
        case "png", "jpg", "jpeg", "heic", "tiff": return .image
        default: return nil
        }
    }
}

struct FileMetadata: Sendable, Equatable {
    let url: URL
    let title: String?
    let fileSize: Int64
    let pageCount: Int?
    let format: DocumentFormat

    var fileSizeMB: Double {
        Double(fileSize) / 1_048_576.0
    }

    var fileSizeFormatted: String {
        if fileSizeMB >= 1.0 {
            return String(format: "%.1f MB", fileSizeMB)
        } else {
            let kb = Double(fileSize) / 1024.0
            return String(format: "%.0f KB", kb)
        }
    }
}

struct ParsedDocument: Sendable, Equatable {
    let text: String
    let sections: [DocumentSection]
    let metadata: FileMetadata
    let contentHash: String

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var characterCount: Int {
        text.count
    }

    var estimatedTokenCount: Int {
        // Rough estimate: ~4 characters per token for English
        text.count / 4
    }
}

struct DocumentSection: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String?
    let content: String
    let pageNumber: Int?

    init(title: String? = nil, content: String, pageNumber: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.pageNumber = pageNumber
    }
}
