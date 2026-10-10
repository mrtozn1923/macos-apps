import CoreGraphics
import Foundation

/// Builds one tall image from successive captures of the same region while the user scrolls down.
/// Consecutive frames are aligned by comparing per-row fingerprints; rows that stay fixed at the
/// top/bottom (sticky headers, footers) are excluded from matching and the footer is appended once at the end.
final class ImageStitcher {
    enum AppendResult {
        case first
        case appended(rows: Int)
        case unchanged
        case noMatch
        case full
    }

    private struct Frame {
        let height: Int
        let pixels: [UInt8]
        let hashes: [UInt64]
        let uniform: [Bool]
    }

    let maxHeight: Int
    private(set) var width: Int = 0
    private var bytesPerRow: Int { width * 4 }
    private var output: [UInt8] = []
    private var outputRows: Int = 0
    private var previous: Frame?
    private var footer: Int?

    var height: Int { outputRows + (footer ?? 0) }

    init(maxHeight: Int = 30_000) {
        self.maxHeight = maxHeight
    }

    func append(_ image: CGImage) -> AppendResult {
        guard let frame = makeFrame(image) else { return .noMatch }

        guard let previous else {
            width = image.width
            output = frame.pixels
            outputRows = frame.height
            self.previous = frame
            return .first
        }
        guard frame.height == previous.height, frame.hashes.count == previous.hashes.count else { return .noMatch }
        if frame.hashes == previous.hashes { return .unchanged }
        if outputRows >= maxHeight { return .full }

        let rows: Int = frame.height
        let header: Int = stickyCount(previous, frame, fromTop: true)
        if footer == nil {
            let detected: Int = stickyCount(previous, frame, fromTop: false)
            footer = detected
            // The first frame was appended whole; its footer belongs at the very end instead.
            outputRows -= detected
            output.removeLast(detected * bytesPerRow)
        }
        let footerRows: Int = footer ?? 0
        let scrollable: Int = rows - header - footerRows
        guard scrollable > 8, let offset = bestOffset(previous, frame, header: header, footer: footerRows) else {
            return .noMatch
        }

        let newRows: Int = min(offset, maxHeight - outputRows)
        let start: Int = (rows - footerRows - offset) * bytesPerRow
        output.append(contentsOf: frame.pixels[start..<(start + newRows * bytesPerRow)])
        outputRows += newRows
        self.previous = frame
        return .appended(rows: newRows)
    }

    func result() -> CGImage? {
        guard let previous, width > 0 else { return nil }
        var pixels: [UInt8] = output
        let footerRows: Int = footer ?? 0
        if footerRows > 0 {
            let start: Int = (previous.height - footerRows) * bytesPerRow
            pixels.append(contentsOf: previous.pixels[start..<(previous.height * bytesPerRow)])
        }
        let totalRows: Int = pixels.count / bytesPerRow
        guard totalRows > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: totalRows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Matching

    /// Rows identical at the same position in both frames, counted from the top or bottom.
    /// Runs made only of blank rows are ignored, since blank content would match anyway.
    private func stickyCount(_ a: Frame, _ b: Frame, fromTop: Bool) -> Int {
        let rows: Int = a.height
        var count: Int = 0
        var sawContent: Bool = false
        while count < rows / 3 {
            let y: Int = fromTop ? count : rows - 1 - count
            guard a.hashes[y] == b.hashes[y] else { break }
            if !a.uniform[y] { sawContent = true }
            count += 1
        }
        return sawContent ? count : 0
    }

    /// Finds how many rows the content moved up between `a` and `b`.
    private func bestOffset(_ a: Frame, _ b: Frame, header: Int, footer: Int) -> Int? {
        let bottom: Int = a.height - footer
        var best: (offset: Int, score: Double)?
        for offset in 1..<(bottom - header - 4) {
            let compareCount: Int = bottom - header - offset
            var contentRows: Int = 0
            var mismatches: Int = 0
            let allowed: Int = max(1, compareCount / 50)
            var y: Int = header
            while y < bottom - offset {
                if b.hashes[y] != a.hashes[y + offset] {
                    mismatches += 1
                    if mismatches > allowed { break }
                } else if !b.uniform[y] {
                    contentRows += 1
                }
                y += 1
            }
            guard mismatches <= allowed, contentRows >= 3 else { continue }
            let score: Double = Double(contentRows) / Double(compareCount) - Double(mismatches) / Double(compareCount)
            if best == nil || score > best!.score + 0.001 {
                best = (offset, score)
            }
            // A large, clean overlap is unambiguous; stop early.
            if mismatches == 0 && compareCount > a.height / 3 && contentRows > compareCount / 4 { break }
        }
        return best?.offset
    }

    private func makeFrame(_ image: CGImage) -> Frame? {
        let w: Int = image.width
        let h: Int = image.height
        guard w > 0, h > 0, previous == nil || w == width else { return nil }
        var pixels: [UInt8] = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        var hashes: [UInt64] = [UInt64](repeating: 0, count: h)
        var uniform: [Bool] = [Bool](repeating: true, count: h)
        let stride: Int = max(1, w / 400)
        for y in 0..<h {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            let rowStart: Int = y * w * 4
            // Drop the low bits so tiny rendering noise does not break matches.
            let first: UInt32 = quantized(pixels, rowStart)
            var isUniform: Bool = true
            var x: Int = 0
            while x < w {
                let value: UInt32 = quantized(pixels, rowStart + x * 4)
                if value != first { isUniform = false }
                hash = (hash ^ UInt64(value)) &* 0x100_0000_01b3
                x += stride
            }
            hashes[y] = hash
            uniform[y] = isUniform
        }
        return Frame(height: h, pixels: pixels, hashes: hashes, uniform: uniform)
    }

    @inline(__always)
    private func quantized(_ pixels: [UInt8], _ index: Int) -> UInt32 {
        (UInt32(pixels[index] >> 3) << 10) | (UInt32(pixels[index + 1] >> 3) << 5) | UInt32(pixels[index + 2] >> 3)
    }
}
