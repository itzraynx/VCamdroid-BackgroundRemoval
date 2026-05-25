import SwiftUI

@main
struct VCamdroidApp: App {
    @StateObject private var streamManager = StreamManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamManager)
        }
    }
}
