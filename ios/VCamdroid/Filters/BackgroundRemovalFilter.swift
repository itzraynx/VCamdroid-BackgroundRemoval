import CoreImage
import UIKit
import Accelerate

class BackgroundRemovalFilter {
    enum Mode: Int {
        case remove = 0
        case blur = 1
    }

    private let segmenter = SelfieSegmenterHelper.shared
    var mode: Mode = .remove

    func apply(pixelBuffer: CVPixelBuffer, existingMask: inout Data?, frameCount: inout Int) -> CVPixelBuffer {
        guard let downscaled = downscale(pixelBuffer, to: 256) else { return pixelBuffer }

        frameCount += 1
        if frameCount % 2 == 0 {
            existingMask = segmenter.segment(ciImage: CIImage(cvPixelBuffer: downscaled))
        }

        guard let mask = existingMask else { return pixelBuffer }
        return composite(pixelBuffer, mask: mask, maskSize: 256)
    }

    private func downscale(_ pixelBuffer: CVPixelBuffer, to size: Int) -> CVPixelBuffer? {
        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return nil
        }
        let srcRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var srcBuf = vImage_Buffer(data: srcBase, height: vImagePixelCount(srcH),
                                    width: vImagePixelCount(srcW), rowBytes: srcRow)

        var dstData = Data(count: size * size * 4)
        var dstBuf = vImage_Buffer(data: &dstData, height: vImagePixelCount(size),
                                    width: vImagePixelCount(size), rowBytes: size * 4)
        vImageScale_ARGB8888(&srcBuf, &dstBuf, nil, vImage_Flags(kvImageHighQualityResampling))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &out)
        guard let out else { return nil }

        CVPixelBufferLockBaseAddress(out, [])
        let dstPtr = CVPixelBufferGetBaseAddress(out)
        memcpy(dstPtr, (dstData as NSData).bytes, size * size * 4)
        CVPixelBufferUnlockBaseAddress(out, [])
        return out
    }

    private func composite(_ pixelBuffer: CVPixelBuffer, mask: Data, maskSize: Int) -> CVPixelBuffer {
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

        mask.withUnsafeBytes { mPtr in
            guard let mb = mPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<h {
                let my = min(y * maskSize / h, maskSize - 1)
                let mOff = my * maskSize
                let sOff = y * srcRow
                let dOff = y * dstRow
                for x in 0..<w {
                    let mx = min(x * maskSize / w, maskSize - 1)
                    let mv = Float(mb[mOff + mx]) / 255.0
                    let px = sOff + x * 4
                    if mv > 0.5 {
                        dst[dOff + x*4 + 0] = src[px + 0]
                        dst[dOff + x*4 + 1] = src[px + 1]
                        dst[dOff + x*4 + 2] = src[px + 2]
                        dst[dOff + x*4 + 3] = 255
                    } else if mode == .remove {
                        dst[dOff + x*4 + 0] = 0
                        dst[dOff + x*4 + 1] = 0
                        dst[dOff + x*4 + 2] = 0
                        dst[dOff + x*4 + 3] = 255
                    } else {
                        var r = 0, g = 0, b = 0, c = 0
                        for dy in -2...2 {
                            for dx in -2...2 {
                                let nx = max(0, min(x + dx, w - 1))
                                let ny = max(0, min(y + dy, h - 1))
                                let np = ny * srcRow + nx * 4
                                r += Int(src[np])
                                g += Int(src[np+1])
                                b += Int(src[np+2])
                                c += 1
                            }
                        }
                        dst[dOff + x*4 + 0] = UInt8(r / c)
                        dst[dOff + x*4 + 1] = UInt8(g / c)
                        dst[dOff + x*4 + 2] = UInt8(b / c)
                        dst[dOff + x*4 + 3] = 255
                    }
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(out, [])
        return out
    }
}
