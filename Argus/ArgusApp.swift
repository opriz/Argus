//
//  ArgusApp.swift
//  Argus
//

import SwiftUI

@main
struct ArgusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Argus] applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        MenuBarController.shared.start()
        NSLog("[Argus] start() returned")
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarController.shared.stopSocket()
    }
}
