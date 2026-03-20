import Foundation

// MARK: - Transcript Export Errors

enum TranscriptExportError: Error, LocalizedError {
    case directoryCreationFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let detail):
            return "Failed to create export directory: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write transcript file: \(detail)"
        }
    }
}

// MARK: - Transcript Exporter

struct TranscriptExporter {

    // MARK: - Plain Text from DialogueSummary

    static func exportAsText(from summary: DialogueSummary) -> String {
        var lines: [String] = []

        lines.append(textHeader(
            documentTitle: summary.documentTitle,
            date: Date(),
            duration: summary.totalDuration,
            model: summary.modelUsed.displayName
        ))

        lines.append("TRANSCRIPT")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for message in summary.messages {
            let label = message.role == .examiner ? "EXAMINER" : "TRAINEE"
            lines.append("\(label): \(message.content)")
            lines.append("")
        }

        lines.append(String(repeating: "-", count: 60))
        lines.append("")
        lines.append(textFooter(
            overallScore: summary.overallScore,
            topicScores: summary.topicScores
        ))

        return lines.joined(separator: "\n")
    }

    // MARK: - Plain Text from ExamSummary

    static func exportAsText(from summary: ExamSummary) -> String {
        var lines: [String] = []

        lines.append(textHeader(
            documentTitle: summary.documentTitle,
            date: Date(),
            duration: summary.totalDuration,
            model: summary.modelUsed.displayName
        ))

        lines.append("TRANSCRIPT")
        lines.append(String(repeating: "-", count: 60))
        lines.append("")

        for turn in summary.turns {
            lines.append("EXAMINER: \(turn.question)")
            lines.append("")
            lines.append("TRAINEE: \(turn.userAnswer)")
            lines.append("")
        }

        lines.append(String(repeating: "-", count: 60))
        lines.append("")
        lines.append(textFooter(
            overallScore: summary.overallScore,
            topicScores: summary.topicScores
        ))

        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown from DialogueSummary

    static func exportAsMarkdown(from summary: DialogueSummary) -> String {
        var lines: [String] = []

        lines.append(markdownHeader(
            documentTitle: summary.documentTitle,
            date: Date(),
            duration: summary.totalDuration,
            model: summary.modelUsed.displayName
        ))

        lines.append("## Transcript")
        lines.append("")

        for message in summary.messages {
            let label = message.role == .examiner ? "**Examiner**" : "**Trainee**"
            lines.append("\(label): \(message.content)")
            lines.append("")
        }

        lines.append(markdownAssessment(
            overallScore: summary.overallScore,
            topicScores: summary.topicScores
        ))

        if !summary.assessments.isEmpty {
            lines.append("## Detailed Assessments")
            lines.append("")
            for assessment in summary.assessments {
                lines.append("- **\(assessment.topicName)**: ")
                lines.append("  Understanding: \(formatPercent(assessment.understanding)), ")
                lines.append("  Confidence: \(formatPercent(assessment.confidence))")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown from ExamSummary

    static func exportAsMarkdown(from summary: ExamSummary) -> String {
        var lines: [String] = []

        lines.append(markdownHeader(
            documentTitle: summary.documentTitle,
            date: Date(),
            duration: summary.totalDuration,
            model: summary.modelUsed.displayName
        ))

        lines.append("## Transcript")
        lines.append("")

        for (index, turn) in summary.turns.enumerated() {
            lines.append("### Question \(index + 1): \(turn.topic.name)")
            lines.append("")
            lines.append("**Examiner**: \(turn.question)")
            lines.append("")
            lines.append("**Trainee**: \(turn.userAnswer)")
            lines.append("")
            lines.append("*Score: \(formatPercent(turn.evaluation.compositeScore))*")
            lines.append("")
        }

        lines.append(markdownAssessment(
            overallScore: summary.overallScore,
            topicScores: summary.topicScores
        ))

        return lines.joined(separator: "\n")
    }

    // MARK: - File Export

    static func saveToFile(content: String, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: documentsDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw TranscriptExportError.directoryCreationFailed(error.localizedDescription)
            }
        }

        let fileURL = documentsDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw TranscriptExportError.writeFailed(error.localizedDescription)
        }

        return fileURL
    }

    // MARK: - Private Helpers

    private static func textHeader(
        documentTitle: String,
        date: Date,
        duration: TimeInterval,
        model: String
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("EXAMINATION TRANSCRIPT")
        lines.append(String(repeating: "=", count: 60))
        lines.append("Document: \(documentTitle)")
        lines.append("Date: \(dateFormatter.string(from: date))")
        lines.append("Duration: \(formatDuration(duration))")
        lines.append("Model: \(model)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func textFooter(
        overallScore: Double,
        topicScores: [TopicScore]
    ) -> String {
        var lines: [String] = []
        lines.append("RESULTS")
        lines.append(String(repeating: "=", count: 60))
        lines.append("Overall Score: \(formatPercent(overallScore))")
        lines.append("")

        if !topicScores.isEmpty {
            lines.append("Topic Breakdown:")
            for score in topicScores {
                let trendSymbol: String
                switch score.trend {
                case .improving: trendSymbol = "[UP]"
                case .stable: trendSymbol = "[--]"
                case .declining: trendSymbol = "[DN]"
                }
                lines.append("  \(score.topicName): \(formatPercent(score.mastery)) "
                    + "(\(score.questionsCorrect)/\(score.questionsAsked)) \(trendSymbol)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func markdownHeader(
        documentTitle: String,
        date: Date,
        duration: TimeInterval,
        model: String
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("# Examination Transcript")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|-------|-------|")
        lines.append("| **Document** | \(documentTitle) |")
        lines.append("| **Date** | \(dateFormatter.string(from: date)) |")
        lines.append("| **Duration** | \(formatDuration(duration)) |")
        lines.append("| **Model** | \(model) |")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func markdownAssessment(
        overallScore: Double,
        topicScores: [TopicScore]
    ) -> String {
        var lines: [String] = []
        lines.append("## Results")
        lines.append("")
        lines.append("**Overall Score: \(formatPercent(overallScore))**")
        lines.append("")

        if !topicScores.isEmpty {
            lines.append("### Topic Scores")
            lines.append("")
            lines.append("| Topic | Mastery | Correct | Trend |")
            lines.append("|-------|---------|---------|-------|")
            for score in topicScores {
                let trendEmoji: String
                switch score.trend {
                case .improving: trendEmoji = "Improving"
                case .stable: trendEmoji = "Stable"
                case .declining: trendEmoji = "Declining"
                }
                lines.append("| \(score.topicName) "
                    + "| \(formatPercent(score.mastery)) "
                    + "| \(score.questionsCorrect)/\(score.questionsAsked) "
                    + "| \(trendEmoji) |")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatPercent(_ value: Double) -> String {
        let percentage = (value * 100).rounded()
        return "\(Int(percentage))%"
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
