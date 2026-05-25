import MediaPipeTasksVision
import CoreImage
import UIKit

class SelfieSegmenterHelper {
    static let shared = SelfieSegmenterHelper()

    private var segmenter: ImageSegmenter?
    private var initialized = false

    private init() {}

    func initialize() {
        guard !initialized else { return }
        guard let modelPath = Bundle.main.path(forResource: "selfie_segmenter", ofType: "tflite") else {
            Logger.log("selfie_segmenter.tflite not in bundle")
            return
        }

        let baseOptions = BaseOptions()
        baseOptions.modelAssetPath = modelPath

        let options = ImageSegmenterOptions()
        options.baseOptions = baseOptions
        options.runningMode = .image

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
        guard let masks = result.confidenceMasks, masks.count >= 2 else { return nil }

        let mw = masks[1].width
        let mh = masks[1].height
        return Data(bytes: masks[1].uint8Data, count: mw * mh)
    }

    func close() {
        segmenter = nil
        initialized = false
    }
}
