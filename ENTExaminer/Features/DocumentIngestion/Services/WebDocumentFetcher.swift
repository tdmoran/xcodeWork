import Foundation
import CryptoKit
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "WebDocumentFetcher")

struct WebDocumentFetcher: Sendable {
    private static let timeoutSeconds: TimeInterval = 30
    private static let maxResponseBytes = 10 * 1_048_576 // 10 MB

    func fetch(urlString: String) async throws -> ParsedDocument {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw AppError.parseFailure("Invalid URL: \(urlString)")
        }

        let (data, response) = try await downloadPage(url: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.apiNetworkError("Unexpected response type from \(urlString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppError.apiNetworkError(
                "HTTP \(httpResponse.statusCode) from \(url.host ?? urlString)"
            )
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("text/html") || contentType.contains("text/plain") || contentType.isEmpty else {
            throw AppError.unsupportedFormat(
                "Expected HTML content but received '\(contentType)'"
            )
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .ascii) else {
            throw AppError.parseFailure("Could not decode web page text from \(urlString)")
        }

        let title = extractTitle(from: html) ?? url.host
        let bodyHTML = extractBody(from: html)
        let text = HTMLTextConverter.convert(bodyHTML)

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.documentEmpty
        }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sections = splitIntoParagraphSections(text: text)

        let metadata = FileMetadata(
            url: url,
            title: title,
            fileSize: Int64(data.count),
            pageCount: nil,
            format: .webURL
        )

        logger.info("Fetched web page: \(url.absoluteString) (\(data.count) bytes)")

        return ParsedDocument(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: sections,
            metadata: metadata,
            contentHash: hash
        )
    }

    private func downloadPage(url: URL) async throws -> (Data, URLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeoutSeconds
        config.timeoutIntervalForResource = Self.timeoutSeconds
        config.httpAdditionalHeaders = [
            "User-Agent": "ENTExaminer/1.0 (Document Fetcher)",
            "Accept": "text/html, text/plain;q=0.9, */*;q=0.1",
        ]

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(from: url)
            guard data.count <= Self.maxResponseBytes else {
                throw AppError.documentTooLarge(
                    sizeMB: Double(data.count) / 1_048_576.0,
                    limitMB: Double(Self.maxResponseBytes) / 1_048_576.0
                )
            }
            return (data, response)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.apiNetworkError(error.localizedDescription)
        }
    }

    private func extractTitle(from html: String) -> String? {
        guard let titleStart = html.range(of: "<title", options: .caseInsensitive),
              let tagClose = html.range(of: ">", range: titleStart.upperBound..<html.endIndex),
              let titleEnd = html.range(of: "</title>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) else {
            return nil
        }
        let raw = String(html[tagClose.upperBound..<titleEnd.lowerBound])
        return HTMLTextConverter.decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractBody(from html: String) -> String {
        // Try to extract just the <body> content
        if let bodyStart = html.range(of: "<body", options: .caseInsensitive),
           let tagClose = html.range(of: ">", range: bodyStart.upperBound..<html.endIndex),
           let bodyEnd = html.range(of: "</body>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) {
            return String(html[tagClose.upperBound..<bodyEnd.lowerBound])
        }
        return html
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

// MARK: - HTML to Text Converter

enum HTMLTextConverter {
    static func convert(_ html: String) -> String {
        var result = html

        // Remove script and style blocks entirely
        result = removeBlocks(from: result, tag: "script")
        result = removeBlocks(from: result, tag: "style")
        result = removeBlocks(from: result, tag: "nav")
        result = removeBlocks(from: result, tag: "footer")
        result = removeBlocks(from: result, tag: "header")

        // Convert block-level tags to paragraph breaks
        let blockTags = ["p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6",
                         "li", "tr", "blockquote", "article", "section"]
        for tag in blockTags {
            result = result.replacingOccurrences(
                of: "<\(tag)[^>]*>",
                with: "\n\n",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: "</\(tag)>",
                with: "\n\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Strip all remaining HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        result = decodeEntities(result)

        // Collapse whitespace within lines
        result = result.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )

        // Collapse multiple blank lines into double newlines
        result = result.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "\u{2013}"),
            ("&mdash;", "\u{2014}"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&hellip;", "\u{2026}"),
            ("&copy;", "\u{00A9}"),
            ("&reg;", "\u{00AE}"),
            ("&trade;", "\u{2122}"),
        ]

        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric entities like &#123; and &#x1A;
        result = decodeNumericEntities(result)

        return result
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        var result = text

        // Decimal: &#123;
        let decimalPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: decimalPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[codeRange]),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }

        // Hex: &#x1A;
        let hexPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[codeRange], radix: 16),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }

        return result
    }

    private static func removeBlocks(from html: String, tag: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
