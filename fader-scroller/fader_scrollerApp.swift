//
//  fader_scrollerApp.swift
//  fader-scroller
//
//  Created by Weston Clark on 4/17/25.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        ScrollWheelMonitor.cleanupAllMonitors()
    }
}

@main
struct fader_scrollerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
