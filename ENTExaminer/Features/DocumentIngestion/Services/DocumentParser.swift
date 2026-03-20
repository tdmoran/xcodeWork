import Foundation
import PDFKit
import Vision
import OSLog
import CryptoKit

private let logger = Logger(subsystem: "com.entexaminer", category: "DocumentParser")

protocol DocumentParserProtocol: Sendable {
    func canParse(format: DocumentFormat) -> Bool
    func parse(url: URL) async throws -> ParsedDocument
}

// MARK: - PDF Parser

struct PDFParserService: DocumentParserProtocol {
    func canParse(format: DocumentFormat) -> Bool {
        format == .pdf
    }

    func parse(url: URL) async throws -> ParsedDocument {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw AppError.parseFailure("Could not open PDF file")
        }

        var allText = ""
        var sections: [DocumentSection] = []

        // Limit pages to avoid exceeding context windows
        let maxPages = min(pdfDocument.pageCount, 100)
        logger.info("Parsing PDF: \(pdfDocument.pageCount) pages (processing first \(maxPages))")

        for pageIndex in 0..<maxPages {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageText = page.string ?? ""
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.count > 10 {
                sections.append(DocumentSection(
                    title: "Page \(pageIndex + 1)",
                    content: trimmed,
                    pageNumber: pageIndex + 1
                ))
                allText += trimmed + "\n\n"
            } else {
                // Scanned page or very little text — try OCR
                do {
                    let ocrText = try await ocrPage(page)
                    let ocrTrimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if ocrTrimmed.count > 10 {
                        sections.append(DocumentSection(
                            title: "Page \(pageIndex + 1) (OCR)",
                            content: ocrTrimmed,
                            pageNumber: pageIndex + 1
                        ))
                        allText += ocrTrimmed + "\n\n"
                    }
                } catch {
                    logger.warning("OCR failed for page \(pageIndex + 1): \(error.localizedDescription)")
                }
            }
        }

        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let metadata = FileMetadata(
            url: url,
            title: pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            fileSize: Int64(data.count),
            pageCount: pdfDocument.pageCount,
            format: .pdf
        )

        let doc = ParsedDocument(text: allText.trimmingCharacters(in: .whitespacesAndNewlines), sections: sections, metadata: metadata, contentHash: hash)

        guard !doc.isEmpty else { throw AppError.documentEmpty }
        return doc
    }

    private func ocrPage(_ page: PDFPage) async throws -> String {
        let pageImage = page.thumbnail(of: CGSize(width: 2048, height: 2048), for: .mediaBox)

        guard let cgImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Plain Text Parser

struct PlainTextParserService: DocumentParserProtocol {
    func canParse(format: DocumentFormat) -> Bool {
        format == .plainText || format == .markdown
    }

    func parse(url: URL) async throws -> ParsedDocument {
        let data = try Data(contentsOf: url)

        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .ascii) else {
            throw AppError.parseFailure("Could not decode text file")
        }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let format = DocumentFormat.detect(from: url) ?? .plainText

        let sections = splitIntoSections(text: text)

        let metadata = FileMetadata(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            fileSize: Int64(data.count),
            pageCount: nil,
            format: format
        )

        let doc = ParsedDocument(text: text, sections: sections, metadata: metadata, contentHash: hash)
        guard !doc.isEmpty else { throw AppError.documentEmpty }
        return doc
    }

    private func splitIntoSections(text: String) -> [DocumentSection] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [DocumentSection] = []
        var currentTitle: String?
        var currentContent = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect headings (Markdown # or all-caps lines)
            let isHeading = trimmed.hasPrefix("#")
                || (trimmed.count > 3 && trimmed.count < 100 && trimmed == trimmed.uppercased() && trimmed.rangeOfCharacter(from: .letters) != nil)

            if isHeading && !currentContent.isEmpty {
                sections.append(DocumentSection(title: currentTitle, content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines)))
                currentContent = ""
            }

            if isHeading {
                currentTitle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            } else {
                currentContent += line + "\n"
            }
        }

        if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(DocumentSection(title: currentTitle, content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return sections
    }
}

// MARK: - Image OCR Parser

struct ImageOCRParserService: DocumentParserProtocol {
    func canParse(format: DocumentFormat) -> Bool {
        format == .image
    }

    func parse(url: URL) async throws -> ParsedDocument {
        let data = try Data(contentsOf: url)

        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AppError.parseFailure("Could not load image")
        }

        let text = try await recognizeText(in: cgImage)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let metadata = FileMetadata(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            fileSize: Int64(data.count),
            pageCount: 1,
            format: .image
        )

        let doc = ParsedDocument(
            text: text,
            sections: [DocumentSection(content: text, pageNumber: 1)],
            metadata: metadata,
            contentHash: hash
        )

        guard !doc.isEmpty else { throw AppError.documentEmpty }
        return doc
    }

    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - DOCX Parser

struct DocxParserService: DocumentParserProtocol {
    func canParse(format: DocumentFormat) -> Bool {
        format == .docx
    }

    func parse(url: URL) async throws -> ParsedDocument {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx_\(UUID().uuidString)")

        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let extractedXML = try extractDocumentXML(from: url, to: tempDir)
        let text = try parseWordXML(at: extractedXML)

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.documentEmpty
        }

        let sections = splitIntoParagraphSections(text: text)

        let metadata = FileMetadata(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            fileSize: Int64(data.count),
            pageCount: nil,
            format: .docx
        )

        return ParsedDocument(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: sections,
            metadata: metadata,
            contentHash: hash
        )
    }

    private func extractDocumentXML(from docxURL: URL, to tempDir: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", docxURL.path, "word/document.xml", "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppError.parseFailure("Failed to extract DOCX contents (unzip exit code \(process.terminationStatus))")
        }

        let xmlPath = tempDir.appendingPathComponent("word/document.xml")
        guard FileManager.default.fileExists(atPath: xmlPath.path) else {
            throw AppError.parseFailure("DOCX file does not contain word/document.xml")
        }

        return xmlPath
    }

    private func parseWordXML(at xmlURL: URL) throws -> String {
        let data = try Data(contentsOf: xmlURL)
        let delegate = WordXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown XML parse error"
            throw AppError.parseFailure("Failed to parse DOCX XML: \(errorDesc)")
        }

        return delegate.extractedText
    }

    private func splitIntoParagraphSections(text: String) -> [DocumentSection] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var sections: [DocumentSection] = []
        var sectionIndex = 1

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            sections.append(DocumentSection(
                title: "Section \(sectionIndex)",
                content: trimmed
            ))
            sectionIndex += 1
        }

        return sections
    }
}

// MARK: - Word XML Parser Delegate

private final class WordXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var extractedText = ""
    private var isInsideTextElement = false
    private var currentParagraphText = ""
    private var isNewParagraph = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        // <w:t> elements contain the actual text runs
        if elementName == "w:t" {
            isInsideTextElement = true
        }
        // <w:p> marks a new paragraph
        if elementName == "w:p" {
            isNewParagraph = true
            currentParagraphText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTextElement {
            currentParagraphText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "w:t" {
            isInsideTextElement = false
        }
        if elementName == "w:p" {
            let trimmed = currentParagraphText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !extractedText.isEmpty {
                    extractedText += "\n\n"
                }
                extractedText += trimmed
            }
            isNewParagraph = false
            currentParagraphText = ""
        }
    }
}

// MARK: - Composite Parser

struct CompositeDocumentParser: DocumentParserProtocol {
    private let parsers: [any DocumentParserProtocol]

    init() {
        self.parsers = [
            PDFParserService(),
            DocxParserService(),
            PlainTextParserService(),
            ImageOCRParserService(),
        ]
    }

    func canParse(format: DocumentFormat) -> Bool {
        parsers.contains { $0.canParse(format: format) }
    }

    func parse(url: URL) async throws -> ParsedDocument {
        guard let format = DocumentFormat.detect(from: url) else {
            throw AppError.unsupportedFormat(url.pathExtension)
        }

        guard let parser = parsers.first(where: { $0.canParse(format: format) }) else {
            throw AppError.unsupportedFormat(format.displayName)
        }

        logger.info("Parsing \(url.lastPathComponent) as \(format.displayName)")
        return try await parser.parse(url: url)
    }
}
