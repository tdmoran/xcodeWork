import XCTest
@testable import ENTExaminer

final class PerformanceCalculatorTests: XCTestCase {
    let calculator = PerformanceCalculator()

    let sampleAnalysis = DocumentAnalysis(
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
        let turn = makeTurn(index: 0, topicIndex: 0, correctness: 0.8, completeness: 0.6, clarity: 1.0)
        let snapshot = calculator.computeSnapshot(turns: [turn], analysis: sampleAnalysis, maxQuestions: 5)
        XCTAssertGreaterThan(snapshot.overallScore, 0)
        XCTAssertEqual(snapshot.turnsCompleted, 1)
        XCTAssertEqual(snapshot.turnsRemaining, 4)
        XCTAssertEqual(snapshot.topicScores.count, 1)
        XCTAssertEqual(snapshot.turnScores.count, 1)
    }

    func testCompositeScoreFormula() {
        let eval = TurnEvaluation(
            correctnessScore: 1.0,
            completenessScore: 0.5,
            clarityScore: 0.0,
            keyPointsCovered: [],
            keyPointsMissed: [],
            feedback: "",
            followUpSuggestion: .moveToNextTopic
        )
        XCTAssertEqual(eval.compositeScore, 0.65, accuracy: 0.001)
    }

    func testStreakCountsConsecutiveGoodAnswers() {
        let turns = (0..<3).map { makeTurn(index: $0, topicIndex: 0, score: 0.9) }
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 10)
        XCTAssertEqual(snapshot.streak, 3)
    }

    func testStreakBreaksOnLowScore() {
        let turns = [
            makeTurn(index: 0, topicIndex: 0, score: 0.9),
            makeTurn(index: 1, topicIndex: 0, score: 0.3),
            makeTurn(index: 2, topicIndex: 0, score: 0.9),
        ]
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 10)
        XCTAssertEqual(snapshot.streak, 1)
    }

    func testRemainingTurnsCalculation() {
        let turns = [
            makeTurn(index: 0, topicIndex: 0, score: 0.7),
            makeTurn(index: 1, topicIndex: 0, score: 0.7),
        ]
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 8)
        XCTAssertEqual(snapshot.turnsCompleted, 2)
        XCTAssertEqual(snapshot.turnsRemaining, 6)
    }

    func testMultipleTopicsTracked() {
        let turns = [
            makeTurn(index: 0, topicIndex: 0, score: 0.9),
            makeTurn(index: 1, topicIndex: 1, score: 0.5),
        ]
        let snapshot = calculator.computeSnapshot(turns: turns, analysis: sampleAnalysis, maxQuestions: 10)
        XCTAssertEqual(snapshot.topicScores.count, 2)

        let topicA = snapshot.topicScores.first(where: { $0.topicName == "Topic A" })
        let topicB = snapshot.topicScores.first(where: { $0.topicName == "Topic B" })
        XCTAssertNotNil(topicA)
        XCTAssertNotNil(topicB)
        XCTAssertGreaterThan(topicA!.mastery, topicB!.mastery)
    }

    // MARK: - Helpers

    func makeTurn(index: Int, topicIndex: Int, score: Double) -> ExamTurn {
        makeTurn(index: index, topicIndex: topicIndex, correctness: score, completeness: score, clarity: score)
    }

    func makeTurn(index: Int, topicIndex: Int, correctness: Double, completeness: Double, clarity: Double) -> ExamTurn {
        ExamTurn(
            questionIndex: index,
            topic: sampleAnalysis.topics[topicIndex],
            question: "Q\(index)",
            userAnswer: "A",
            evaluation: TurnEvaluation(
                correctnessScore: correctness,
                completenessScore: completeness,
                clarityScore: clarity,
                keyPointsCovered: [],
                keyPointsMissed: [],
                feedback: "",
                followUpSuggestion: .moveToNextTopic
            )
        )
    }
}
