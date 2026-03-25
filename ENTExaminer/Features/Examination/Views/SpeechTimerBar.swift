import SwiftUI

/// Speech Turn Indicator — a persistent horizontal bar showing whose turn it is
/// and the timing state of the conversation.
///
/// - **Trainee speaking**: Green bar fills left-to-right showing answer duration.
/// - **Silence detected**: Orange/red bar fills right-to-left showing countdown to examiner.
/// - **Examiner speaking**: Blue bar pulses to show the examiner has the floor.
/// - **Thinking**: Subtle animated bar while the examiner prepares a response.
/// - **Paused / Idle**: Empty track with status label.
struct SpeechTurnIndicator: View {
    let status: ExamStatus
    let isListening: Bool
    let isSpeaking: Bool
    let listeningStartTime: Date?
    let lastSpeechTime: Date?
    let silenceTimeout: TimeInterval
    var maxSpeakingDuration: TimeInterval = 60.0

    // Drive animation updates
    @State private var now = Date()
    @State private var timer: Timer?
    @State private var examinerPulse: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))

                    switch currentMode {
                    case .traineeActive:
                        // Green bar: speaking progress (left to right)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.7), .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * greenProgress))

                        // Red bar: silence countdown (right to left, anchored to right edge)
                        if redProgress > 0 {
                            let redWidth = max(0, geo.size.width * redProgress)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [redBarColor.opacity(0.7), redBarColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: redWidth)
                                .position(x: geo.size.width - redWidth / 2, y: geo.size.height / 2)
                        }

                    case .examinerActive:
                        // Blue pulsing bar while examiner speaks
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.5), .cyan.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(examinerPulse ? 1.0 : 0.5)

                    case .thinking:
                        // Animated indeterminate bar
                        Capsule()
                            .fill(Color.blue.opacity(0.3))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .blue.opacity(0.5), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: examinerPulse ? geo.size.width * 0.7 : 0)

                    case .idle:
                        EmptyView()
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            // Labels
            HStack {
                Text(leftLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(leftLabelColor)

                Spacer()

                if !rightLabel.isEmpty {
                    Text(rightLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(rightLabelColor)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .animation(.easeOut(duration: 0.15), value: greenProgress)
        .animation(.easeOut(duration: 0.15), value: redProgress)
        .animation(.easeInOut(duration: 0.8), value: examinerPulse)
        .onAppear {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                now = Date()
            }
            startPulse()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: currentMode) { _, _ in
            startPulse()
        }
    }

    // MARK: - Mode

    private enum Mode: Equatable {
        case traineeActive
        case examinerActive
        case thinking
        case idle
    }

    private var currentMode: Mode {
        if isListening { return .traineeActive }
        if isSpeaking { return .examinerActive }
        if status == .thinking { return .thinking }
        return .idle
    }

    // MARK: - Labels

    private var leftLabel: String {
        switch currentMode {
        case .traineeActive: return "Your turn"
        case .examinerActive: return "Examiner speaking"
        case .thinking: return "Examiner thinking..."
        case .idle:
            switch status {
            case .paused: return "Paused"
            case .finished: return "Examination complete"
            default: return "Speech Turn Indicator"
            }
        }
    }

    private var leftLabelColor: Color {
        switch currentMode {
        case .traineeActive: return .green
        case .examinerActive: return .blue
        case .thinking: return .blue
        case .idle: return .secondary
        }
    }

    private var rightLabel: String {
        switch currentMode {
        case .traineeActive:
            if redProgress > 0.7 {
                return "Examiner taking over..."
            } else if redProgress > 0 {
                return "Silence detected"
            }
            return ""
        case .examinerActive: return ""
        case .thinking: return ""
        case .idle: return ""
        }
    }

    private var rightLabelColor: Color {
        redBarColor
    }

    // MARK: - Pulse

    private func startPulse() {
        examinerPulse = false
        if currentMode == .examinerActive || currentMode == .thinking {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                examinerPulse = true
            }
        }
    }

    // MARK: - Progress (trainee mode)

    private var greenProgress: CGFloat {
        guard currentMode == .traineeActive, let start = listeningStartTime else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1.0, CGFloat(elapsed / maxSpeakingDuration))
    }

    private var redProgress: CGFloat {
        guard currentMode == .traineeActive, let lastSpeech = lastSpeechTime else { return 0 }
        let silenceElapsed = now.timeIntervalSince(lastSpeech)
        guard silenceElapsed > 0 else { return 0 }
        return min(1.0, CGFloat(silenceElapsed / silenceTimeout))
    }

    private var redBarColor: Color {
        redProgress > 0.7 ? .red : .orange
    }
}
