import Foundation

/// A document in the user's library that can be examined on.
struct LibraryDocument: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let sourceFileName: String
    let format: DocumentFormat
    let fileSize: Int64
    let pageCount: Int?
    let tags: [String]
    let addedDate: Date
    let isPreloaded: Bool

    /// Whether this document has been archived (offloaded from active library).
    var isArchived: Bool

    /// Date of most recent examination on this document.
    var lastExaminedDate: Date?

    /// Number of times examined.
    var examCount: Int

    /// Brief content preview (first ~500 chars).
    var contentPreview: String

    init(
        id: UUID = UUID(),
        title: String,
        sourceFileName: String,
        format: DocumentFormat,
        fileSize: Int64,
        pageCount: Int? = nil,
        tags: [String] = [],
        addedDate: Date = Date(),
        isPreloaded: Bool = false,
        isArchived: Bool = false,
        lastExaminedDate: Date? = nil,
        examCount: Int = 0,
        contentPreview: String = ""
    ) {
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.format = format
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.tags = tags
        self.addedDate = addedDate
        self.isPreloaded = isPreloaded
        self.isArchived = isArchived
        self.lastExaminedDate = lastExaminedDate
        self.examCount = examCount
        self.contentPreview = contentPreview
    }

    /// Returns a new document with updated exam history.
    func withExamRecorded() -> LibraryDocument {
        LibraryDocument(
            id: id,
            title: title,
            sourceFileName: sourceFileName,
            format: format,
            fileSize: fileSize,
            pageCount: pageCount,
            tags: tags,
            addedDate: addedDate,
            isPreloaded: isPreloaded,
            isArchived: isArchived,
            lastExaminedDate: Date(),
            examCount: examCount + 1,
            contentPreview: contentPreview
        )
    }

    /// Returns a new document with archive status toggled.
    func withArchiveStatus(_ archived: Bool) -> LibraryDocument {
        LibraryDocument(
            id: id,
            title: title,
            sourceFileName: sourceFileName,
            format: format,
            fileSize: fileSize,
            pageCount: pageCount,
            tags: tags,
            addedDate: addedDate,
            isPreloaded: isPreloaded,
            isArchived: archived,
            lastExaminedDate: lastExaminedDate,
            examCount: examCount,
            contentPreview: contentPreview
        )
    }

    var fileSizeFormatted: String {
        let mb = Double(fileSize) / 1_048_576.0
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(fileSize) / 1024.0
            return String(format: "%.0f KB", kb)
        }
    }

    var formatIcon: String {
        switch format {
        case .pdf: return "doc.richtext.fill"
        case .docx: return "doc.fill"
        case .plainText: return "doc.text.fill"
        case .markdown: return "doc.text.fill"
        case .image: return "photo.fill"
        case .webURL: return "globe"
        }
    }
}

/// Metadata for an exam session stored in the library.
struct ExamSessionRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let documentId: UUID
    let date: Date
    let duration: TimeInterval
    let overallScore: Double
    let topicsCovered: [String]
    let modelUsed: String
}
