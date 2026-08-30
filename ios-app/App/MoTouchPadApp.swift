import SwiftUI

@main
struct MoTouchPadApp: App {
    var body: some Scene {
        WindowGroup {
            TouchpadView()
                .preferredColorScheme(.dark)
        }
    }
}
