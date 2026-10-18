#!/usr/bin/env swift
// Renders the 1024×1024 app icon (opaque RGB, no alpha) with CoreGraphics.
//
//   swift scripts/make-icon.swift [output.png]
//
// Default output: App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// Design: calm teal field, a white contraction trace (a small hump, then a
// bigger one) and a coral marker at the peak — the app's two phase colors.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first
    ?? "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no context")
}
// Top-left origin, like a design tool.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Background: soft vertical teal gradient with a faint warm glow up top.
let background = CGGradient(colorsSpace: space,
                            colors: [rgb(0x27A094), rgb(0x12655E)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(0xFFF1E4, 0.12), rgb(0xFFE9D6, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 180), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 180), endRadius: 700, options: [])

// The trace: baseline, small hump, baseline, big hump, baseline.
let baseline: CGFloat = 700
func hump(_ path: CGMutablePath, from x0: CGFloat, to x1: CGFloat, peak: CGFloat) {
    let mid = (x0 + x1) / 2, w = x1 - x0
    path.addCurve(to: CGPoint(x: mid, y: peak),
                  control1: CGPoint(x: x0 + w * 0.28, y: baseline),
                  control2: CGPoint(x: mid - w * 0.22, y: peak))
    path.addCurve(to: CGPoint(x: x1, y: baseline),
                  control1: CGPoint(x: mid + w * 0.22, y: peak),
                  control2: CGPoint(x: x1 - w * 0.28, y: baseline))
}
let trace = CGMutablePath()
trace.move(to: CGPoint(x: 140, y: baseline))
trace.addLine(to: CGPoint(x: 170, y: baseline))
hump(trace, from: 170, to: 430, peak: 545)
trace.addLine(to: CGPoint(x: 446, y: baseline))
let bigPeak = CGPoint(x: 668, y: 340)
hump(trace, from: 446, to: 890, peak: bigPeak.y)

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
// Soft shadow for depth, then the white line.
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: rgb(0x0A3D39, 0.45))
ctx.addPath(trace)
ctx.setStrokeColor(rgb(0xFFFFFF))
ctx.setLineWidth(58)
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Coral marker at the peak, ringed in white.
let radius: CGFloat = 62
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: bigPeak.x - radius - 16, y: bigPeak.y - radius - 16,
                           width: (radius + 16) * 2, height: (radius + 16) * 2))
ctx.setFillColor(rgb(0xE8634C))
ctx.fillEllipse(in: CGRect(x: bigPeak.x - radius, y: bigPeak.y - radius, width: radius * 2, height: radius * 2))

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not write \(output)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not finalize \(output)") }
print("Wrote \(output)")
