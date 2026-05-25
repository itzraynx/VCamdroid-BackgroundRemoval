import SwiftUI

struct ContentView: View {
    @EnvironmentObject var streamManager: StreamManager

    var body: some View {
        VStack(spacing: 0) {
            CameraPreview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ControlsView()
                .padding(.horizontal)
                .padding(.bottom, 20)
        }
        .edgesIgnoringSafeArea(.all)
        .preferredColorScheme(.dark)
    }
}
