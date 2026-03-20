import SwiftUI
import Charts

// MARK: - Conversation Summary View

struct ConversationSummaryView: View {
    @Environment(AppState.self) private var appState
    let summary: DialogueSummary

    @State private var animateIn = false
    @State private var scoreProgress: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerSection
                overallAssessmentCard
                topicsCoveredSection
                strengthsSection
                areasForImprovementSection
                knowledgeGapsSection
                suggestedStudySection
                keyMomentsSection
                actionBar
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animateIn = true
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                scoreProgress = summary.overallScore
            }
        }
    }
}

// MARK: - Header

private extension ConversationSummaryView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "stethoscope")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: animateIn)

            Text("Conversation Review")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(summary.documentTitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(formatDuration(summary.totalDuration), systemImage: "clock")
                Label(
                    "\(summary.exchangeCount) exchanges",
                    systemImage: "bubble.left.and.bubble.right"
                )
                Label(summary.modelUsed.displayName, systemImage: "cpu")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -20)
    }
}

// MARK: - Overall Assessment Card

private extension ConversationSummaryView {
    var overallAssessmentCard: some View {
        HStack(spacing: 32) {
            progressRing

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.grade)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(gradeColor)
                    .contentTransition(.numericText())

                Text(narrativeAssessment)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }

    var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(from: 0, to: scoreProgress)
                .stroke(
                    gradeColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(scoreProgress * 100))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("overall")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
    }

    var narrativeAssessment: String {
        switch summary.overallScore {
        case 0.9...:
            return "Outstanding conversation. You demonstrated deep understanding across topics and made impressive connections between concepts."
        case 0.75..<0.9:
            return "A strong showing. Your knowledge base is solid, with a few areas that could benefit from further exploration."
        case 0.6..<0.75:
            return "You showed a reasonable grasp of the material. Some topics came through clearly while others could use reinforcement."
        case 0.4..<0.6:
            return "You have a foundation to build on. Targeted review of the areas below will help solidify your understanding."
        default:
            return "This is a starting point. Everyone begins somewhere, and the areas identified below give you a clear path forward."
        }
    }
}

// MARK: - Topics Covered

private extension ConversationSummaryView {
    var topicsCoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topics Covered")
                .font(.headline)

            ForEach(
                Array(summary.topicDiscussions.enumerated()),
                id: \.offset
            ) { _, discussion in
                topicRow(discussion)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }

    func topicRow(_ discussion: TopicDiscussion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(discussion.topic.name)
                    .font(.callout)
                    .fontWeight(.medium)

                depthIndicator(discussion.exchangeCount)

                Spacer()

                trendArrow(for: discussion.topic.name)

                Text("\(Int(discussion.averageUnderstanding * 100))%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: discussion.averageUnderstanding)
                .tint(understandingColor(discussion.averageUnderstanding))

            let allSignals = discussion.assessments.flatMap(\.signals)
            if !allSignals.isEmpty {
                signalsList(allSignals)
            }
        }
        .padding(.vertical, 4)
    }

    func depthIndicator(_ exchangeCount: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(exchangeCount, 5), id: \.self) { index in
                Circle()
                    .fill(index < exchangeCount ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    func trendArrow(for topicName: String) -> some View {
        let trend = summary.topicScores
            .first { $0.topicName == topicName }?.trend ?? .stable

        return Image(
            systemName: trend == .improving ? "arrow.up.right" :
                trend == .declining ? "arrow.down.right" : "arrow.right"
        )
        .font(.caption)
        .foregroundStyle(
            trend == .improving ? .green :
                trend == .declining ? .red : .secondary
        )
    }

    func signalsList(_ signals: [KnowledgeSignal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(
                Array(signals.prefix(4).enumerated()),
                id: \.offset
            ) { _, signal in
                HStack(spacing: 6) {
                    Image(systemName: signalIcon(signal.type))
                        .font(.caption2)
                        .foregroundStyle(signalColor(signal.type))

                    Text(signal.concept)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Strengths

private extension ConversationSummaryView {
    var strengthSignals: [KnowledgeSignal] {
        summary.assessments
            .flatMap(\.signals)
            .filter { $0.type == .demonstrated || $0.type == .connection }
    }

    var strengthsSection: some View {
        Group {
            if !strengthSignals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Strengths Identified")
                        .font(.headline)

                    ForEach(
                        Array(strengthSignals.enumerated()),
                        id: \.offset
                    ) { _, signal in
                        strengthCard(signal)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
    }

    func strengthCard(_ signal: KnowledgeSignal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: signal.type == .connection ?
                  "link.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.concept)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(signal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.green.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

// MARK: - Areas for Improvement

private extension ConversationSummaryView {
    var improvementSignals: [KnowledgeSignal] {
        summary.assessments
            .flatMap(\.signals)
            .filter { $0.type == .partial || $0.type == .misconception }
    }

    var areasForImprovementSection: some View {
        Group {
            if !improvementSignals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Areas for Improvement")
                        .font(.headline)

                    ForEach(
                        Array(improvementSignals.enumerated()),
                        id: \.offset
                    ) { _, signal in
                        improvementCard(signal)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
    }

    func improvementCard(_ signal: KnowledgeSignal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: signal.type == .misconception ?
                  "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .foregroundStyle(signal.type == .misconception ? .red : .orange)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.concept)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(signal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

// MARK: - Knowledge Gaps

private extension ConversationSummaryView {
    var knowledgeGaps: [GapItem] {
        var gaps: [GapItem] = []

        // Topics with low understanding
        for discussion in summary.topicDiscussions
            where discussion.averageUnderstanding < 0.4 {
            gaps.append(GapItem(
                topic: discussion.topic.name,
                reason: "Understanding was below threshold during the conversation",
                understanding: discussion.averageUnderstanding
            ))
        }

        // Uncertain signals
        let uncertainSignals = summary.assessments
            .flatMap(\.signals)
            .filter { $0.type == .uncertain }

        for signal in uncertainSignals {
            let alreadyCovered = gaps.contains { $0.topic == signal.concept }
            if !alreadyCovered {
                gaps.append(GapItem(
                    topic: signal.concept,
                    reason: signal.detail,
                    understanding: 0.2
                ))
            }
        }

        return gaps
    }

    var knowledgeGapsSection: some View {
        Group {
            if !knowledgeGaps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Knowledge Gaps")
                        .font(.headline)

                    Text("These areas need further study to build confidence.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(
                        Array(knowledgeGaps.enumerated()),
                        id: \.offset
                    ) { _, gap in
                        gapCard(gap)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
    }

    func gapCard(_ gap: GapItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(.purple)
                .font(.callout)

            VStack(alignment: .leading, spacing: 2) {
                Text(gap.topic)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(gap.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.purple.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

// MARK: - Suggested Study Topics

private extension ConversationSummaryView {
    var studySuggestions: [StudySuggestion] {
        var suggestions: [StudySuggestion] = []

        // From knowledge gaps
        for gap in knowledgeGaps {
            suggestions.append(StudySuggestion(
                topic: gap.topic,
                gap: gap.reason,
                suggestion: "Review core concepts and practice explaining them in your own words."
            ))
        }

        // From misconceptions
        let misconceptions = summary.assessments
            .flatMap(\.signals)
            .filter { $0.type == .misconception }

        for signal in misconceptions {
            let alreadyCovered = suggestions.contains { $0.topic == signal.concept }
            if !alreadyCovered {
                suggestions.append(StudySuggestion(
                    topic: signal.concept,
                    gap: signal.detail,
                    suggestion: "Revisit the primary source material and compare with your current understanding."
                ))
            }
        }

        // From partial understanding
        let partials = summary.assessments
            .flatMap(\.signals)
            .filter { $0.type == .partial }

        for signal in partials {
            let alreadyCovered = suggestions.contains { $0.topic == signal.concept }
            if !alreadyCovered {
                suggestions.append(StudySuggestion(
                    topic: signal.concept,
                    gap: signal.detail,
                    suggestion: "You have the foundation -- fill in the details with targeted reading."
                ))
            }
        }

        return suggestions
    }

    var suggestedStudySection: some View {
        Group {
            if !studySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Study Topics")
                        .font(.headline)

                    Text("Focus your next study session on these areas for the biggest improvement.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(
                        Array(studySuggestions.enumerated()),
                        id: \.offset
                    ) { _, item in
                        studySuggestionCard(item)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
    }

    func studySuggestionCard(_ item: StudySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.topic)
                .font(.callout)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(item.gap)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(item.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

// MARK: - Key Moments

private extension ConversationSummaryView {
    var keyMoments: [KeyMoment] {
        let examinerMessages = summary.messages.filter { $0.role == .examiner }
        let traineeMessages = summary.messages.filter { $0.role == .trainee }
        let pairs = zip(examinerMessages, traineeMessages).map { ($0, $1) }

        guard !pairs.isEmpty else { return [] }

        var moments: [KeyMoment] = []

        // First exchange
        if let first = pairs.first {
            moments.append(KeyMoment(
                label: "Opening",
                examinerText: first.0.content,
                traineeText: first.1.content,
                icon: "play.circle.fill"
            ))
        }

        // Best moment (highest understanding)
        let scored = pairs.compactMap { pair -> (Double, (DialogueMessage, DialogueMessage))? in
            let score = pair.0.assessment?.understanding
                ?? pair.1.assessment?.understanding ?? 0
            return (score, pair)
        }

        if let best = scored.max(by: { $0.0 < $1.0 }),
           best.0 > 0 {
            let alreadyAdded = moments.contains {
                $0.examinerText == best.1.0.content
            }
            if !alreadyAdded {
                moments.append(KeyMoment(
                    label: "Best Moment",
                    examinerText: best.1.0.content,
                    traineeText: best.1.1.content,
                    icon: "star.fill"
                ))
            }
        }

        // Worst moment (lowest understanding, if notably low)
        if let worst = scored.min(by: { $0.0 < $1.0 }),
           worst.0 < 0.5 {
            let alreadyAdded = moments.contains {
                $0.examinerText == worst.1.0.content
            }
            if !alreadyAdded {
                moments.append(KeyMoment(
                    label: "Challenging Moment",
                    examinerText: worst.1.0.content,
                    traineeText: worst.1.1.content,
                    icon: "exclamationmark.bubble.fill"
                ))
            }
        }

        // Misconception correction
        let misconceptionPair = pairs.first { pair in
            let signals = (pair.0.assessment?.signals ?? [])
                + (pair.1.assessment?.signals ?? [])
            return signals.contains { $0.type == .misconception }
        }
        if let correction = misconceptionPair {
            let alreadyAdded = moments.contains {
                $0.examinerText == correction.0.content
            }
            if !alreadyAdded {
                moments.append(KeyMoment(
                    label: "Misconception Addressed",
                    examinerText: correction.0.content,
                    traineeText: correction.1.content,
                    icon: "arrow.uturn.right.circle.fill"
                ))
            }
        }

        // Final exchange
        if pairs.count > 1, let last = pairs.last {
            let alreadyAdded = moments.contains {
                $0.examinerText == last.0.content
            }
            if !alreadyAdded {
                moments.append(KeyMoment(
                    label: "Closing",
                    examinerText: last.0.content,
                    traineeText: last.1.content,
                    icon: "flag.checkered"
                ))
            }
        }

        return Array(moments.prefix(5))
    }

    var keyMomentsSection: some View {
        Group {
            if !keyMoments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Key Moments")
                        .font(.headline)

                    ForEach(
                        Array(keyMoments.enumerated()),
                        id: \.offset
                    ) { _, moment in
                        keyMomentCard(moment)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
    }

    func keyMomentCard(_ moment: KeyMoment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: moment.icon)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)

                Text(moment.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }

            // Examiner bubble
            HStack {
                Text(truncatedText(moment.examinerText, maxLength: 200))
                    .font(.caption)
                    .padding(8)
                    .background(
                        Color.blue.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                Spacer(minLength: 40)
            }

            // Trainee bubble
            HStack {
                Spacer(minLength: 40)

                Text(truncatedText(moment.traineeText, maxLength: 200))
                    .font(.caption)
                    .padding(8)
                    .background(
                        Color.green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Action Bar

private extension ConversationSummaryView {
    var actionBar: some View {
        HStack(spacing: 16) {
            Button("New Examination") {
                appState.resetForNewExamination()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Practice Again") {
                appState.selectedSection = .examination
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, 8)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
}

// MARK: - Helper Types

private struct GapItem {
    let topic: String
    let reason: String
    let understanding: Double
}

private struct StudySuggestion: Equatable {
    let topic: String
    let gap: String
    let suggestion: String
}

private struct KeyMoment {
    let label: String
    let examinerText: String
    let traineeText: String
    let icon: String
}

// MARK: - Utility Functions

private extension ConversationSummaryView {
    var gradeColor: Color {
        understandingColor(summary.overallScore)
    }

    func understandingColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return .green
        case 0.6..<0.75: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    func signalIcon(_ type: KnowledgeSignal.SignalType) -> String {
        switch type {
        case .demonstrated: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .misconception: return "xmark.circle.fill"
        case .uncertain: return "questionmark.circle"
        case .connection: return "link.circle.fill"
        }
    }

    func signalColor(_ type: KnowledgeSignal.SignalType) -> Color {
        switch type {
        case .demonstrated, .connection: return .green
        case .partial: return .yellow
        case .misconception: return .red
        case .uncertain: return .purple
        }
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    func truncatedText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}

// MARK: - Preview

#if DEBUG
struct ConversationSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        ConversationSummaryView(summary: previewDialogueSummary)
            .environment(PreviewData.makePreviewAppState(withResults: true))
            .frame(width: 700, height: 1200)
            .previewDisplayName("Conversation Summary")
    }

    static var previewDialogueSummary: DialogueSummary {
        let topics = PreviewData.sampleTopics

        let messages: [DialogueMessage] = [
            DialogueMessage(
                role: .examiner,
                content: "Let's start with otology. Can you walk me through the pathophysiology of acute otitis media?",
                intent: .openTopic(topics[0]),
                assessment: nil
            ),
            DialogueMessage(
                role: .trainee,
                content: "Acute otitis media involves bacterial infection of the middle ear, commonly from Streptococcus pneumoniae. The Eustachian tube dysfunction leads to fluid accumulation.",
                assessment: InlineAssessment(
                    topicName: "Otitis Media",
                    understanding: 0.85,
                    confidence: 0.8,
                    signals: [
                        KnowledgeSignal(type: .demonstrated, concept: "Bacterial etiology", detail: "Correctly identified S. pneumoniae as common pathogen"),
                        KnowledgeSignal(type: .demonstrated, concept: "Eustachian tube role", detail: "Linked tube dysfunction to fluid accumulation"),
                        KnowledgeSignal(type: .partial, concept: "Viral prodrome", detail: "Did not mention preceding viral URI")
                    ]
                )
            ),
            DialogueMessage(
                role: .examiner,
                content: "Good. And what about the first-line treatment approach?",
                intent: .followUp(aspect: "treatment"),
                assessment: nil
            ),
            DialogueMessage(
                role: .trainee,
                content: "First-line is amoxicillin for 7-10 days. For penicillin allergy, we can use azithromycin.",
                assessment: InlineAssessment(
                    topicName: "Otitis Media",
                    understanding: 0.75,
                    confidence: 0.7,
                    signals: [
                        KnowledgeSignal(type: .demonstrated, concept: "Amoxicillin first-line", detail: "Correct antibiotic choice and duration"),
                        KnowledgeSignal(type: .misconception, concept: "Allergy alternative", detail: "Azithromycin is not ideal -- cephalosporins preferred if no anaphylaxis history")
                    ]
                )
            ),
            DialogueMessage(
                role: .examiner,
                content: "Now let's discuss hearing loss. What are the key differences between conductive and sensorineural?",
                intent: .transition(to: topics[2], bridge: "Moving from middle ear pathology to hearing assessment"),
                assessment: nil
            ),
            DialogueMessage(
                role: .trainee,
                content: "Conductive involves outer or middle ear issues blocking sound. Sensorineural is inner ear or nerve damage. Weber lateralizes to the affected ear in conductive loss.",
                assessment: InlineAssessment(
                    topicName: "Hearing Loss",
                    understanding: 0.92,
                    confidence: 0.9,
                    signals: [
                        KnowledgeSignal(type: .demonstrated, concept: "CHL vs SNHL distinction", detail: "Clear, accurate differentiation"),
                        KnowledgeSignal(type: .connection, concept: "Weber test application", detail: "Unprompted connection to clinical testing"),
                        KnowledgeSignal(type: .demonstrated, concept: "Anatomical localization", detail: "Correctly mapped pathology to ear structures")
                    ]
                )
            ),
            DialogueMessage(
                role: .examiner,
                content: "Excellent connection with the Weber test. When would you consider CT imaging for sinusitis?",
                intent: .transition(to: topics[1], bridge: "Transitioning to rhinology"),
                assessment: nil
            ),
            DialogueMessage(
                role: .trainee,
                content: "I'm not entirely sure... maybe when symptoms last more than 12 weeks?",
                assessment: InlineAssessment(
                    topicName: "Sinusitis",
                    understanding: 0.35,
                    confidence: 0.3,
                    signals: [
                        KnowledgeSignal(type: .uncertain, concept: "CT imaging indications", detail: "Expressed uncertainty about when to order imaging"),
                        KnowledgeSignal(type: .partial, concept: "Chronic sinusitis timeline", detail: "Knew the 12-week threshold but lacked specifics")
                    ]
                )
            ),
        ]

        let assessments = messages.compactMap(\.assessment)

        let topicDiscussions = [
            TopicDiscussion(
                topic: topics[0],
                exchangeCount: 4,
                assessments: assessments.filter { $0.topicName == "Otitis Media" }
            ),
            TopicDiscussion(
                topic: topics[2],
                exchangeCount: 2,
                assessments: assessments.filter { $0.topicName == "Hearing Loss" }
            ),
            TopicDiscussion(
                topic: topics[1],
                exchangeCount: 2,
                assessments: assessments.filter { $0.topicName == "Sinusitis" }
            ),
        ]

        return DialogueSummary(
            messages: messages,
            assessments: assessments,
            topicDiscussions: topicDiscussions,
            overallScore: 0.72,
            topicScores: [
                TopicScore(topicName: "Otitis Media", mastery: 0.80, questionsAsked: 2, questionsCorrect: 1, trend: .stable),
                TopicScore(topicName: "Hearing Loss", mastery: 0.92, questionsAsked: 1, questionsCorrect: 1, trend: .improving),
                TopicScore(topicName: "Sinusitis", mastery: 0.35, questionsAsked: 1, questionsCorrect: 0, trend: .declining),
            ],
            totalDuration: 540,
            documentTitle: "ENT Clinical Examination Guide",
            modelUsed: .haiku
        )
    }
}
#endif
