import AVFoundation
import CoreImage
import UIKit
import Metal

class CameraManager: NSObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var onFrame: ((CVPixelBuffer) -> Void)?
    private var isRunning = false
    private var currentPosition: AVCaptureDevice.Position = .front

    let metalDevice = MTLCreateSystemDefaultDevice()
    var latestPixelBuffer: CVPixelBuffer?

    var width: Int32 = 640
    var height: Int32 = 480

    func start(_ onFrame: @escaping (CVPixelBuffer) -> Void) {
        guard !isRunning else { return }
        self.onFrame = onFrame
        isRunning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupSession()
            self?.captureSession.startRunning()
        }
    }

    func stop() {
        isRunning = false
        onFrame = nil
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func switchCamera() {
        guard !isRunning else { return }
        currentPosition = currentPosition == .front ? .back : .front
        captureSession.stopRunning()
        removeInputs()
        setupSession()
        captureSession.startRunning()
    }

    private func removeInputs() {
        captureSession.inputs.forEach { captureSession.removeInput($0) }
    }

    private func setupSession() {
        captureSession.sessionPreset = .medium

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition)
        guard let device else {
            Logger.log("No camera found")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            Logger.log("Failed to create camera input")
            return
        }

        guard captureSession.canAddInput(input) else {
            Logger.log("Cannot add camera input")
            return
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.queue", qos: .userInitiated))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard captureSession.canAddOutput(videoOutput) else {
            Logger.log("Cannot add video output")
            return
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = currentPosition == .front
            }
        }

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        width = dims.width
        height = dims.height
        Logger.log("Camera started: \(width)x\(height) position=\(currentPosition == .front ? "front" : "back")")
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pixelBuffer
        onFrame?(pixelBuffer)
    }
}
