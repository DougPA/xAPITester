//
//  AppDelegate.swift
//  xAPITester
//
//  Created by Douglas Adams on 12/10/16.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Cocoa

let kClientName = "xAPITesterSL"

// ------------------------------------------------------------------------------
// MARK: - App Delegate Class implementation
// ------------------------------------------------------------------------------

@NSApplicationMain
final class AppDelegate                     : NSObject, NSApplicationDelegate {
    
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    
  }
  
  func applicationWillTerminate(_ aNotification: Notification) {
    
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    
    // close the app if the window is closed
    return true
  }
}

