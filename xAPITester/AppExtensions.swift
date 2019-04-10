//
//  AppExtensions.swift
//  xAPITester
//
//  Created by Douglas Adams on 8/15/15.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Cocoa
import SwiftyUserDefaults

// ----------------------------------------------------------------------------
// MARK: - EXTENSIONS

typealias NC = NotificationCenter

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
//  static let commandColor                   = DefaultsKey<NSColor>("commandColor")
  static let defaultRadio                   = DefaultsKey<[String: Any]>("defaultRadio")
  static let enablePinging                  = DefaultsKey<Bool>("enablePinging")
  static let filter                         = DefaultsKey<String>("filter")
  static let filterByTag                    = DefaultsKey<Int>("filterByTag")
  static let filterMeters                   = DefaultsKey<String>("filterMeters")
  static let filterMetersByTag              = DefaultsKey<Int>("filterMetersByTag")
  static let filterObjects                  = DefaultsKey<String>("filterObjects")
  static let filterObjectsByTag             = DefaultsKey<Int>("filterObjectsByTag")
  static let fontMaxSize                    = DefaultsKey<Int>("fontMaxSize")
  static let fontMinSize                    = DefaultsKey<Int>("fontMinSize")
  static let fontName                       = DefaultsKey<String>("fontName")
  static let fontSize                       = DefaultsKey<Int>("fontSize")
  static let isGui                          = DefaultsKey<Bool>("isGui")
  static let lowBandwidthEnabled            = DefaultsKey<Bool>("lowBandwidthEnabled")
//  static let messageColor                   = DefaultsKey<NSColor>("messageColor")
//  static let myHandleColor                  = DefaultsKey<NSColor>("myHandleColor")
//  static let neutralColor                   = DefaultsKey<NSColor>("neutralColor")
//  static let otherHandleColor               = DefaultsKey<NSColor>("otherHandleColor")
  static let showAllReplies                 = DefaultsKey<Bool>("showAllReplies")
  static let showPings                      = DefaultsKey<Bool>("showPings")
  static let showRemoteTabView              = DefaultsKey<Bool>("showRemoteTabView")
  static let showTimestamps                 = DefaultsKey<Bool>("showTimestamps")
  static let smartLinkAuth0Email            = DefaultsKey<String>("smartLinkAuth0Email")
  static let smartLinkToken                 = DefaultsKey<String?>("smartLinkToken")
  static let smartLinkTokenExpiry           = DefaultsKey<Date?>("smartLinkTokenExpiry")
  static let suppressUdp                    = DefaultsKey<Bool>("suppressUdp")
  static let useLowBw                       = DefaultsKey<Bool>("useLowBw")
  //  static let connectSimple                  = DefaultsKey<Bool>("connectSimple")
}

extension FileManager {
  
  /// Get / create the Application Support folder
  ///
  static var appFolder : URL {
    let fileManager = FileManager.default
    let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask )
    let appFolderUrl = urls.first!.appendingPathComponent( Bundle.main.bundleIdentifier! )
    
    // does the folder exist?
    if !fileManager.fileExists( atPath: appFolderUrl.path ) {
      
      // NO, create it
      do {
        try fileManager.createDirectory( at: appFolderUrl, withIntermediateDirectories: false, attributes: nil)
      } catch let error as NSError {
        fatalError("Error creating App Support folder: \(error.localizedDescription)")
      }
    }
    return appFolderUrl
  }
}

extension URL {
  
  /// Write an array of Strings to a URL
  ///
  /// - Parameters:
  ///   - textArray:                        an array of String
  ///   - addEndOfLine:                     whether to add an end of line to each String
  /// - Returns:                            an error message (if any)
  ///
  func writeArray(_ textArray: [String], addEndOfLine: Bool = true) -> String? {
    
    let eol = (addEndOfLine ? "\n" : "")
    
    // add a return to each line
    // build a string of all the lines
    let fileString = textArray
      .map { $0 + eol }
      .reduce("", +)
    
    do {
      // write the string to the url
      try fileString.write(to: self, atomically: true, encoding: String.Encoding.utf8)
      
    } catch let error as NSError {
      
      // an error occurred
      return "Error writing to file : \(error.localizedDescription)"
      
    } catch {
      
      // an error occurred
      return "Error writing Log"
    }
    return nil
  }
}
// ----------------------------------------------------------------------------
// MARK: - String

public extension String {
  
  /// Check if a String is a valid IP4 address
  ///
  /// - Returns:          the result of the check as Bool
  ///
  func isValidIP4() -> Bool {
    
    // check for 4 values separated by period
    let parts = self.components(separatedBy: ".")
    
    // convert each value to an Int
    let nums = parts.compactMap { Int($0) }
    
    // must have 4 values containing 4 numbers & 0 <= number < 256
    return parts.count == 4 && nums.count == 4 && nums.filter { $0 >= 0 && $0 < 256}.count == 4
  }
}

// ----------------------------------------------------------------------------
// MARK: - TOP-LEVEL FUNCTIONS

/// Find versions for this app and the specified framework
///
func versionInfo(framework: String) -> (String, String) {
  let kVersionKey             = "CFBundleShortVersionString"  // CF constants
  let kBuildKey               = "CFBundleVersion"
  
  // get the version of the framework
  let frameworkBundle = Bundle(identifier: framework)!
  var version = frameworkBundle.object(forInfoDictionaryKey: kVersionKey)!
  var build = frameworkBundle.object(forInfoDictionaryKey: kBuildKey)!
  let frameworkVersion = "\(version).\(build)"
  
  // get the version of this app
  version = Bundle.main.object(forInfoDictionaryKey: kVersionKey)!
  build = Bundle.main.object(forInfoDictionaryKey: kBuildKey)!
  let appVersion = "\(version).\(build)"
  
  return (frameworkVersion, appVersion)
}

/// Setup & Register User Defaults from a file
///
/// - Parameter file:         a file name (w/wo extension)
///
func defaults(from file: String) {
  var fileURL : URL? = nil
  
  // get the name & extension
  let parts = file.split(separator: ".")
  
  // exit if invalid
  guard parts.count != 0 else {return }
  
  if parts.count >= 2 {
    
    // name & extension
    fileURL = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]))
    
  } else if parts.count == 1 {
    
    // name only
    fileURL = Bundle.main.url(forResource: String(parts[0]), withExtension: "")
  }
  
  if let fileURL = fileURL {
    // load the contents
    let myDefaults = NSDictionary(contentsOf: fileURL)!
    
    // register the defaults
    UserDefaults.standard.register(defaults: myDefaults as! Dictionary<String, Any>)
  }
}


