import XCTest
@testable import ENTExaminer

final class FlowControllerTests: XCTestCase {
    private let flowController = FlowController()

    private let sampleAnalysis = DocumentAnalysis(
        topics: [
            ExamTopic(name: "Photosynthesis", importance: 0.9, keyConcepts: ["chlorophyll", "light reactions"], difficulty: .intermediate, subtopics: ["Calvin cycle", "Electron transport"]),
            ExamTopic(name: "Cell Respiration", importance: 0.8, keyConcepts: ["mitochondria", "ATP"], difficulty: .intermediate, subtopics: ["Glycolysis", "Krebs cycle"]),
            ExamTopic(name: "DNA Replication", importance: 0.7, keyConcepts: ["helicase", "polymerase"], difficulty: .advanced, subtopics: ["Leading strand", "Lagging strand"]),
        ],
        documentSummary: "A biology textbook chapter on cellular processes.",
        suggestedQuestionCount: 10,
        estimatedDurationMinutes: 15,
        difficultyAssessment: "intermediate"
    )

    func testFirstQuestionStartsWithMostImportantTopic() {
        let action = flowController.decideNextAction(
            analysis: sampleAnalysis,
            completedTurns: [],
            topicScores: [],
            maxQuestions: 10
        )

        if case .askQuestion(let topic, let difficulty, _) = action {
            XCTAssertEqual(topic.name, "Photosynthesis")
            XCTAssertEqual(difficulty, .foundational)
        } else {
            XCTFail("Expected askQuestion, got \(action)")
        }
    }

    func testWrapsUpAtMaxQuestions() {
        let turns = (0..<10).map { index in
            ExamTurn(
                questionIndex: index,
                topic: sampleAnalysis.topics[0],
                question: "Question \(index)",
                userAnswer: "Answer \(index)",
                evaluation: TurnEvaluation(
                    correctnessScore: 0.8,
                    completenessScore: 0.7,
                    clarityScore: 0.9,
                    keyPointsCovered: ["point"],
                    keyPointsMissed: [],
                    feedback: "Good",
                    followUpSuggestion: .moveToNextTopic
                )
            )
        }

        let action = flowController.decideNextAction(
            analysis: sampleAnalysis,
            completedTurns: turns,
            topicScores: [],
            maxQuestions: 10
        )

        XCTAssertEqual(action, .wrapUp)
    }

    func testMovesToNextTopicAfterHighMastery() {
        let turns = [
            makeTurn(index: 0, topic: sampleAnalysis.topics[0], score: 0.9),
            makeTurn(index: 1, topic: sampleAnalysis.topics[0], score: 0.9),
            makeTurn(index: 2, topic: sampleAnalysis.topics[0], score: 0.95),
        ]

        let topicScores = [
            TopicScore(topicName: "Photosynthesis", mastery: 0.9, questionsAsked: 3, questionsCorrect: 3, trend: .stable)
        ]

        let action = flowController.decideNextAction(
            analysis: sampleAnalysis,
            completedTurns: turns,
            topicScores: topicScores,
            maxQuestions: 10
        )

        if case .transitionTopic(let from, let to) = action {
            XCTAssertEqual(from.name, "Photosynthesis")
            XCTAssertEqual(to.name, "Cell Respiration")
        } else {
            XCTFail("Expected transitionTopic, got \(action)")
        }
    }

    // MARK: - Helpers

    private func makeTurn(index: Int, topic: ExamTopic, score: Double) -> ExamTurn {
        ExamTurn(
            questionIndex: index,
            topic: topic,
            question: "Question \(index)",
            userAnswer: "Answer",
            evaluation: TurnEvaluation(
                correctnessScore: score,
                completenessScore: score,
                clarityScore: score,
                keyPointsCovered: [],
                keyPointsMissed: [],
                feedback: "OK",
                followUpSuggestion: .moveToNextTopic
            )
        )
    }
}
