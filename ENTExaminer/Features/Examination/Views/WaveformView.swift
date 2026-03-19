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
