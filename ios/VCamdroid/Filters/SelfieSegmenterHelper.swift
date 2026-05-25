import MediaPipeTasksVision
import CoreImage
import UIKit

class SelfieSegmenterHelper {
    static let shared = SelfieSegmenterHelper()

    private var segmenter: ImageSegmenter?
    private var initialized = false
    private let ciContext = CIContext()

    private init() {}

    func initialize() {
        guard !initialized else { return }
        guard let modelPath = Bundle.main.path(forResource: "selfie_segmenter", ofType: "tflite") else {
            Logger.log("selfie_segmenter.tflite not in bundle")
            return
        }

        let baseOptions = BaseOptions(modelAssetPath: modelPath)
        baseOptions.delegate = .cpu

        let options = ImageSegmenterOptions()
        options.baseOptions = baseOptions
        options.runningMode = .image
        options.outputType = .confidenceMask

        segmenter = try? ImageSegmenter(options: options)
        initialized = segmenter != nil
        Logger.log(initialized ? "ImageSegmenter initialized (CPU)" : "ImageSegmenter init failed")
    }

    func segment(ciImage: CIImage) -> Data? {
        guard initialized, let segmenter else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)

        guard let mpImage = try? MPImage(uiImage: uiImage) else { return nil }

        guard let result = try? segmenter.segment(image: mpImage) else { return nil }
        let masks = result.confidenceMasks
        guard masks.count >= 2 else { return nil }

        let personMaskCG = masks[1].image
        let mw = personMaskCG.width
        let mh = personMaskCG.height

        var pixelData = [UInt8](repeating: 0, count: mw * mh)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &pixelData, width: mw, height: mh,
                                  bitsPerComponent: 8, bytesPerRow: mw,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(personMaskCG, in: CGRect(x: 0, y: 0, width: mw, height: mh))
        return Data(pixelData)
    }

    func close() {
        segmenter = nil
        initialized = false
    }
}
