//
//  Radio.swift
//  xAPITester
//
//  Created by Douglas Adams on 8/15/15.
//  Copyright © 2015 Douglas Adams & Mario Illgen. All rights reserved.
//

import Foundation


// --------------------------------------------------------------------------------
// MARK: - Radio Class implementation
//
//      This is a "Stub" version of Radio included to allow the use of the CommonCode.
//
// --------------------------------------------------------------------------------

public final class Radio                    : NSObject {
  
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
  public init(api: Api, objectQ: DispatchQueue) {
    
    _api = api
    _objectQ = objectQ

    super.init()
  }
}

