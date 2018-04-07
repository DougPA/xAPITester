//
//  IqHandler.swift
//  xAPITester
//
//  Created by Douglas Adams on 4/5/18.
//  Copyright © 2018 Douglas Adams. All rights reserved.
//

import Foundation
import xLib6000

// ------------------------------------------------------------------------------
// MARK: - IqHandler Class implementation
// ------------------------------------------------------------------------------

public final class IqHandler         : NSObject, IqStreamHandler {
  
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
  
  public func iqStreamHandler(_ dataFrame: IqStreamFrame) {

    // data received, is it the first?
    if !active {
      // YES, set active
      active = true
      
      _delegate.showInObjectsTable("START   IQ             \(_id.hex) stream")
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Start the timer
  ///
//  private func startTimer() {
//    
//    // create the timer's dispatch source
//    _timer = DispatchSource.makeTimerSource(flags: [.strict], queue: _timerQ)
//    
//    // Set timer for 1 second with 100 millisecond leeway
//    _timer.schedule(deadline: DispatchTime.now(), repeating: .seconds(1), leeway: .milliseconds(100))
//    
//    // set the expiration handler
//    _timer.setEventHandler { [ unowned self ] in
//      
//      // Timer fired, stop the Timer
//      self._timer?.cancel()
//      
//      self._delegate?.showInObjectsTable("TIMEOUT Panadapter \(self._id.hex) stream")
//    }
//  }
}
