#!/usr/bin/env swift

import AppKit
import CoreGraphics

// MARK: - VocalCards Icon Generator
// Design: Clean blue gradient background with white microphone and waveform bars.
// Simple, modern, reads well at all sizes.

struct IconGenerator {

    // Blue gradient colors
    static let gradientTopColor = NSColor(
        calibratedRed: 0.20, green: 0.50, blue: 0.95, alpha: 1.0
    )
    static let gradientBottomColor = NSColor(
        calibratedRed: 0.10, green: 0.30, blue: 0.80, alpha: 1.0
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

        // Draw blue gradient background (bottom-left to top-right for depth)
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
                end: CGPoint(x: s * 0.4, y: s),
                options: []
            )
        }

        // --- Subtle lighter overlay at top for polish ---
        let overlayColors = [
            NSColor(white: 1.0, alpha: 0.12).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray
        if let overlayGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: overlayColors,
            locations: [0.0, 1.0]
        ) {
            context.drawLinearGradient(
                overlayGrad,
                start: CGPoint(x: s * 0.5, y: s),
                end: CGPoint(x: s * 0.5, y: s * 0.4),
                options: []
            )
        }

        // --- Microphone (white) ---
        drawMicrophone(in: context, size: s)

        // --- Waveform bars flanking the microphone ---
        drawWaveformBars(in: context, size: s)

        // --- Subtle inner highlight border ---
        context.saveGState()
        let innerRect = rect.insetBy(dx: s * 0.005, dy: s * 0.005)
        let innerRadius = cornerRadius - s * 0.005
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)
        NSColor(white: 1.0, alpha: 0.08).setStroke()
        innerPath.lineWidth = s * 0.008
        innerPath.stroke()
        context.restoreGState()

        context.restoreGState()
        image.unlockFocus()

        return image
    }

    static func drawMicrophone(in context: CGContext, size s: CGFloat) {
        context.saveGState()

        let white = NSColor.white

        let centerX = s * 0.5
        // Position microphone in upper-center area
        let micCenterY = s * 0.58

        // Microphone capsule (rounded rectangle / pill shape)
        let micW = s * 0.13
        let micH = s * 0.20
        let micX = centerX - micW / 2.0
        let micY = micCenterY - micH * 0.3
        let micRect = CGRect(x: micX, y: micY, width: micW, height: micH)
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW / 2.0, yRadius: micW / 2.0)
        white.setFill()
        micPath.fill()

        // Cradle arc (U-shape around bottom of capsule)
        let arcCenterY = micY + s * 0.01
        let arcRadius = s * 0.10
        let arcPath = NSBezierPath()
        arcPath.appendArc(
            withCenter: CGPoint(x: centerX, y: arcCenterY),
            radius: arcRadius,
            startAngle: 0,
            endAngle: 180,
            clockwise: true
        )
        white.setStroke()
        arcPath.lineWidth = s * 0.025
        arcPath.lineCapStyle = .round
        arcPath.stroke()

        // Stand vertical line
        let standTop = arcCenterY - arcRadius
        let standBottom = standTop - s * 0.10
        let standPath = NSBezierPath()
        standPath.move(to: CGPoint(x: centerX, y: standTop))
        standPath.line(to: CGPoint(x: centerX, y: standBottom))
        white.setStroke()
        standPath.lineWidth = s * 0.025
        standPath.lineCapStyle = .round
        standPath.stroke()

        // Stand base (horizontal line)
        let baseW = s * 0.12
        let basePath = NSBezierPath()
        basePath.move(to: CGPoint(x: centerX - baseW / 2.0, y: standBottom))
        basePath.line(to: CGPoint(x: centerX + baseW / 2.0, y: standBottom))
        white.setStroke()
        basePath.lineWidth = s * 0.025
        basePath.lineCapStyle = .round
        basePath.stroke()

        context.restoreGState()
    }

    static func drawWaveformBars(in context: CGContext, size s: CGFloat) {
        context.saveGState()

        let white = NSColor(white: 1.0, alpha: 0.85)
        let barWidth = s * 0.032
        let barSpacing = s * 0.025
        let centerY = s * 0.55

        // Bars on the LEFT side of the microphone
        let leftBarHeights: [CGFloat] = [0.06, 0.12, 0.18]
        let micLeftEdge = s * 0.5 - s * 0.13 / 2.0
        let leftStartX = micLeftEdge - s * 0.04

        for i in 0..<leftBarHeights.count {
            let h = leftBarHeights[i] * s
            let x = leftStartX - CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - h / 2.0
            let barRect = CGRect(x: x - barWidth, y: y, width: barWidth, height: h)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2.0, yRadius: barWidth / 2.0)
            white.setFill()
            barPath.fill()
        }

        // Bars on the RIGHT side of the microphone (mirrored)
        let rightBarHeights: [CGFloat] = [0.06, 0.12, 0.18]
        let micRightEdge = s * 0.5 + s * 0.13 / 2.0
        let rightStartX = micRightEdge + s * 0.04

        for i in 0..<rightBarHeights.count {
            let h = rightBarHeights[i] * s
            let x = rightStartX + CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - h / 2.0
            let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2.0, yRadius: barWidth / 2.0)
            white.setFill()
            barPath.fill()
        }

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

print("Generating VocalCards app icons (blue + white design)...")
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
