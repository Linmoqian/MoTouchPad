import SwiftUI

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

@main
struct MoTouchPadApp: App {
    var body: some Scene {
        WindowGroup {
            TouchpadView()
                .preferredColorScheme(.dark)
        }
    }
}
