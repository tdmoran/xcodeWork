import SwiftUI

/// A horizontal bar showing the user how long they've been speaking (green, left-to-right)
/// and how close they are to the silence cutoff (red, right-to-left).
///
/// The green bar grows steadily while the user speaks. When the user stops speaking,
/// a red bar begins filling from the right edge toward the left — once it reaches
/// full width, the examiner will take over.
struct SpeechTimerBar: View {
    let listeningStartTime: Date?
    let lastSpeechTime: Date?
    let silenceTimeout: TimeInterval
    var maxSpeakingDuration: TimeInterval = 60.0

    // Drive animation updates
    @State private var now = Date()
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))

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

                    // Red bar: silence countdown (right to left)
                    if redProgress > 0 {
                        HStack {
                            Spacer()
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [redBarColor, redBarColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * redProgress))
                        }
                    }
                }
            }
            .frame(height: 6)

            // Labels
            HStack {
                if greenProgress > 0 {
                    Text("Speaking")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                if redProgress > 0 {
                    Text(redProgress > 0.7 ? "Examiner taking over..." : "Silence detected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(redBarColor)
                }
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.1), value: greenProgress)
        .animation(.easeOut(duration: 0.1), value: redProgress)
        .onAppear {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                now = Date()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Computed Progress

    /// Green bar: fraction of max speaking time elapsed since listening started.
    private var greenProgress: CGFloat {
        guard let start = listeningStartTime else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1.0, CGFloat(elapsed / maxSpeakingDuration))
    }

    /// Red bar: fraction of silence timeout consumed since last speech.
    /// Returns 0 while the user is still speaking.
    private var redProgress: CGFloat {
        guard let lastSpeech = lastSpeechTime else { return 0 }
        let silenceElapsed = now.timeIntervalSince(lastSpeech)
        guard silenceElapsed > 0 else { return 0 }
        return min(1.0, CGFloat(silenceElapsed / silenceTimeout))
    }

    /// Red bar color intensifies as silence approaches the cutoff.
    private var redBarColor: Color {
        redProgress > 0.7 ? .red : .orange
    }
}
