import Foundation

struct FlowController: Sendable {
    enum NextAction: Sendable, Equatable {
        case askQuestion(topic: ExamTopic, difficulty: ExamTopic.Difficulty, context: String)
        case clarifyMisunderstanding(topic: ExamTopic, misconception: String)
        case deeperDive(topic: ExamTopic, subtopic: String)
        case transitionTopic(from: ExamTopic, to: ExamTopic)
        case wrapUp
    }

    func decideNextAction(
        analysis: DocumentAnalysis,
        completedTurns: [ExamTurn],
        topicScores: [TopicScore],
        maxQuestions: Int
    ) -> NextAction {
        // Check if we've hit the question limit
        if completedTurns.count >= maxQuestions {
            return .wrapUp
        }

        // If no turns yet, start with the most important topic at foundational level
        guard let lastTurn = completedTurns.last else {
            let firstTopic = analysis.topics
                .sorted { $0.importance > $1.importance }
                .first ?? analysis.topics[0]
            return .askQuestion(
                topic: firstTopic,
                difficulty: .foundational,
                context: "This is the first question. Start with a broad, accessible question."
            )
        }

        let lastEval = lastTurn.evaluation
        let currentTopic = lastTurn.topic
        let currentTopicScore = topicScores.first(where: { $0.topicName == currentTopic.name })
        let mastery = currentTopicScore?.mastery ?? 0.5
        let questionsOnTopic = completedTurns.filter { $0.topic.name == currentTopic.name }.count

        // Handle the last evaluation's suggestion
        switch lastEval.followUpSuggestion {
        case .clarifyMisunderstanding:
            if let missed = lastEval.keyPointsMissed.first {
                return .clarifyMisunderstanding(topic: currentTopic, misconception: missed)
            }

        case .deeperOnSameTopic:
            if mastery > 0.6, let subtopic = currentTopic.subtopics.first(where: { sub in
                !completedTurns.contains { $0.question.localizedCaseInsensitiveContains(sub) }
            }) {
                return .deeperDive(topic: currentTopic, subtopic: subtopic)
            }

        case .congratulateAndAdvance, .moveToNextTopic:
            break // Fall through to topic transition logic
        }

        // Decide whether to stay on topic or move on
        let shouldMoveTopic = mastery > 0.8 || questionsOnTopic >= 3 || (mastery < 0.3 && questionsOnTopic >= 2)

        if shouldMoveTopic {
            // Find the next uncovered or weakest topic
            let coveredTopicNames = Set(completedTurns.map(\.topic.name))
            let uncoveredTopics = analysis.topics.filter { !coveredTopicNames.contains($0.name) }

            if let nextTopic = uncoveredTopics.sorted(by: { $0.importance > $1.importance }).first {
                return .transitionTopic(from: currentTopic, to: nextTopic)
            }

            // All topics covered — revisit the weakest
            if let weakest = topicScores.min(by: { $0.mastery < $1.mastery }),
               let topic = analysis.topics.first(where: { $0.name == weakest.topicName }),
               topic.name != currentTopic.name {
                return .transitionTopic(from: currentTopic, to: topic)
            }
        }

        // Continue on current topic with adaptive difficulty
        let difficulty: ExamTopic.Difficulty
        if mastery > 0.7 {
            difficulty = .advanced
        } else if mastery > 0.4 {
            difficulty = .intermediate
        } else {
            difficulty = .foundational
        }

        let context = questionsOnTopic > 0
            ? "Previous score on this topic: \(String(format: "%.0f%%", mastery * 100)). Probe a different angle."
            : "First question on this topic."

        return .askQuestion(topic: currentTopic, difficulty: difficulty, context: context)
    }
}
