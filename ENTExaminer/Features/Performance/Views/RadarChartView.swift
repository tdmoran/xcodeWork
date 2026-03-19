import SwiftUI

struct RadarChartView: View {
    let topicScores: [TopicScore]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 30
            let count = topicScores.count

            guard count >= 3 else { return }

            let angleStep = (2 * .pi) / Double(count)

            // Draw grid rings
            for level in [0.25, 0.5, 0.75, 1.0] {
                let r = radius * level
                var gridPath = Path()
                for i in 0..<count {
                    let angle = angleStep * Double(i) - .pi / 2
                    let point = CGPoint(
                        x: center.x + r * cos(angle),
                        y: center.y + r * sin(angle)
                    )
                    if i == 0 {
                        gridPath.move(to: point)
                    } else {
                        gridPath.addLine(to: point)
                    }
                }
                gridPath.closeSubpath()
                context.stroke(gridPath, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
            }

            // Draw axis lines
            for i in 0..<count {
                let angle = angleStep * Double(i) - .pi / 2
                let endPoint = CGPoint(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )
                var axisPath = Path()
                axisPath.move(to: center)
                axisPath.addLine(to: endPoint)
                context.stroke(axisPath, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            }

            // Draw data polygon
            var dataPath = Path()
            for i in 0..<count {
                let angle = angleStep * Double(i) - .pi / 2
                let value = topicScores[i].mastery
                let r = radius * max(0.05, value) // Minimum visible size
                let point = CGPoint(
                    x: center.x + r * cos(angle),
                    y: center.y + r * sin(angle)
                )
                if i == 0 {
                    dataPath.move(to: point)
                } else {
                    dataPath.addLine(to: point)
                }
            }
            dataPath.closeSubpath()

            context.fill(dataPath, with: .color(.accentColor.opacity(0.2)))
            context.stroke(dataPath, with: .color(.accentColor), lineWidth: 2)

            // Draw data points
            for i in 0..<count {
                let angle = angleStep * Double(i) - .pi / 2
                let value = topicScores[i].mastery
                let r = radius * max(0.05, value)
                let point = CGPoint(
                    x: center.x + r * cos(angle),
                    y: center.y + r * sin(angle)
                )
                let dotRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(.accentColor))
            }

            // Draw labels
            for i in 0..<count {
                let angle = angleStep * Double(i) - .pi / 2
                let labelRadius = radius + 20
                let labelPoint = CGPoint(
                    x: center.x + labelRadius * cos(angle),
                    y: center.y + labelRadius * sin(angle)
                )

                let name = topicScores[i].topicName
                let displayName = name.count > 12 ? String(name.prefix(11)) + "..." : name
                let text = Text(displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                context.draw(
                    context.resolve(text),
                    at: labelPoint,
                    anchor: .center
                )
            }
        }
        .animation(.spring(duration: 0.5), value: topicScores.map(\.mastery))
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let descriptions = topicScores.map { "\($0.topicName): \(Int($0.mastery * 100))%" }
        return "Topic mastery chart. " + descriptions.joined(separator: ". ")
    }
}
