import Metal
import MetalKit
import CoreVideo

class PixelBufferRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    private let vertexBuffer: MTLBuffer
    private var previewPSO: MTLRenderPipelineState!
    private var maskPSO: MTLRenderPipelineState!

    private var textureCache: CVMetalTextureCache?
    private var maskTexture: MTLTexture?
    private let threshold: Float = 0.5

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.autoResizeDrawable = true

        guard let lib = device.makeDefaultLibrary() else { return nil }
        self.library = lib

        let verts: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [])!

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

        previewPSO = makePSO(fragment: "fragmentPreview")
        maskPSO = makePSO(fragment: "fragmentMaskComposite")
    }

    func updateMask(_ maskData: Data, width: Int, height: Int) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                            width: width, height: height,
                                                            mipmapped: false)
        desc.usage = .shaderRead
        maskTexture = device.makeTexture(descriptor: desc)
        maskData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            maskTexture?.replace(region: MTLRegionMake2D(0, 0, width, height),
                                 mipmapLevel: 0,
                                 withBytes: base,
                                 bytesPerRow: width)
        }
    }

    func renderPreview(pixelBuffer: CVPixelBuffer, to drawable: CAMetalDrawable) {
        guard let tex = makeTexture(from: pixelBuffer) else { return }
        render(texture: tex, pso: previewPSO, to: drawable)
    }

    func renderMaskComposite(pixelBuffer: CVPixelBuffer, to drawable: CAMetalDrawable) {
        guard let tex = makeTexture(from: pixelBuffer), let maskTex = maskTexture else {
            renderPreview(pixelBuffer: pixelBuffer, to: drawable)
            return
        }

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let rpd = currentRenderPass(to: drawable) else { return }

        let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(maskPSO)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentTexture(maskTex, index: 1)
        var thresh = threshold
        enc.setFragmentBytes(&thresh, length: MemoryLayout<Float>.size, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private func render(texture: MTLTexture, pso: MTLRenderPipelineState, to drawable: CAMetalDrawable) {
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let rpd = currentRenderPass(to: drawable) else { return }
        let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pso)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer,
                                                   nil, .bgra8Unorm, w, h, 0, &cvTex)
        guard let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return nil }
        return tex
    }

    private func currentRenderPass(to drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return rpd
    }

    private func makePSO(fragment: String) -> MTLRenderPipelineState? {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexPassThrough")
        desc.fragmentFunction = library.makeFunction(name: fragment)
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}
