//
//  Radio.swift
//  xAPITesterSL
//
//  Created by Douglas Adams on 8/15/15.
//  Copyright © 2015 Douglas Adams & Mario Illgen. All rights reserved.
//

import Foundation


// --------------------------------------------------------------------------------
// MARK: - Radio Class implementation
//
//      as the object analog to the Radio (hardware), manages the use of all of
//      the other model objects
//
// --------------------------------------------------------------------------------

public final class Radio                    : NSObject {
  
  public private(set) var isWan             : Bool

  // ----------------------------------------------------------------------------
  // MARK: - Static properties
  
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties (Read Only)
  
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  internal var _api                         = Api.sharedInstance            // the API
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  

  // GCD Queue
  private let _objectQ                      : DispatchQueue

  
  // ----------------------------------------------------------------------------
  // MARK: - Initialization
  
  /// Initialize a Radio Class
  ///
  /// - Parameters:
  ///   - api:        an Api instance
  ///
  public init(api: Api, objectQ: DispatchQueue, isWan: Bool = false) {
    
    _api = api
    _objectQ = objectQ
    self.isWan = isWan

    super.init()
  }
}

