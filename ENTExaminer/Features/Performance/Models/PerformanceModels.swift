import Foundation

struct PerformanceSnapshot: Sendable, Equatable {
    let overallScore: Double
    let confidence: Double
    let topicScores: [TopicScore]
    let turnScores: [TurnScore]
    let streak: Int
    let turnsCompleted: Int
    let turnsRemaining: Int

    static let empty = PerformanceSnapshot(
        overallScore: 0,
        confidence: 0,
        topicScores: [],
        turnScores: [],
        streak: 0,
        turnsCompleted: 0,
        turnsRemaining: 0
    )
}

struct TopicScore: Sendable, Equatable, Identifiable {
    let id: UUID
    let topicName: String
    let mastery: Double
    let questionsAsked: Int
    let questionsCorrect: Int
    let trend: Trend

    enum Trend: String, Sendable, Equatable {
        case improving
        case stable
        case declining
    }

    init(
        topicName: String,
        mastery: Double,
        questionsAsked: Int,
        questionsCorrect: Int,
        trend: Trend
    ) {
        self.id = UUID()
        self.topicName = topicName
        self.mastery = mastery
        self.questionsAsked = questionsAsked
        self.questionsCorrect = questionsCorrect
        self.trend = trend
    }
}

struct TurnScore: Sendable, Equatable, Identifiable {
    let id: UUID
    let questionIndex: Int
    let score: Double
    let topicName: String

    init(questionIndex: Int, score: Double, topicName: String) {
        self.id = UUID()
        self.questionIndex = questionIndex
        self.score = score
        self.topicName = topicName
    }
}

// MARK: - Performance Calculator

struct PerformanceCalculator: Sendable {
    private let alpha: Double = 0.4 // EMA weight for recent scores

    func computeSnapshot(
        turns: [ExamTurn],
        analysis: DocumentAnalysis,
        maxQuestions: Int
    ) -> PerformanceSnapshot {
        guard !turns.isEmpty else { return .empty }

        // Per-topic mastery via exponential moving average
        var topicMasteryMap: [String: (mastery: Double, asked: Int, correct: Int, scores: [Double])] = [:]

        for turn in turns {
            let topicName = turn.topic.name
            let score = turn.evaluation.compositeScore
            let existing = topicMasteryMap[topicName] ?? (mastery: 0, asked: 0, correct: 0, scores: [])

            let newMastery = alpha * score + (1 - alpha) * existing.mastery
            let newCorrect = existing.correct + (score >= 0.6 ? 1 : 0)

            topicMasteryMap[topicName] = (
                mastery: newMastery,
                asked: existing.asked + 1,
                correct: newCorrect,
                scores: existing.scores + [score]
            )
        }

        let topicScores = topicMasteryMap.map { name, data in
            let trend: TopicScore.Trend
            if data.scores.count < 2 {
                trend = .stable
            } else {
                let recent = data.scores.suffix(2)
                let diff = recent.last! - recent.first!
                if diff > 0.1 { trend = .improving }
                else if diff < -0.1 { trend = .declining }
                else { trend = .stable }
            }

            return TopicScore(
                topicName: name,
                mastery: data.mastery,
                questionsAsked: data.asked,
                questionsCorrect: data.correct,
                trend: trend
            )
        }

        // Overall score weighted by topic importance
        let weightedSum = topicScores.reduce(0.0) { sum, topicScore in
            let importance = analysis.topics.first(where: { $0.name == topicScore.topicName })?.importance ?? 0.5
            return sum + topicScore.mastery * importance
        }
        let totalWeight = topicScores.reduce(0.0) { sum, topicScore in
            let importance = analysis.topics.first(where: { $0.name == topicScore.topicName })?.importance ?? 0.5
            return sum + importance
        }
        let overallScore = totalWeight > 0 ? weightedSum / totalWeight : 0

        // Confidence based on recent trend
        let recentScores = turns.suffix(5).map(\.evaluation.compositeScore)
        let confidence = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / Double(recentScores.count)

        // Streak
        var streak = 0
        for turn in turns.reversed() {
            if turn.evaluation.compositeScore >= 0.7 {
                streak += 1
            } else {
                break
            }
        }

        // Turn scores for timeline
        let turnScores = turns.enumerated().map { index, turn in
            TurnScore(
                questionIndex: index + 1,
                score: turn.evaluation.compositeScore,
                topicName: turn.topic.name
            )
        }

        return PerformanceSnapshot(
            overallScore: overallScore,
            confidence: confidence,
            topicScores: topicScores,
            turnScores: turnScores,
            streak: streak,
            turnsCompleted: turns.count,
            turnsRemaining: max(0, maxQuestions - turns.count)
        )
    }
}
