import CoreVideo
import UIKit

class ChromaKeyFilter {
    var keyColorR: Float = 0.0
    var keyColorG: Float = 1.0
    var keyColorB: Float = 0.0
    var tolerance: Float = 0.3

    func apply(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &out)
        guard let out else { return pixelBuffer }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(out, [])
        let src = CVPixelBufferGetBaseAddress(pixelBuffer).assumingMemoryBound(to: UInt8.self)
        let dst = CVPixelBufferGetBaseAddress(out).assumingMemoryBound(to: UInt8.self)
        let srcRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstRow = CVPixelBufferGetBytesPerRow(out)

        for y in 0..<h {
            let sOff = y * srcRow
            let dOff = y * dstRow
            for x in 0..<w {
                let px = sOff + x * 4
                let r = Float(src[px]) / 255.0
                let g = Float(src[px+1]) / 255.0
                let b = Float(src[px+2]) / 255.0
                let dr = r - keyColorR
                let dg = g - keyColorG
                let db = b - keyColorB
                let dist = sqrt(dr*dr + dg*dg + db*db)
                if dist < tolerance {
                    dst[dOff + x*4 + 0] = 0
                    dst[dOff + x*4 + 1] = 0
                    dst[dOff + x*4 + 2] = 0
                    dst[dOff + x*4 + 3] = 255
                } else {
                    dst[dOff + x*4 + 0] = src[px]
                    dst[dOff + x*4 + 1] = src[px+1]
                    dst[dOff + x*4 + 2] = src[px+2]
                    dst[dOff + x*4 + 3] = 255
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(out, [])
        return out
    }
}
