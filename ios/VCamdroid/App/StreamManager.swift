import Foundation
import Combine
import CoreVideo
import CoreMedia
import CoreImage
import Accelerate

class StreamManager: ObservableObject {
    enum FilterType: String, CaseIterable {
        case none = "None"
        case backgroundRemoval = "Background Removal"
        case backgroundBlur = "Background Blur"
        case chromaKey = "Chroma Key"
    }

    @Published var isStreaming = false
    @Published var clientConnected = false
    @Published var localIP: String = ""
    @Published var rtspURL: String = ""
    @Published var rtspURLs: [String] = []
    @Published var activeFilter: FilterType = .none

    let cameraManager = CameraManager()
    let segmenter = SelfieSegmenterHelper.shared
    let encoder = VideoEncoder()
    let rtspServer = RTSPServer()
    let connectionManager = ConnectionManager()

    private let bgFilter = BackgroundRemovalFilter()
    private let chromaKeyFilter = ChromaKeyFilter()
    private var frameCount = 0
    private var lastMask: Data?
    private var cancellables = Set<AnyCancellable>()
    var allIPs: [String] = []

    init() {
        segmenter.initialize()

        connectionManager.$allIPs.receive(on: DispatchQueue.main).sink { [weak self] ips in
            guard let self else { return }
            self.allIPs = ips
            self.localIP = ips.first ?? "0.0.0.0"
            self.rtspURL = "rtsp://\(self.localIP):8554/live"
            self.rtspURLs = ips.map { "rtsp://\($0):8554/live" }
        }.store(in: &cancellables)

        rtspServer.onClientConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.clientConnected = true
            }
        }
        rtspServer.onClientDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.clientConnected = false
            }
        }
    }

    func startStream() {
        guard !isStreaming else { return }
        isStreaming = true
        frameCount = 0
        rtspServer.start()
        encoder.start(width: 640, height: 480) { [weak self] data, isKeyframe in
            let nalType = data[4] & 0x1F
            guard nalType != 8 && nalType != 6 else { return }
            self?.rtspServer.sendH264Packet(data, timestamp: CMTime.invalid, isKeyframe: isKeyframe)
        }
        cameraManager.start { [weak self] pixelBuffer in
            self?.processFrame(pixelBuffer)
        }
    }

    func stopStream() {
        isStreaming = false
        cameraManager.stop()
        encoder.stop()
        rtspServer.stop()
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isStreaming else { return }

        let processed: CVPixelBuffer
        switch activeFilter {
        case .backgroundRemoval:
            bgFilter.mode = .remove
            processed = bgFilter.apply(pixelBuffer: pixelBuffer, existingMask: &lastMask, frameCount: &frameCount)
        case .backgroundBlur:
            bgFilter.mode = .blur
            processed = bgFilter.apply(pixelBuffer: pixelBuffer, existingMask: &lastMask, frameCount: &frameCount)
        case .chromaKey:
            processed = chromaKeyFilter.apply(pixelBuffer: pixelBuffer)
        case .none:
            processed = pixelBuffer
        }
        encoder.encode(processed)
    }
}
