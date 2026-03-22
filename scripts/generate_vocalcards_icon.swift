#!/usr/bin/env swift

import AppKit
import CoreGraphics

// MARK: - VocalCards Icon Generator
// Design: Deep teal/navy gradient background with a bold white card
// featuring a vibrant coral-orange waveform. Clean, modern, distinctive.

struct IconGenerator {

    // Background gradient: deep navy-teal
    static let gradientTopColor = NSColor(
        calibratedRed: 0.05, green: 0.12, blue: 0.22, alpha: 1.0
    )
    static let gradientBottomColor = NSColor(
        calibratedRed: 0.08, green: 0.38, blue: 0.42, alpha: 1.0
    )

    // Accent: vibrant coral-orange
    static let accentColor = NSColor(
        calibratedRed: 0.96, green: 0.38, blue: 0.27, alpha: 1.0
    )
    static let accentColorDeep = NSColor(
        calibratedRed: 0.85, green: 0.25, blue: 0.18, alpha: 1.0
    )

    static func generateIcon(size: Int) -> NSImage {
        let cgSize = CGSize(width: size, height: size)
        let image = NSImage(size: cgSize)

        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let rect = CGRect(origin: .zero, size: cgSize)
        let s = CGFloat(size)

        // --- Rounded square background ---
        let cornerRadius = s * 0.22
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        context.saveGState()
        bgPath.addClip()

        // Draw gradient background
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            gradientBottomColor.cgColor,
            gradientTopColor.cgColor
        ] as CFArray

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: gradientColors,
            locations: [0.0, 1.0]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: s * 0.3, y: s),
                options: []
            )
        }

        // --- Card shape (white, bold, centered) ---
        drawCard(in: context, size: s)

        // --- Waveform bars on the card ---
        drawWaveform(in: context, size: s)

        // --- Small microphone icon below waveform ---
        drawMicIcon(in: context, size: s)

        // --- Subtle inner border ---
        context.saveGState()
        let innerRect = rect.insetBy(dx: s * 0.006, dy: s * 0.006)
        let innerRadius = cornerRadius - s * 0.006
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)
        NSColor(white: 1.0, alpha: 0.05).setStroke()
        innerPath.lineWidth = s * 0.01
        innerPath.stroke()
        context.restoreGState()

        context.restoreGState()
        image.unlockFocus()

        return image
    }

    static func drawCard(in context: CGContext, size s: CGFloat) {
        context.saveGState()

        let cardWidth = s * 0.54
        let cardHeight = s * 0.58
        let cardX = (s - cardWidth) / 2.0
        let cardY = (s - cardHeight) / 2.0 + s * 0.02
        let cardCorner = s * 0.06

        // Shadow
        context.setShadow(
            offset: CGSize(width: 0, height: -s * 0.015),
            blur: s * 0.07,
            color: NSColor(white: 0.0, alpha: 0.4).cgColor
        )

        let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardCorner, yRadius: cardCorner)
        NSColor.white.setFill()
        cardPath.fill()

        context.setShadow(offset: .zero, blur: 0, color: nil)

        // Subtle lined-card texture
        NSColor(white: 0.0, alpha: 0.04).setStroke()
        let lineStartY = cardY + s * 0.07
        let lineEndY = cardY + cardHeight - s * 0.07
        let lineStep = s * 0.048
        var ly = lineStartY
        while ly < lineEndY {
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: cardX + s * 0.045, y: ly))
            linePath.line(to: CGPoint(x: cardX + cardWidth - s * 0.045, y: ly))
            linePath.lineWidth = s * 0.0025
            linePath.stroke()
            ly += lineStep
        }

        context.restoreGState()
    }

    static func drawWaveform(in context: CGContext, size s: CGFloat) {
        context.saveGState()

        let barCount = 7
        let barWidth = s * 0.038
        let barSpacing = s * 0.022
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (s - totalWidth) / 2.0
        let centerY = s * 0.54

        // Heights (symmetric, taller in middle - audio waveform feel)
        let barHeights: [CGFloat] = [0.045, 0.09, 0.14, 0.19, 0.14, 0.09, 0.045]

        for i in 0..<barCount {
            let h = barHeights[i] * s
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - h / 2.0
            let barRadius = barWidth / 2.0
            let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barRadius, yRadius: barRadius)

            // Gradient fill
            context.saveGState()
            barPath.addClip()
            let barColors = [
                accentColorDeep.cgColor,
                accentColor.cgColor
            ] as CFArray
            if let barGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: barColors,
                locations: [0.0, 1.0]
            ) {
                context.drawLinearGradient(
                    barGrad,
                    start: CGPoint(x: x, y: y),
                    end: CGPoint(x: x, y: y + h),
                    options: []
                )
            }
            context.restoreGState()
        }

        context.restoreGState()
    }

    static func drawMicIcon(in context: CGContext, size s: CGFloat) {
        context.saveGState()

        let centerX = s * 0.5
        let baseY = s * 0.54 - s * 0.19 / 2.0 - s * 0.02 // just below waveform

        // Microphone body (rounded rectangle)
        let micW = s * 0.032
        let micH = s * 0.048
        let micX = centerX - micW / 2.0
        let micY = baseY - micH - s * 0.025
        let micRect = CGRect(x: micX, y: micY, width: micW, height: micH)
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW / 2.0, yRadius: micW / 2.0)
        accentColor.withAlphaComponent(0.75).setFill()
        micPath.fill()

        // Mic stand arc
        let arcCenterY = micY
        let arcRadius = s * 0.032
        let arcPath = NSBezierPath()
        // Draw a U-shape arc below the mic body
        arcPath.appendArc(
            withCenter: CGPoint(x: centerX, y: arcCenterY),
            radius: arcRadius,
            startAngle: 0,
            endAngle: 180,
            clockwise: true
        )
        accentColor.withAlphaComponent(0.55).setStroke()
        arcPath.lineWidth = s * 0.007
        arcPath.stroke()

        // Mic stand vertical line
        let standPath = NSBezierPath()
        standPath.move(to: CGPoint(x: centerX, y: arcCenterY - arcRadius))
        standPath.line(to: CGPoint(x: centerX, y: arcCenterY - arcRadius - s * 0.025))
        accentColor.withAlphaComponent(0.55).setStroke()
        standPath.lineWidth = s * 0.007
        standPath.stroke()

        // Stand base (small horizontal line)
        let basePath = NSBezierPath()
        let baseW = s * 0.03
        let standBottom = arcCenterY - arcRadius - s * 0.025
        basePath.move(to: CGPoint(x: centerX - baseW / 2.0, y: standBottom))
        basePath.line(to: CGPoint(x: centerX + baseW / 2.0, y: standBottom))
        accentColor.withAlphaComponent(0.55).setStroke()
        basePath.lineWidth = s * 0.007
        basePath.lineCapStyle = .round
        basePath.stroke()

        context.restoreGState()
    }

    static func savePNG(image: NSImage, size: Int, to path: String) -> Bool {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("ERROR: Failed to create PNG data for \(path)")
            return false
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            let fileSize = pngData.count
            print("OK: \(path) (\(fileSize) bytes, \(size)x\(size)px)")
            return true
        } catch {
            print("ERROR: Failed to write \(path): \(error)")
            return false
        }
    }
}

// MARK: - Main

let outputDir = "/Users/tommoran/Dropbox/Mac (2)/Desktop/ExaminerAndMobile/ENTExaminer/Resources/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let fileManager = FileManager.default
if !fileManager.fileExists(atPath: outputDir) {
    try! fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
}

print("Generating VocalCards app icons...")
print("Output: \(outputDir)\n")

var allSucceeded = true

for size in sizes {
    let icon = IconGenerator.generateIcon(size: size)
    let filename = "icon_\(size).png"
    let path = "\(outputDir)/\(filename)"

    if !IconGenerator.savePNG(image: icon, size: size, to: path) {
        allSucceeded = false
    }
}

print("")
if allSucceeded {
    print("All icons generated successfully!")
} else {
    print("Some icons failed to generate.")
    exit(1)
}
