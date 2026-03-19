import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let color: Color
    let accentColor: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color, accentColor],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: levels[index])
            }
        }
        .opacity(isActive ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(levels[index])
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 40

        if isActive {
            return max(minHeight, level * maxHeight)
        } else {
            // Gentle breathing animation when idle
            return minHeight + 2
        }
    }
}

// MARK: - Previews

#if DEBUG
struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WaveformView(
                levels: (0..<32).map { _ in Float.random(in: 0.1...0.9) },
                color: .blue,
                accentColor: .cyan,
                isActive: true
            )
            .frame(height: 48)
            .padding()
            .previewDisplayName("Active Waveform")

            WaveformView(
                levels: Array(repeating: Float(0), count: 32),
                color: .green,
                accentColor: .mint,
                isActive: false
            )
            .frame(height: 48)
            .padding()
            .previewDisplayName("Idle Waveform")
        }
    }
}
#endif
