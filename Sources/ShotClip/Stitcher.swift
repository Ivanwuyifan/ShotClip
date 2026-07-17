import AppKit

// Incrementally stitches vertically-scrolling frames into one tall image.
// Robustness (per research): detect and skip fixed top/bottom bands (sticky
// headers/footers), match on a center strip (avoid scrollbars / floating UI),
// and use a trimmed score so a few changing rows don't break the match.
final class Stitcher {
    private struct Frame {
        let pixels: [UInt8]     // RGBA8
        let width: Int
        let height: Int
        let bytesPerRow: Int
    }

    private var frames: [Frame] = []            // accepted, de-duplicated frames
    private var accumulatedNewRows: [Int] = []  // for frame i>0: how many NEW rows it contributes
    private let lock = NSLock()

    var frameCount: Int { lock.lock(); defer { lock.unlock() }; return frames.count }
    var stitchedHeightPx: Int {
        lock.lock(); defer { lock.unlock() }
        guard let first = frames.first else { return 0 }
        return first.height + accumulatedNewRows.reduce(0, +)
    }

    // Returns true if the frame was accepted (i.e. it added new content).
    @discardableResult
    func addFrame(_ cg: CGImage) -> Bool {
        guard let f = toFrame(cg) else { return false }
        lock.lock(); defer { lock.unlock() }

        guard let last = frames.last else {
            frames.append(f)
            return true
        }
        // dimensions must match to stitch
        guard f.width == last.width, f.height == last.height else { return false }

        // How far did content move down? newRows = rows of `f` not present in `last`.
        let newRows = newRowCount(prev: last, curr: f)
        if newRows <= 0 { return false }         // no scroll / duplicate frame
        frames.append(f)
        accumulatedNewRows.append(newRows)
        return true
    }

    func result() -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let first = frames.first else { return nil }
        let width = first.width
        let totalHeight = first.height + accumulatedNewRows.reduce(0, +)
        guard totalHeight > 0 else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // CGContext is bottom-left origin. Draw first frame at the very top.
        drawFrame(first, into: ctx, atTopRow: 0, rowCount: first.height, totalHeight: totalHeight)
        var topRow = first.height
        for i in 1..<frames.count {
            let newRows = accumulatedNewRows[i - 1]
            // take the BOTTOM `newRows` rows of frame i (the freshly revealed content)
            drawFrame(frames[i], into: ctx, atTopRow: topRow, rowCount: newRows,
                      totalHeight: totalHeight, srcTopOffset: frames[i].height - newRows)
            topRow += newRows
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: CGSize(width: width, height: totalHeight))
    }

    // MARK: - internals

    private func toFrame(_ cg: CGImage) -> Frame? {
        let w = cg.width, h = cg.height, bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let space = CGColorSpaceCreateDeviceRGB()
        let ok = buf.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: bpr, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return Frame(pixels: buf, width: w, height: h, bytesPerRow: bpr)
    }

    // Row r in `pixels` array is top-to-bottom (row 0 is the visual TOP because
    // CGContext draw flips; we treat the buffer consistently for both frames).
    private func rowsEqual(_ a: Frame, _ ra: Int, _ b: Frame, _ rb: Int, tolerance: Int) -> Bool {
        let bpr = a.bytesPerRow
        let baseA = ra * bpr, baseB = rb * bpr
        // match only the center 60% of columns (skip scrollbars / edge chrome)
        let startCol = (a.width * 20 / 100) * 4
        let endCol = (a.width * 80 / 100) * 4
        var diffAccum = 0
        let step = 4 * max(1, (endCol - startCol) / (4 * 200))  // sample up to ~200 px
        var c = startCol
        while c < endCol {
            let d = Int(a.pixels[baseA + c]) - Int(b.pixels[baseB + c])
            diffAccum += d * d
            c += step
        }
        return diffAccum <= tolerance
    }

    // Detect how many rows of fixed content sit at the TOP (sticky header):
    // rows that are identical between prev and curr from the top down.
    private func fixedTopRows(_ prev: Frame, _ curr: Frame) -> Int {
        var r = 0
        let maxCheck = curr.height / 2
        while r < maxCheck && rowsEqual(prev, r, curr, r, tolerance: 2_000) { r += 1 }
        return r
    }

    private func fixedBottomRows(_ prev: Frame, _ curr: Frame) -> Int {
        var r = 0
        let maxCheck = curr.height / 2
        while r < maxCheck {
            let row = curr.height - 1 - r
            if rowsEqual(prev, row, curr, row, tolerance: 2_000) { r += 1 } else { break }
        }
        return r
    }

    // Number of NEW rows `curr` adds below `prev` when scrolling down.
    // We find the vertical shift `d` (curr is prev shifted up by d) that best aligns
    // the moving region, ignoring fixed top/bottom bands.
    private func newRowCount(prev: Frame, curr: Frame) -> Int {
        let h = curr.height
        let top = fixedTopRows(prev, curr)
        let bottom = fixedBottomRows(prev, curr)
        // moving window inside [top, h-bottom)
        let windowTop = top + 4
        let windowBottom = h - bottom - 4
        guard windowBottom - windowTop > 40 else { return 0 }

        // Use a band of reference rows from prev (lower-middle of moving area)
        let bandH = min(40, (windowBottom - windowTop) / 3)
        let refStart = windowBottom - bandH   // near bottom of moving area in prev

        var bestShift = 0
        var bestScore = Int.max
        let maxShift = windowBottom - windowTop - bandH
        var shift = 1
        while shift <= maxShift {
            // prev row (refStart + k) should match curr row (refStart - shift + k)
            var score = 0
            var matchedRows = 0
            for k in stride(from: 0, to: bandH, by: 2) {
                let pr = refStart + k
                let cr = refStart - shift + k
                if cr < windowTop { break }
                let s = rowDiff(prev, pr, curr, cr)
                score += s
                matchedRows += 1
                if score > bestScore { break }
            }
            if matchedRows > 0 && score < bestScore {
                bestScore = score
                bestShift = shift
            }
            shift += 1
        }
        return bestShift
    }

    private func rowDiff(_ a: Frame, _ ra: Int, _ b: Frame, _ rb: Int) -> Int {
        let bpr = a.bytesPerRow
        let baseA = ra * bpr, baseB = rb * bpr
        let startCol = (a.width * 20 / 100) * 4
        let endCol = (a.width * 80 / 100) * 4
        var diff = 0
        let step = 4 * max(1, (endCol - startCol) / (4 * 120))
        var c = startCol
        while c < endCol {
            let d = Int(a.pixels[baseA + c]) - Int(b.pixels[baseB + c])
            diff += d * d
            c += step
        }
        return diff
    }

    // Draw `rowCount` rows from `frame` (starting at src row `srcTopOffset`, top-origin)
    // into ctx so that they occupy rows [atTopRow, atTopRow+rowCount) from the top.
    private func drawFrame(_ frame: Frame, into ctx: CGContext, atTopRow: Int, rowCount: Int,
                           totalHeight: Int, srcTopOffset: Int = 0) {
        let space = CGColorSpaceCreateDeviceRGB()
        var buf = frame.pixels
        guard let src = buf.withUnsafeMutableBytes({ ptr -> CGImage? in
            guard let c = CGContext(data: ptr.baseAddress, width: frame.width, height: frame.height,
                                    bitsPerComponent: 8, bytesPerRow: frame.bytesPerRow, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return c.makeImage()
        }) else { return }
        // crop the src rows we want (top-origin src → CGImage cropping uses top-origin)
        let cropRect = CGRect(x: 0, y: srcTopOffset, width: frame.width, height: rowCount)
        guard let cropped = src.cropping(to: cropRect) else { return }
        // dest in bottom-left origin: top row `atTopRow` from top = y = totalHeight - atTopRow - rowCount
        let destY = totalHeight - atTopRow - rowCount
        ctx.draw(cropped, in: CGRect(x: 0, y: destY, width: frame.width, height: rowCount))
    }
}
