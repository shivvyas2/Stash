//
//  AppIcon.swift
//  Stash
//
//  Icons for the Mac apps Stash exports. A raw portrait cover squashed into
//  a Finder icon looks broken, so the cover sits as box art on a rounded
//  tile made from a blurred copy of itself, on Apple's icon grid.
//

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum AppIcon {
    private static let canvas: CGFloat = 1024
    /// Apple's macOS grid: an 824pt tile with a 185pt corner radius, centred on 1024
    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let tileRadius: CGFloat = 185

    /// Renders the icon at 1024×1024. Works for portrait covers and square exe icons alike.
    static func render(from artwork: NSImage) -> CGImage? {
        guard let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

        // Soft shadow under the tile, like Apple's own icons
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(tilePath)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // The tile is the artwork itself, blurred and dimmed
        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        let backdrop = blurred(source) ?? source
        context.draw(backdrop, in: aspectFill(size(of: backdrop), in: tile.insetBy(dx: -40, dy: -40)))
        context.setFillColor(CGColor(gray: 0, alpha: 0.3))
        context.fill(tile)
        context.restoreGState()

        // The whole artwork on top, like a game box
        let box = aspectFit(size(of: source), in: tile.insetBy(dx: 84, dy: 64)).integral
        let boxPath = CGPath(roundedRect: box, cornerWidth: 22, cornerHeight: 22, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.55))
        context.addPath(boxPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(boxPath)
        context.clip()
        context.draw(source, in: box)
        context.restoreGState()

        // A faint rim keeps dark covers from melting into a dark Dock
        context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1, dy: 1), cornerWidth: tileRadius - 1,
                               cornerHeight: tileRadius - 1, transform: nil))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
        context.setLineWidth(2)
        context.strokePath()

        return context.makeImage()
    }

    /// Writes a multi-size .icns, so Finder and the Dock stay sharp at every size
    static func writeICNS(_ image: CGImage, to url: URL) throws {
        let sizes = [16, 32, 128, 256, 512]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.icns.identifier as CFString,
                                                                sizes.count * 2, nil)
        else { throw StashError("The app icon couldn't be created.") }
        // Each size twice: 72 dpi for standard displays, 144 dpi marks the @2x Retina copy
        for size in sizes {
            for (factor, dpi) in [(1, 72), (2, 144)] {
                guard let scaled = scale(image, to: size * factor) else { continue }
                let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
                CGImageDestinationAddImage(destination, scaled, properties)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw StashError("The app icon couldn't be saved.") }
    }

    // MARK: Drawing helpers

    private static func size(of image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        return centred(CGSize(width: size.width * scale, height: size.height * scale), in: rect)
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        return centred(CGSize(width: size.width * scale, height: size.height * scale), in: rect)
    }

    private static func centred(_ size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(image.width, image.height)) / 25)
            .cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }

    private static func scale(_ image: CGImage, to size: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
