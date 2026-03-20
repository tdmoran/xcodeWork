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
        let lastExaminerMessage = messages.last { $0.role == .examiner }
        let lastAssessment = assessments.last

        // Handle empty/whitespace-only responses (silence)
        if let traineeText = lastTraineeMessage?.content, isSilentResponse(traineeText) {
            return scaffoldForSilence(context: context)
        }

        // Handle repetitive filler or echoing the question back
        if let traineeText = lastTraineeMessage?.content,
           isStrugglingResponse(traineeText, examinerText: lastExaminerMessage?.content) {
            return scaffoldingMove(context: context, analysis: analysis)
        }

        // Check if we should stay on topic or transition
        if shouldTransition(context: context, assessments: assessments, analysis: analysis) {
            return transitionMove(context: context, analysis: analysis)
        }

        // Build the follow-up move
        var move = followUpMove(
            context: context,
            lastAssessment: lastAssessment,
            analysis: analysis
        )

        // Teaching moment: when trainee demonstrates strong understanding
        if let assessment = lastAssessment,
           shouldIncludeTeachingMoment(understanding: assessment.understanding) {
            move = addTeachingMoment(to: move)
        }

        // Time pressure awareness
        move = addTimePressureIfNeeded(to: move, context: context)

        // Mood-aware tone adjustment
        move = adjustForMood(move: move, mood: context.recentMood)

        return move
    }

    // MARK: - Opening

    private func openingMove(analysis: DocumentAnalysis) -> NextMove {
        guard let firstTopic = analysis.topics.max(by: { $0.importance < $1.importance }) else {
            return NextMove(
                intent: .closing,
                promptGuidance: """
                    No topics available to discuss. Politely explain that the document \
                    didn't contain enough material for a discussion.
                    """
            )
        }

        let scenarioStarter = randomElement(from: openingScenarioStarters)

        return NextMove(
            intent: .openTopic(firstTopic),
            promptGuidance: """
                Open the conversation naturally. You're a senior consultant about to discuss \
                "\(firstTopic.name)" with a trainee. Don't jump straight into a question — \
                set the scene briefly using a clinical scenario, then invite \
                the trainee to share their thoughts. Keep it warm and collegial.

                Start the scenario with something like: "\(scenarioStarter)"

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
            let template = randomElement(from: partialUnderstandingTemplates)
            return NextMove(
                intent: .followUp(aspect: gap.concept),
                promptGuidance: """
                    The trainee showed partial understanding of "\(gap.concept)" — \
                    they mentioned some aspects but missed: \(gap.detail). \
                    \(template)
                    """
            )
        }

        // Misconception detected — gently correct
        let misconceptions = assessment.signals.filter { $0.type == .misconception }
        if let misconception = misconceptions.first {
            let template = randomElement(from: misconceptionTemplates)
            return NextMove(
                intent: .clarify(misconception: misconception.detail),
                promptGuidance: """
                    The trainee seems to have a misconception about \
                    "\(misconception.concept)": \(misconception.detail). \
                    \(template)
                    """
            )
        }

        return probeMove(context: context)
    }

    private func probeMove(context: ConversationContext) -> NextMove {
        let topicName = context.currentTopic?.name ?? "the current topic"
        let template = randomElement(from: followUpProbeTemplates)

        return NextMove(
            intent: .followUp(aspect: topicName),
            promptGuidance: """
                Continue the conversation naturally about "\(topicName)". \
                Acknowledge what the trainee said, then \(template)
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
            let template = randomElement(from: deeperProbeTemplates)
            return NextMove(
                intent: .followUp(aspect: concept),
                promptGuidance: """
                    The trainee is doing well — push them harder. They haven't discussed \
                    "\(concept)" yet. \(String(format: template, concept, concept))
                    """
            )
        }

        // All concepts covered on this topic — synthesize
        let connections = assessment.signals.filter { $0.type == .connection }
        if connections.count < 2 {
            let template = randomElement(from: synthesizeTemplates)
            return NextMove(
                intent: .synthesize(topics: [topic.name]),
                promptGuidance: """
                    The trainee has covered the key concepts well. \(template)
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
        let template = randomElement(from: scaffoldTemplates)

        return NextMove(
            intent: .scaffold(hint: concepts),
            promptGuidance: """
                The trainee is struggling or unsure about "\(topicName)". Don't move on — \
                help them get there. \(String(format: template, concepts))

                Be encouraging. This is a learning conversation, not a test of recall. \
                If they said "I don't know", acknowledge that honestly and scaffold: \
                "That's okay — let's work through it together."
                """
        )
    }

    /// A gentler scaffold for when the trainee goes silent or gives empty responses.
    private func scaffoldForSilence(context: ConversationContext) -> NextMove {
        let topicName = context.currentTopic?.name ?? "this topic"
        let template = randomElement(from: silenceScaffoldTemplates)

        return NextMove(
            intent: .scaffold(hint: "gentle nudge"),
            promptGuidance: """
                The trainee seems to need a moment with "\(topicName)". \(template)

                Do NOT repeat the question verbatim. Instead, offer a different angle \
                or simplify. Keep the tone warm and unhurried.
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

        let template = randomElement(from: transitionTemplates)

        return NextMove(
            intent: .transition(to: nextTopic, bridge: bridge),
            promptGuidance: """
                Transition to "\(nextTopic.name)" naturally. \(String(format: template, nextTopic.name))

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

    // MARK: - Teaching Moments

    /// Occasionally include a teaching pearl when the trainee demonstrates strong understanding.
    private func shouldIncludeTeachingMoment(understanding: Double) -> Bool {
        understanding > 0.8 && Int.random(in: 1...10) <= 3
    }

    private func addTeachingMoment(to move: NextMove) -> NextMove {
        let teachingGuidance = """

            Before your next question, share a brief clinical anecdote or teaching pearl \
            related to what the trainee just said well. Something like \
            "That reminds me of a case I had..." or "You know, that's exactly the kind of \
            thinking that..." Keep it to 1-2 sentences. Make it feel natural and conversational, \
            not like a lecture.
            """
        return NextMove(
            intent: move.intent,
            promptGuidance: move.promptGuidance + teachingGuidance
        )
    }

    // MARK: - Time Pressure Awareness

    /// Whether to mention time naturally during the conversation.
    private func shouldMentionTime(totalDuration: TimeInterval) -> Bool {
        if totalDuration > 720 {
            // > 12 minutes: 50% chance
            return Int.random(in: 1...10) <= 5
        } else if totalDuration > 600 {
            // > 10 minutes: 20% chance
            return Int.random(in: 1...10) <= 2
        }
        return false
    }

    private func addTimePressureIfNeeded(to move: NextMove, context: ConversationContext) -> NextMove {
        guard shouldMentionTime(totalDuration: context.totalDuration) else {
            return move
        }

        let timeGuidance: String
        if context.totalDuration > 720 {
            timeGuidance = """

                Gently note that we should start wrapping up: "We should start thinking \
                about bringing things together..." or "In the time we have left, let's \
                touch on..." Do NOT create panic or say "we're running out of time."
                """
        } else {
            timeGuidance = """

                Briefly and naturally acknowledge that time is moving along, without \
                creating pressure. Something like "We're making good progress..." or \
                "Let's make sure we cover..." Do NOT say "we're running out of time."
                """
        }

        return NextMove(
            intent: move.intent,
            promptGuidance: move.promptGuidance + timeGuidance
        )
    }

    // MARK: - Mood-Aware Responses

    private func adjustForMood(move: NextMove, mood: TraineeMood) -> NextMove {
        let moodGuidance: String
        switch mood {
        case .confident:
            moodGuidance = """

                The trainee seems confident. Push harder — ask more challenging questions, \
                introduce edge cases, or ask them to defend their reasoning. \
                "That's solid, but what about when..." or "Play devil's advocate for me..."
                """
        case .engaged:
            moodGuidance = """

                The trainee is engaged and following well. Maintain the current difficulty \
                level and explore depth. Let them lead where they're curious. \
                Build on their momentum.
                """
        case .neutral:
            moodGuidance = """

                The trainee seems neutral — neither excited nor struggling. Mix in a \
                slightly easier or more clinically relevant question to build momentum \
                and spark engagement. Ground the discussion in a relatable scenario.
                """
        case .hesitant:
            moodGuidance = """

                The trainee seems hesitant. Be more encouraging — validate what they've \
                said so far. Offer more scaffolding. Use phrases like "You're on the \
                right track..." or "That's a good start, let's build on that..."
                """
        case .struggling:
            moodGuidance = """

                The trainee is struggling. Be very supportive and break things down \
                into smaller, more manageable pieces. Use simple language, offer choices \
                rather than open questions: "Would you say it's more like A or B?" \
                Reassure them: "This is a tricky area — let's take it step by step."
                """
        }

        return NextMove(
            intent: move.intent,
            promptGuidance: move.promptGuidance + moodGuidance
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

    private func isStrugglingResponse(_ text: String, examinerText: String? = nil) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let strugglePatterns = [
            "i don't know",
            "i'm not sure",
            "i have no idea",
            "i can't remember",
            "i don't remember",
            "no clue",
            "pass",
        ]

        // Very short response (< 15 chars) or contains struggle phrases
        if lowered.count < 15 && !lowered.contains(" and ") {
            return true
        }

        if strugglePatterns.contains(where: { lowered.contains($0) }) {
            return true
        }

        // Repetitive filler with little content
        if isFillerHeavy(lowered) {
            return true
        }

        // Echoing the examiner's question back
        if let examiner = examinerText, isEchoing(trainee: lowered, examiner: examiner) {
            return true
        }

        return false
    }

    /// Detects empty or whitespace-only responses indicating silence or a long pause.
    private func isSilentResponse(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Detects responses dominated by filler words ("um", "uh", "er") with little substance.
    private func isFillerHeavy(_ lowered: String) -> Bool {
        let fillerPatterns = ["um", "uh", "er", "erm", "hmm", "umm"]
        let words = lowered.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return false }

        let fillerCount = words.filter { word in
            fillerPatterns.contains(word.trimmingCharacters(in: .punctuationCharacters))
        }.count

        let fillerRatio = Double(fillerCount) / Double(words.count)
        // If more than half the words are filler and total is short
        return fillerRatio > 0.5 && words.count < 12
    }

    /// Detects when the trainee is just echoing the examiner's question back.
    private func isEchoing(trainee: String, examiner: String) -> Bool {
        let examinerLowered = examiner.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let traineeWords = Set(trainee.split(separator: " ").map(String.init))
        let examinerWords = Set(examinerLowered.split(separator: " ").map(String.init))

        guard traineeWords.count >= 3, examinerWords.count >= 3 else { return false }

        let overlap = traineeWords.intersection(examinerWords)
        let overlapRatio = Double(overlap.count) / Double(traineeWords.count)
        // If 80%+ of the trainee's words came from the examiner's question
        return overlapRatio > 0.8
    }

    // MARK: - Template Selection

    private func randomElement(from templates: [String]) -> String {
        let index = Int.random(in: 0..<templates.count)
        return templates[index]
    }

    // MARK: - Prompt Templates

    private var openingScenarioStarters: [String] {
        [
            "Imagine a patient walks into your clinic...",
            "You're on call and get referred a patient with...",
            "A GP sends you a referral letter about...",
            "You're reviewing a case in the MDT meeting...",
            "During your outpatient clinic, you see...",
        ]
    }

    private var followUpProbeTemplates: [String] {
        [
            """
            ask a follow-up that probes their understanding from a different angle. \
            Use their own words where possible — "You mentioned X, can you tell me more \
            about how that works?" or "Good point about X — what would you do differently if...?"
            """,
            """
            present a clinical case that tests the concept they just described. \
            "Let me give you a scenario — a 45-year-old presents with..." \
            See if they can apply what they just explained.
            """,
            """
            ask the trainee to compare or contrast two related concepts. \
            "How does that differ from..." or "What would change if instead of X, \
            we were dealing with Y?"
            """,
            """
            pose a hypothetical variation on what they just discussed. \
            "What if the patient also had..." or "And what would you do differently \
            if the presentation was slightly different — say..."
            """,
        ]
    }

    private var deeperProbeTemplates: [String] {
        [
            """
            Connect it naturally to what they just said. \
            "That's exactly right. Now, thinking about %@, how would that \
            change your approach?" or "Excellent. Let's take it further — tell me \
            about %@ in this context."
            """,
            """
            Ask them to walk through how %@ fits into the clinical picture. \
            "Walk me through how you'd factor in %@ when making your decision." \
            Let them explain the process step by step.
            """,
            """
            Challenge them with a scenario that requires knowledge of %@. \
            "Now here's a twist — what if %@ was a factor? How does that \
            change things?"
            """,
            """
            Ask them to explain %@ as if teaching a junior colleague. \
            "If a medical student asked you about %@, how would you explain \
            its relevance here?"
            """,
        ]
    }

    private var partialUnderstandingTemplates: [String] {
        [
            """
            Don't tell them what they missed directly. Instead, ask a follow-up \
            that naturally leads them to think about the missing aspect. \
            Use phrases like "And what about..." or "How does that relate to..."
            """,
            """
            Guide them towards the gap without revealing it. Try a clinical \
            scenario that makes the missing piece relevant: "Now imagine \
            this patient also had... what would you consider then?"
            """,
            """
            Acknowledge what they got right, then use a "what else" prompt: \
            "Good — you've covered some important points. What else might \
            be relevant here?" or "Is there anything else you'd want to check?"
            """,
            """
            Use a compare-and-contrast approach to expose the gap: \
            "That's partly right. How would your answer change if we were \
            talking about a different type of patient?" or "What distinguishes \
            this from a similar condition?"
            """,
        ]
    }

    private var misconceptionTemplates: [String] {
        [
            """
            Don't bluntly correct them. Instead, present a scenario or ask a \
            question that exposes the contradiction. Something like "That's \
            interesting — but what would happen if..." or "I see what you mean, \
            but consider this case..."
            """,
            """
            Gently probe the misconception by asking them to explain their \
            reasoning: "Walk me through how you arrived at that." Often \
            trainees self-correct when they think aloud.
            """,
            """
            Use a Socratic approach: ask a question whose answer contradicts \
            the misconception. "If that were the case, what would we expect \
            to see clinically? And does that match what we typically find?"
            """,
        ]
    }

    private var scaffoldTemplates: [String] {
        [
            """
            Break it down: "No worries, let's think about this step by step. \
            What do you know about %@?" or "Let me put it another way..." \
            or "Think about it from the patient's perspective — what would \
            they present with?"
            """,
            """
            Offer a starting point: "Let's start with the basics. If a patient \
            came to you with this problem, what's the first thing you'd want \
            to know about %@?"
            """,
            """
            Give them a multiple-choice scaffold: "Would you say %@ is more \
            related to A, B, or C? Don't worry about getting it exactly right \
            — just think out loud."
            """,
            """
            Reframe the question more concretely: "Let me put it differently. \
            Picture a real patient in front of you. They ask you about %@. \
            What would you tell them in plain language?"
            """,
        ]
    }

    private var silenceScaffoldTemplates: [String] {
        [
            """
            Give them a gentle nudge without pressure: "Take your time — \
            there's no rush. Would it help if I rephrased the question?"
            """,
            """
            Offer to approach it differently: "Would it help if I came at \
            this from a different angle? Sometimes it's easier to think about \
            it in terms of a specific patient."
            """,
            """
            Normalize the pause: "It's completely fine to take a moment. \
            This is a thinking question, not a speed test. Want me to \
            give you a hint to get started?"
            """,
            """
            Lower the stakes: "No pressure at all. Let's simplify — if you \
            had to guess, what would your instinct tell you? We can work \
            from there."
            """,
        ]
    }

    private var transitionTemplates: [String] {
        [
            """
            Don't say "Let's move on to..." — instead, find a connection: \
            "You mentioned something earlier that actually ties into..." \
            or "That's a good segue into something I wanted to ask you about..." \
            or present a new clinical scenario that naturally involves %@.
            """,
            """
            Use the trainee's own words as a bridge: "You touched on something \
            interesting there. It actually connects to %@. Tell me what \
            comes to mind when you think about that."
            """,
            """
            Introduce a new clinical scenario that naturally involves %@. \
            "Let me paint you a different picture — new patient, different \
            presentation..." Make the transition feel organic, not abrupt.
            """,
            """
            Pivot through a patient case: "Staying with our patient for a \
            moment — what if they also had a concern about %@? \
            How would that change your thinking?"
            """,
        ]
    }

    private var synthesizeTemplates: [String] {
        [
            """
            Ask them to synthesize — "So pulling all that together, if you \
            had a patient presenting with... how would you approach it?" \
            or "Given everything you've told me, what's the most important \
            factor and why?"
            """,
            """
            Ask them to prioritize: "You've covered a lot of ground. If you \
            had to pick the three most important things to remember about \
            this topic, what would they be and why?"
            """,
            """
            Present a complex case that requires integrating multiple concepts: \
            "Let me give you a more complex scenario that ties several things \
            together..." See if they can apply their knowledge holistically.
            """,
        ]
    }
}
