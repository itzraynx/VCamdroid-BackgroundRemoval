import VideoToolbox
import CoreVideo
import CoreMedia

class VideoEncoder {
    private var compressionSession: VTCompressionSession?
    private var isEncoding = false
    private var onEncoded: ((Data, Bool) -> Void)?
    private var frameCount = 0

    func start(width: Int32, height: Int32, onEncoded: @escaping (Data, Bool) -> Void) {
        self.onEncoded = onEncoded
        isEncoding = true

        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: width, height: height,
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: nil,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: encodingCallback,
                                                refcon: Unmanaged.passUnretained(self).toOpaque(),
                                                compressionSessionOut: &compressionSession)
        guard status == noErr, let session = compressionSession else {
            Logger.log("VTCompressionSession create failed: \(status)")
            return
        }

        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ExpectedFrameRate: 30,
            kVTCompressionPropertyKey_AverageBitRate: 4_000_000,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 30,
        ]
        VTSessionSetProperties(session, props as CFDictionary)
        VTCompressionSessionPrepareToEncodeFrames(session)
        Logger.log("VideoEncoder started \(width)x\(height)")
    }

    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard isEncoding, let session = compressionSession else { return }

        let pts = CMTime(value: CMTimeValue(frameCount), timescale: 30)
        frameCount += 1

        VTCompressionSessionEncodeFrame(session,
                                        imageBuffer: pixelBuffer,
                                        presentationTimeStamp: pts,
                                        duration: .invalid,
                                        frameProperties: nil,
                                        sourceFrameRefcon: nil,
                                        infoFlagsOut: nil)
    }

    func stop() {
        isEncoding = false
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
        }
        compressionSession = nil
        onEncoded = nil
    }

    private func handleOutput(sampleBuffer: CMSampleBuffer) {
        guard let onEncoded, let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length: Int = 0
        var data: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                     totalLengthOut: &length, dataPointerOut: &data)
        guard let data, length > 0 else { return }

        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            isKeyframe = !CFDictionaryContainsKey(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        }

        let nalData = Data(bytes: data, count: length)
        parseNALUnits(nalData).forEach { onEncoded($0, isKeyframe) }
    }

    private func parseNALUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        var start = 0
        let pattern: [UInt8] = [0, 0, 0, 1]
        while start < data.count {
            if let end = findNextNAL(data, from: start + 4) {
                units.append(Data(data[start..<end]))
                start = end
            } else {
                units.append(Data(data[start..<data.count]))
                break
            }
        }
        return units
    }

    private func findNextNAL(_ data: Data, from: Int) -> Int? {
        var i = from
        while i < data.count - 3 {
            if data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                return i
            }
            i += 1
        }
        return nil
    }
}

private let encodingCallback: VTCompressionOutputCallback = { refcon, _, _, status, infoFlags, sampleBuffer in
    guard status == noErr, let sb = sampleBuffer else { return }
    let encoder = Unmanaged<VideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
    encoder.handleOutput(sampleBuffer: sb)
}
