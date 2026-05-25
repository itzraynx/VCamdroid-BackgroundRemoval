import SwiftUI
import MetalKit

struct CameraPreview: UIViewRepresentable {
    @EnvironmentObject var streamManager: StreamManager

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = streamManager.cameraManager.metalDevice
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 30
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(streamManager: streamManager)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let streamManager: StreamManager
        var renderer: PixelBufferRenderer?
        var textureCache: CVMetalTextureCache?

        init(streamManager: StreamManager) {
            self.streamManager = streamManager
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            if renderer == nil {
                renderer = PixelBufferRenderer(mtkView: view)
            }
        }

        func draw(in view: MTKView) {
            guard let renderer, let drawable = view.currentDrawable else { return }
            if let pb = streamManager.cameraManager.latestPixelBuffer {
                renderer.renderPreview(pixelBuffer: pb, to: drawable)
            }
        }
    }
}
