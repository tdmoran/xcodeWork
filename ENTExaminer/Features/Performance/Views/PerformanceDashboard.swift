import SwiftUI
import Charts

struct PerformanceDashboard: View {
    let performance: PerformanceSnapshot
    let topicScores: [TopicScore]
    let turnScores: [TurnScore]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall score gauge
                overallScoreGauge

                // Radar chart
                if !topicScores.isEmpty {
                    radarChartSection
                }

                // Confidence timeline
                if !turnScores.isEmpty {
                    confidenceTimeline
                }

                // Stats
                statsRow
            }
            .padding()
        }
    }

    // MARK: - Overall Score

    private var overallScoreGauge: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: performance.overallScore)
                    .stroke(
                        scoreColor(performance.overallScore),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: performance.overallScore)

                Text("\(Int(performance.overallScore * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Text("Overall Score")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Radar Chart

    private var radarChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topic Mastery")
                .font(.headline)

            RadarChartView(topicScores: topicScores)
                .frame(height: 220)
                .padding(.horizontal)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Confidence Timeline

    private var confidenceTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score Trend")
                .font(.headline)

            Chart(turnScores) { turn in
                LineMark(
                    x: .value("Question", turn.questionIndex),
                    y: .value("Score", turn.score * 100)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Question", turn.questionIndex),
                    y: .value("Score", turn.score * 100)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Question", turn.questionIndex),
                    y: .value("Score", turn.score * 100)
                )
                .foregroundStyle(scoreColor(turn.score))
                .symbolSize(40)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("Q\(intValue)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 16) {
            statItem(
                label: "Questions",
                value: "\(performance.turnsCompleted)",
                icon: "questionmark.circle"
            )
            statItem(
                label: "Streak",
                value: "\(performance.streak)",
                icon: "flame.fill"
            )
            statItem(
                label: "Remaining",
                value: "\(performance.turnsRemaining)",
                icon: "hourglass"
            )
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return .green
        case 0.6..<0.75: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Previews

#if DEBUG
struct PerformanceDashboard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PerformanceDashboard(
                performance: PreviewData.samplePerformance,
                topicScores: PreviewData.sampleTopicScores,
                turnScores: PreviewData.sampleTurnScores
            )
            .frame(width: 380, height: 700)
            .previewDisplayName("Performance Dashboard")

            PerformanceDashboard(
                performance: .empty,
                topicScores: [],
                turnScores: []
            )
            .frame(width: 380, height: 400)
            .previewDisplayName("Empty Dashboard")
        }
    }
}
#endif
