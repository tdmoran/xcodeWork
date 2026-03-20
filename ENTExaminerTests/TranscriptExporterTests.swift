import Testing
@testable import ENTExaminer

@Suite("TranscriptExporter")
struct TranscriptExporterTests {

    @Test("Dialogue summary exports as text with all sections")
    func exportDialogueAsText() {
        let summary = makeDialogueSummary()
        let text = TranscriptExporter.exportAsText(from: summary)
        #expect(text.contains("EXAMINATION TRANSCRIPT"))
        #expect(text.contains("Test Document"))
        #expect(text.contains("EXAMINER:"))
        #expect(text.contains("TRAINEE:"))
        #expect(text.contains("RESULTS"))
        #expect(text.contains("Overall Score:"))
    }

    @Test("Dialogue summary exports as markdown")
    func exportDialogueAsMarkdown() {
        let summary = makeDialogueSummary()
        let md = TranscriptExporter.exportAsMarkdown(from: summary)
        #expect(md.contains("# Examination Transcript"))
        #expect(md.contains("**Examiner**"))
        #expect(md.contains("**Trainee**"))
        #expect(md.contains("## Results"))
        #expect(md.contains("| Topic |"))
    }

    @Test("Exam summary exports as text")
    func exportExamAsText() {
        let summary = makeExamSummary()
        let text = TranscriptExporter.exportAsText(from: summary)
        #expect(text.contains("EXAMINATION TRANSCRIPT"))
        #expect(text.contains("EXAMINER:"))
        #expect(text.contains("TRAINEE:"))
    }

    @Test("Exam summary exports as markdown")
    func exportExamAsMarkdown() {
        let summary = makeExamSummary()
        let md = TranscriptExporter.exportAsMarkdown(from: summary)
        #expect(md.contains("# Examination Transcript"))
        #expect(md.contains("### Question 1"))
    }

    @Test("Topic scores appear in text export")
    func topicScoresInTextExport() {
        let summary = makeDialogueSummary()
        let text = TranscriptExporter.exportAsText(from: summary)
        #expect(text.contains("Anatomy"))
        #expect(text.contains("Topic Breakdown"))
    }

    @Test("Duration formatted correctly")
    func durationFormatted() {
        let summary = makeDialogueSummary()
        let text = TranscriptExporter.exportAsText(from: summary)
        #expect(text.contains("5m"))
    }

    // MARK: - Helpers

    func makeDialogueSummary() -> DialogueSummary {
        DialogueSummary(
            messages: [
                DialogueMessage(role: .examiner, content: "Tell me about the anatomy of the ear."),
                DialogueMessage(role: .trainee, content: "The ear has three parts: outer, middle, and inner ear."),
                DialogueMessage(role: .examiner, content: "Good. What structures are in the middle ear?"),
                DialogueMessage(role: .trainee, content: "The ossicles: malleus, incus, and stapes."),
            ],
            assessments: [],
            topicDiscussions: [],
            overallScore: 0.85,
            topicScores: [
                TopicScore(topicName: "Anatomy", mastery: 0.85, questionsAsked: 2, questionsCorrect: 2, trend: .improving)
            ],
            totalDuration: 300,
            documentTitle: "Test Document",
            modelUsed: .haiku
        )
    }

    func makeExamSummary() -> ExamSummary {
        let topic = ExamTopic(name: "Anatomy", importance: 0.9, keyConcepts: ["ear"], difficulty: .intermediate, subtopics: [])
        return ExamSummary(
            turns: [
                ExamTurn(
                    questionIndex: 0,
                    topic: topic,
                    question: "Describe the ear.",
                    userAnswer: "It has outer, middle, and inner parts.",
                    evaluation: TurnEvaluation(
                        correctnessScore: 0.8, completenessScore: 0.7, clarityScore: 0.9,
                        keyPointsCovered: ["outer"], keyPointsMissed: ["cochlea"],
                        feedback: "Good.", followUpSuggestion: .deeperOnSameTopic
                    )
                )
            ],
            overallScore: 0.8,
            topicScores: [TopicScore(topicName: "Anatomy", mastery: 0.8, questionsAsked: 1, questionsCorrect: 1, trend: .stable)],
            totalDuration: 180,
            documentTitle: "Test Document",
            modelUsed: .sonnet
        )
    }
}
