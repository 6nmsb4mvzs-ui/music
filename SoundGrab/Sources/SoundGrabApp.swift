import SwiftUI

@main
struct SoundGrabApp: App {
    @State private var manager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
                .frame(minWidth: 700, minHeight: 520)
        }
        .defaultSize(width: 800, height: 620)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
