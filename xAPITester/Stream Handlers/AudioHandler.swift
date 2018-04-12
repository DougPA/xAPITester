//
//  AudioHandler.swift
//  xAPITester
//
//  Created by Douglas Adams on 4/5/18.
//  Copyright © 2018 Douglas Adams. All rights reserved.
//

import Foundation
import xLib6000

// ------------------------------------------------------------------------------
// MARK: - AudioHandler Class implementation
// ------------------------------------------------------------------------------

public final class AudioHandler             : NSObject, AudioStreamHandler {
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public var active                         = false
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _id                           : UInt32
  private var _delegate                     : SplitViewController
  
  // ----------------------------------------------------------------------------
  // MARK: - Initialization
  

  init(id: UInt32, delegate: SplitViewController) {
    _id = id

    _delegate = delegate
    super.init()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Public methods
  
  public func streamHandler(_ frame: AudioStreamFrame) {

    // data received, is it the first?
    if !active {
      // YES, set active
      active = true
      
      _delegate.showInObjectsTable("START   Audio          \(_id.hex) stream")
    }
  }
}
