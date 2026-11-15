import AppKit
import CoreGraphics
import SwiftUI

/// Resolves the installed app's icon and derives a readable header palette from it.
final class ClipboardSourceAppearance {
    let name: String
    let icon: NSImage
    let headerColor: Color?
    let headerInk: Color?

    private static let cache: NSCache<NSString, ClipboardSourceAppearance> = {
        let cache = NSCache<NSString, ClipboardSourceAppearance>()
        cache.countLimit = 128
        return cache
    }()

    static func resolve(for identifier: String?) -> ClipboardSourceAppearance? {
        guard let identifier else { return nil }
        let key = identifier as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { return nil }
        let appearance = ClipboardSourceAppearance(applicationURL: url)
        cache.setObject(appearance, forKey: key)
        return appearance
    }

    static func displayName(for applicationURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: applicationURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private init(applicationURL: URL) {
        name = Self.displayName(for: applicationURL)
        let original = NSWorkspace.shared.icon(forFile: applicationURL.path)
        let sample = Self.sampleIcon(original)
        icon = sample?.icon ?? original
        headerColor = sample?.color?.color
        headerInk = sample?.color?.ink
    }

    private struct RGB {
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

        var ink: Color {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045
                    ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
            return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
        }
    }

    private struct ColorBucket {
        var weight = 0.0
        var sum = RGB()

        mutating func add(_ rgb: RGB, weight: Double) {
            self.weight += weight
            sum.red += rgb.red * weight
            sum.green += rgb.green * weight
            sum.blue += rgb.blue * weight
        }

        var average: RGB? {
            guard weight > 0 else { return nil }
            return RGB(red: sum.red / weight, green: sum.green / weight, blue: sum.blue / weight)
        }
    }

    private static func sampleIcon(_ icon: NSImage) -> (icon: NSImage, color: RGB?)? {
        let size = 96
        var proposedRect = CGRect(x: 0, y: 0, width: size, height: size)
        guard
            let image = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        let scale = CGFloat(size) / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2,
                width: width, height: height)
        )

        // Color buckets group nearby hues so the icon's artwork can stand out from neutral padding.
        var hues = Array(repeating: ColorBucket(), count: 18)
        var neutrals = Array(repeating: ColorBucket(), count: 5)
        var bounds = CGRect.null
        var opaquePixels = 0
        for y in 0..<size {
            for x in 0..<size {
                let offset = y * context.bytesPerRow + x * 4
                let alpha = pixels[offset + 3]
                if alpha >= 64 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
                guard alpha >= 230 else { continue }
                opaquePixels += 1
                let rgb = RGB(
                    red: Double(pixels[offset]) / Double(alpha),
                    green: Double(pixels[offset + 1]) / Double(alpha),
                    blue: Double(pixels[offset + 2]) / Double(alpha)
                )
                let brightest = max(rgb.red, rgb.green, rgb.blue)
                let chroma = brightest - min(rgb.red, rgb.green, rgb.blue)
                if chroma >= 0.16 {
                    let hue: Double
                    if brightest == rgb.red {
                        hue = (rgb.green - rgb.blue) / chroma
                    } else if brightest == rgb.green {
                        hue = 2 + (rgb.blue - rgb.red) / chroma
                    } else {
                        hue = 4 + (rgb.red - rgb.green) / chroma
                    }
                    let bucket = (Int((hue * 3).rounded()) + hues.count) % hues.count
                    hues[bucket].add(rgb, weight: chroma)
                } else {
                    let bucket = Int((brightest * Double(neutrals.count - 1)).rounded())
                    neutrals[bucket].add(rgb, weight: 1)
                }
            }
        }

        let dominantHue = hues.max { $0.weight < $1.weight }
        let color =
            if let dominantHue, dominantHue.weight >= Double(opaquePixels) * 0.04 {
                dominantHue.average
            } else {
                neutrals.max { $0.weight < $1.weight }?.average ?? dominantHue?.average
            }

        guard !bounds.isNull,
            let cropped = context.makeImage()?.cropping(
                to: bounds.insetBy(dx: -1, dy: -1).intersection(
                    CGRect(x: 0, y: 0, width: size, height: size)))
        else { return (icon, color) }
        return (
            NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)),
            color
        )
    }
}
