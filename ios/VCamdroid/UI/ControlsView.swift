import SwiftUI

struct ControlsView: View {
    @EnvironmentObject var streamManager: StreamManager

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(streamManager.isStreaming ? "Streaming" : "Stopped")
                    .font(.headline)
                    .foregroundColor(streamManager.isStreaming ? .green : .red)

                ForEach(streamManager.rtspURLs, id: \.self) { url in
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if streamManager.clientConnected {
                    Text("Client connected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Picker("Filter", selection: $streamManager.activeFilter) {
                ForEach(StreamManager.FilterType.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .disabled(streamManager.isStreaming)

            HStack(spacing: 30) {
                Button(action: {
                    if streamManager.isStreaming {
                        streamManager.stopStream()
                    } else {
                        streamManager.startStream()
                    }
                }) {
                    Image(systemName: streamManager.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(streamManager.isStreaming ? .red : .green)
                }

                Button(action: {
                    streamManager.cameraManager.switchCamera()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                .disabled(streamManager.isStreaming)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)
    }
}
