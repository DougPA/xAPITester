//
//  LocalExtensions.swift
//  xAPITester
//
//  Created by Douglas Adams on 12/10/16.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Cocoa
import SwiftyUserDefaults

// ----------------------------------------------------------------------------
// MARK: - Definitions for SwiftyUserDefaults

extension UserDefaults {
  
  subscript(key: DefaultsKey<NSColor>) -> NSColor {
    get { return unarchive(key)! }
    set { archive(key, newValue) }
  }
  
  public subscript(key: DefaultsKey<CGFloat>) -> CGFloat {
    get { return CGFloat(numberForKey(key._key)?.doubleValue ?? 0.0) }
    set { set(key, Double(newValue)) }
  }
}

// defaults keys (for values in defaults.plist)
extension DefaultsKeys {
  
  static let auth0Email                     = DefaultsKey<String>("auth0Email")
  static let clearAtConnect                 = DefaultsKey<Bool>("clearAtConnect")
  static let clearOnSend                    = DefaultsKey<Bool>("clearOnSend")
  static let commandColor                   = DefaultsKey<NSColor>("commandColor")
  static let defaultsDictionary             = DefaultsKey<[String: Any]>("defaultsDictionary")
  static let enablePinging                  = DefaultsKey<Bool>("enablePinging")
  static let filter                         = DefaultsKey<String>("filter")
  static let filterByTag                    = DefaultsKey<Int>("filterByTag")
  static let fontMaxSize                    = DefaultsKey<Int>("fontMaxSize")
  static let fontMinSize                    = DefaultsKey<Int>("fontMinSize")
  static let fontName                       = DefaultsKey<String>("fontName")
  static let fontSize                       = DefaultsKey<Int>("fontSize")
  static let useLowBw                       = DefaultsKey<Bool>("useLowBw")
  static let messageColor                   = DefaultsKey<NSColor>("messageColor")
  static let myHandleColor                  = DefaultsKey<NSColor>("myHandleColor")
  static let neutralColor                   = DefaultsKey<NSColor>("neutralColor")
  static let otherHandleColor               = DefaultsKey<NSColor>("otherHandleColor")
  static let showAllReplies                 = DefaultsKey<Bool>("showAllReplies")
  static let suppressUdp                    = DefaultsKey<Bool>("suppressUdp")
  static let showPings                      = DefaultsKey<Bool>("showPings")
  static let isGui                          = DefaultsKey<Bool>("isGui")
  static let connectSimple                  = DefaultsKey<Bool>("connectSimple")
  static let showRemoteTabView              = DefaultsKey<Bool>("showRemoteTabView")
  static let showTimestamps                 = DefaultsKey<Bool>("showTimestamps")
}
