import XCTest
@testable import ENTExaminer

final class PerformanceCalculatorTests: XCTestCase {
    private let calculator = PerformanceCalculator()

    private let sampleAnalysis = DocumentAnalysis(
        topics: [
            ExamTopic(name: "Topic A", importance: 0.8, keyConcepts: ["a1"], difficulty: .intermediate, subtopics: []),
            ExamTopic(name: "Topic B", importance: 0.6, keyConcepts: ["b1"], difficulty: .foundational, subtopics: []),
        ],
        documentSummary: "Test document",
        suggestedQuestionCount: 5,
        estimatedDurationMinutes: 10,
        difficultyAssessment: "intermediate"
    )

    func testEmptyTurnsReturnsEmptySnapshot() {
        let snapshot = calculator.computeSnapshot(turns: [], analysis: sampleAnalysis, maxQuestions: 10)
        XCTAssertEqual(snapshot, .empty)
    }

    func testSingleTurnComputesScore() {
        let turn = ExamTurn(
            questionIndex: 0,
            topic: sampleAnalysis.topics[0],
            question: "What is A?",
            userAnswer: "A is...",
            evaluation: TurnEvaluation(
                correctnessScore: 0.8,
                completenessScore: 0.6,
                clarityScore: 1.0,
                keyPointsCovered: ["a1"],
                keyPointsMissed: [],
                feedback: "Good",
                followUpSuggestion: .moveToNextTopic
            )
        )

        let snapshot = calculator.computeSnapshot(turns: [turn], analysis: sampleAnalysis, maxQuestions: 5)

        XCTAssertGreaterThan(snapshot.overallScore, 0)
        XCTAssertEqual(snapshot.turnsCompleted, 1)
        XCTAssertEqual(snapshot.turnsRemaining, 4)
        XCTAssertEqual(snapshot.topicScores.count, 1)
        XCTAssertEqual(snapshot.turnScores.count, 1)
    }

    func testStreakCountsConsecutiveGoodAnswers() {
        let goodTurn = { (index: Int) in
            ExamTurn(
                questionIndex: index,
                topic: self.sampleAnalysis.topics[0],
                question: "Q\(index)",
                userAnswer: "A",
                evaluation: TurnEvaluation(
                    correctnessScore: 0.9,
                    completenessScore: 0.8,
                    clarityScore: 0.9,
                    keyPointsCovered: [],
                    keyPointsMissed: [],
                    feedback: "Great",
                    followUpSuggestion: .moveToNextTopic
                )
            )
        }

        let turns = [goodTurn(0), goodTurn(1), goodTurn(2)]
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 10)

        XCTAssertEqual(snapshot.streak, 3)
    }

    func testStreakBreaksOnLowScore() {
        let makeTurn = { (index: Int, score: Double) in
            ExamTurn(
                questionIndex: index,
                topic: self.sampleAnalysis.topics[0],
                question: "Q\(index)",
                userAnswer: "A",
                evaluation: TurnEvaluation(
                    correctnessScore: score,
                    completenessScore: score,
                    clarityScore: score,
                    keyPointsCovered: [],
                    keyPointsMissed: [],
                    feedback: "",
                    followUpSuggestion: .moveToNextTopic
                )
            )
        }

        let turns = [makeTurn(0, 0.9), makeTurn(1, 0.3), makeTurn(2, 0.9)]
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 10)

        XCTAssertEqual(snapshot.streak, 1) // Only the last one counts
    }
}
