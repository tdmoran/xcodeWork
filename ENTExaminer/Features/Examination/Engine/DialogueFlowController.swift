import Foundation

/// Decides what the examiner should do next in a Socratic dialogue.
///
/// Unlike `FlowController` which decides the next *question*, this controller
/// decides the next *conversational move* — acknowledge, probe, redirect, scaffold, etc.
/// It models how an expert examiner naturally guides a conversation.
struct DialogueFlowController: Sendable {

    /// The examiner's next conversational move.
    struct NextMove: Sendable, Equatable {
        let intent: ExaminerIntent
        let promptGuidance: String
    }

    // MARK: - Public

    func decideNextMove(
        analysis: DocumentAnalysis,
        messages: [DialogueMessage],
        context: ConversationContext,
        assessments: [InlineAssessment]
    ) -> NextMove {
        // No messages yet — open the conversation
        guard !messages.isEmpty else {
            return openingMove(analysis: analysis)
        }

        // Check if we should wrap up
        if shouldWrapUp(context: context, analysis: analysis) {
            return closingMove(context: context)
        }

        // Analyze the trainee's last response
        let lastTraineeMessage = messages.last { $0.role == .trainee }
        let lastAssessment = assessments.last

        // Handle "I don't know" or very short responses
        if let traineeText = lastTraineeMessage?.content, isStrugglingResponse(traineeText) {
            return scaffoldingMove(context: context, analysis: analysis)
        }

        // Check if we should stay on topic or transition
        if shouldTransition(context: context, assessments: assessments, analysis: analysis) {
            return transitionMove(context: context, analysis: analysis)
        }

        // Default: follow up naturally based on what was just said
        return followUpMove(
            context: context,
            lastAssessment: lastAssessment,
            analysis: analysis
        )
    }

    // MARK: - Opening

    private func openingMove(analysis: DocumentAnalysis) -> NextMove {
        guard let firstTopic = analysis.topics.max(by: { $0.importance < $1.importance }) else {
            return NextMove(
                intent: .closing,
                promptGuidance: "No topics available to discuss. Politely explain that the document didn't contain enough material for a discussion."
            )
        }

        return NextMove(
            intent: .openTopic(firstTopic),
            promptGuidance: """
                Open the conversation naturally. You're a senior consultant about to discuss \
                "\(firstTopic.name)" with a trainee. Don't jump straight into a question — \
                set the scene briefly, perhaps with a clinical scenario or case, then invite \
                the trainee to share their thoughts. Keep it warm and collegial.

                Topic: \(firstTopic.name)
                Key concepts: \(firstTopic.keyConcepts.joined(separator: ", "))
                """
        )
    }

    // MARK: - Follow-Up

    private func followUpMove(
        context: ConversationContext,
        lastAssessment: InlineAssessment?,
        analysis: DocumentAnalysis
    ) -> NextMove {
        guard let assessment = lastAssessment else {
            return probeMove(context: context)
        }

        // Strong understanding — push deeper
        if assessment.understanding > 0.7 {
            return deeperProbeMove(context: context, assessment: assessment, analysis: analysis)
        }

        // Partial understanding — probe the gaps
        let partialSignals = assessment.signals.filter { $0.type == .partial }
        if let gap = partialSignals.first {
            return NextMove(
                intent: .followUp(aspect: gap.concept),
                promptGuidance: """
                    The trainee showed partial understanding of "\(gap.concept)" — \
                    they mentioned some aspects but missed: \(gap.detail). \
                    Don't tell them what they missed directly. Instead, ask a follow-up \
                    that naturally leads them to think about the missing aspect. \
                    Use phrases like "And what about..." or "How does that relate to..."
                    """
            )
        }

        // Misconception detected — gently correct
        let misconceptions = assessment.signals.filter { $0.type == .misconception }
        if let misconception = misconceptions.first {
            return NextMove(
                intent: .clarify(misconception: misconception.detail),
                promptGuidance: """
                    The trainee seems to have a misconception about "\(misconception.concept)": \
                    \(misconception.detail). Don't bluntly correct them. Instead, present a \
                    scenario or ask a question that exposes the contradiction. Something like \
                    "That's interesting — but what would happen if..." or "I see what you mean, \
                    but consider this case..."
                    """
            )
        }

        return probeMove(context: context)
    }

    private func probeMove(context: ConversationContext) -> NextMove {
        let topicName = context.currentTopic?.name ?? "the current topic"
        return NextMove(
            intent: .followUp(aspect: topicName),
            promptGuidance: """
                Continue the conversation naturally. Acknowledge what the trainee said, \
                then ask a follow-up that probes their understanding from a different angle. \
                Use their own words where possible — "You mentioned X, can you tell me more \
                about how that works?" or "Good point about X — what would you do differently if...?"
                """
        )
    }

    private func deeperProbeMove(
        context: ConversationContext,
        assessment: InlineAssessment,
        analysis: DocumentAnalysis
    ) -> NextMove {
        guard let topic = context.currentTopic else {
            return probeMove(context: context)
        }

        // Find an uncovered subtopic
        let discussedConcepts = Set(assessment.signals.map(\.concept))
        let uncovered = topic.keyConcepts.first { !discussedConcepts.contains($0) }

        if let concept = uncovered {
            return NextMove(
                intent: .followUp(aspect: concept),
                promptGuidance: """
                    The trainee is doing well — push them harder. They haven't discussed \
                    "\(concept)" yet. Connect it naturally to what they just said. \
                    "That's exactly right. Now, thinking about \(concept), how would that \
                    change your approach?" or "Excellent. Let's take it further — tell me \
                    about \(concept) in this context."
                    """
            )
        }

        // All concepts covered on this topic — synthesize
        let connections = assessment.signals.filter { $0.type == .connection }
        if connections.count < 2 {
            return NextMove(
                intent: .synthesize(topics: [topic.name]),
                promptGuidance: """
                    The trainee has covered the key concepts well. Ask them to synthesize — \
                    "So pulling all that together, if you had a patient presenting with... \
                    how would you approach it?" or "Given everything you've told me, what's \
                    the most important factor and why?"
                    """
            )
        }

        // Ready to move on
        return transitionMove(context: context, analysis: analysis)
    }

    // MARK: - Scaffolding

    private func scaffoldingMove(context: ConversationContext, analysis: DocumentAnalysis) -> NextMove {
        let topicName = context.currentTopic?.name ?? "this topic"
        let concepts = context.currentTopic?.keyConcepts.first ?? "the basics"

        return NextMove(
            intent: .scaffold(hint: concepts),
            promptGuidance: """
                The trainee is struggling or unsure about "\(topicName)". Don't move on — \
                help them get there. Break it down: "No worries, let's think about this \
                step by step. What do you know about \(concepts)?" or "Let me put it \
                another way..." or "Think about it from the patient's perspective — what \
                would they present with?"

                Be encouraging. This is a learning conversation, not a test of recall. \
                If they said "I don't know", acknowledge that honestly and scaffold: \
                "That's okay — let's work through it together."
                """
        )
    }

    // MARK: - Transition

    private func transitionMove(
        context: ConversationContext,
        analysis: DocumentAnalysis
    ) -> NextMove {
        let discussedNames = Set(context.topicsDiscussed.map(\.topic.name))
        let uncovered = analysis.topics.filter { !discussedNames.contains($0.name) }

        // Prefer uncovered topics, sorted by importance
        let nextTopic: ExamTopic
        if let uncoveredTopic = uncovered.sorted(by: { $0.importance > $1.importance }).first {
            nextTopic = uncoveredTopic
        } else {
            // Revisit weakest topic
            let weakest = context.topicsDiscussed
                .sorted { $0.averageUnderstanding < $1.averageUnderstanding }
                .first?.topic
            nextTopic = weakest ?? analysis.topics[0]
        }

        let bridge = context.currentTopic.map { current in
            "Bridge from \(current.name) to \(nextTopic.name) using something the trainee said."
        } ?? "Introduce \(nextTopic.name) naturally."

        return NextMove(
            intent: .transition(to: nextTopic, bridge: bridge),
            promptGuidance: """
                Transition to "\(nextTopic.name)" naturally. Don't say "Let's move on to..." \
                — instead, find a connection: "You mentioned X earlier, which actually ties \
                into..." or "That's a good segue into something I wanted to ask you about..." \
                or present a new clinical scenario that naturally involves \(nextTopic.name).

                \(bridge)
                Key concepts to eventually explore: \(nextTopic.keyConcepts.joined(separator: ", "))
                """
        )
    }

    // MARK: - Closing

    private func closingMove(context: ConversationContext) -> NextMove {
        let topicNames = context.topicsDiscussed.map(\.topic.name)

        return NextMove(
            intent: .closing,
            promptGuidance: """
                Wrap up the conversation warmly. Summarize what was discussed across \
                \(topicNames.joined(separator: ", ")). Highlight something specific the \
                trainee said well. If there were areas of struggle, frame them as areas \
                for further reading, not failures. End with encouragement.

                This should feel like the end of a good mentoring conversation, not the \
                end of an exam. "Overall, you've shown a really solid understanding of... \
                I'd suggest reading a bit more about... Great discussion."
                """
        )
    }

    // MARK: - Decision Helpers

    private func shouldWrapUp(context: ConversationContext, analysis: DocumentAnalysis) -> Bool {
        let topicsCovered = context.topicsDiscussed.count
        let totalTopics = analysis.topics.count

        // Time-based: approaching target duration
        if context.totalDuration > Double(15 * 60) { return true }

        // Exchange-based: enough conversation
        if context.exchangeCount > 25 { return true }

        // Coverage-based: all topics discussed with reasonable depth
        if topicsCovered >= totalTopics && context.exchangeCount >= totalTopics * 3 {
            return true
        }

        return false
    }

    private func shouldTransition(
        context: ConversationContext,
        assessments: [InlineAssessment],
        analysis: DocumentAnalysis
    ) -> Bool {
        // Too deep on one topic
        if context.depthOnCurrentTopic >= 5 { return true }

        // Strong mastery on current topic
        let recentAssessments = assessments.suffix(3)
        let averageUnderstanding = recentAssessments.isEmpty ? 0 :
            recentAssessments.map(\.understanding).reduce(0, +) / Double(recentAssessments.count)
        if averageUnderstanding > 0.8 && context.depthOnCurrentTopic >= 3 { return true }

        // Struggling badly — give them a fresh start on a new topic
        if averageUnderstanding < 0.3 && context.depthOnCurrentTopic >= 3 { return true }

        return false
    }

    private func isStrugglingResponse(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let strugglePatterns = [
            "i don't know",
            "i'm not sure",
            "i have no idea",
            "i can't remember",
            "i don't remember",
            "no clue",
            "pass",
            "um",
        ]

        // Very short response (< 15 chars) or contains struggle phrases
        if lowered.count < 15 && !lowered.contains(" and ") {
            return true
        }

        return strugglePatterns.contains { lowered.contains($0) }
    }
}
