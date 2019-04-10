//
//  Macros.swift
//  xAPITester
//
//  Created by Douglas Adams on 5/25/18.
//  Copyright © 2018 Douglas Adams. All rights reserved.
//

import Foundation
import os.log
import xLib6000

final public class Macros {

  static let kMacroPrefix                     : Character = ">"
  static let kConditionPrefix                 : Character = "<"
  static let kPauseBetweenMacroCommands       : UInt32 = 30_000             // 30 milliseconds

  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance          // Api to the Radio
  private let _log                            = OSLog(subsystem: "net.k3tzr.xAPITester", category: "Macros")

  // ----------------------------------------------------------------------------
  // MARK: - Public Instance methods
  
  /// Run a macro file
  ///
  /// - Parameters:
  ///   - name:               the File name
  ///   - choose:             allow the user to pick a file
  ///
  public func runMacro(_ name: String, window: NSWindow, appFolderUrl: URL, choose: Bool = true) {
    
    // nested function to process the selected URL
    func processUrl(_ url: URL) {
      var commandsArray = [String]()
      var fileString = ""
      
      do {
        // try to read the file url
        try fileString = String(contentsOf: url)
        
        // separate into lines
        commandsArray = fileString.components(separatedBy: "\n")
        
        // eliminate the last one (it's blank)
        commandsArray.removeLast()
        
        // run each command
        for command in commandsArray {
          
          let evaluatedCommand = parse(command)
          if evaluatedCommand.active {
            
            // send the command
            _api.send(evaluatedCommand.cmd)
            
            // pause between commands
            usleep(Macros.kPauseBetweenMacroCommands)
          }
        }
      } catch {
        
        // something bad happened!
//        _log.msg("Error reading file", level: .error, function: #function, file: #file, line: #line)

        os_log("Error reading file", log: _log, type: .error)
      }
    }
    
    // pick a file?
    if choose {
      
      // YES, open a dialog
      let openPanel = NSOpenPanel()
      openPanel.canChooseFiles = choose
      openPanel.representedFilename = name
      openPanel.allowedFileTypes = ["macro"]
      openPanel.directoryURL = appFolderUrl
      
      // open an Open Dialog
      openPanel.beginSheetModal(for: window) { (result: NSApplication.ModalResponse) in
        
        // if the user selects Open
        if result == NSApplication.ModalResponse.OK { processUrl(openPanel.url!) }
      }
      
    } else {
      
      // NO, process the passed name
      processUrl(appFolderUrl.appendingPathComponent(name + ".macro"))
    }
  }
  /// Parse a macro command line
  ///
  /// - Parameter command:            the command line
  /// - Returns:                      a tuple containing the evaluated command & whether to send it
  ///
  public func parse(_ command: String) -> (cmd: String, active: Bool, condition: String) {
    
    // format:    <Identifier Param>commandString
    //
    // where:     Identifier = Sn or Pn     for Slice n   or   Panadapter n
    //            Parameter = a parameter names, e.g. AM, RIT_ON, etc
    
    var cmd           = command
    var state         = true
    var condition     = ""
    
    // is it a conditional command?
    if command.hasPrefix("<") {
      
      // YES, drop the "<"
      let remainder = String(command.dropFirst())
      
      // separate the pieces
      let scanner = Scanner(string: remainder)
      var expr1: NSString?
      var expr2: NSString?
      scanner.scanUpTo(">", into: &expr1)
      scanner.scanLocation += 1
      scanner.scanUpTo("", into: &expr2)
      
      // were the parts found?
      if let expr1 = expr1, let expr2 = expr2 {
        
        condition = expr1 as String
        state = evaluateCondition(condition)
        cmd = expr2 as String
      }
    }
    return (cmd, state, condition)
  }
  /// Evaluate the command's condition prefix
  ///
  /// - Parameter condition:      the condition prefix
  /// - Returns:                  whether the condition was satisfied
  ///
  public func evaluateCondition(_ condition: String) -> Bool {
    var result          = false
    
    // separate the components of the condition
    let components = condition.split(separator: " ")
    
    // should only be two
    guard components.count == 2 else {
//      _log.msg("Malformed macro condition - \(condition)", level: .error, function: #function, file: #file, line: #line)

      os_log("Malformed macro condition - %{public}@", log: _log, type: .error, condition)

      return false
    }
    // obtain a reference to the object
    if let object = findObject(id: components) {
      
      // test the specified condition
      switch components[1].lowercased() {
      case "am", "sam", "cw", "usb", "lsb", "digu", "digl", "fm", "nfm","dfm", "rtty" :
        result = ((object as! xLib6000.Slice).mode == components[1].uppercased())
        
      case "off", "slow", "medium", "fast" :
        result = ((object as! xLib6000.Slice).agcMode == components[1].uppercased())
        
        //    case "bw_band":
        //      break
        //
        //    case "bw_back":
        //      break
        //
        //    case "bw_segment":
        //      break
        
      case "anf_off" :
        result = ((object as! xLib6000.Slice).anfEnabled == false)
        
      case "anf_on" :
        result = ((object as! xLib6000.Slice).anfEnabled == true)
        
      case "dax_none":
        result = ((object as! xLib6000.Slice).daxChannel == 0)
        
      case "dax_1","dax_2","dax_3","dax_4","dax_5","dax_6","dax_7" :
        result = ((object as! xLib6000.Slice).daxChannel == Int(components[1].dropFirst(4)))
        
      case "daxiq_none":
        result = ((object as! Panadapter).daxIqChannel == 0)
        
      case "daxiq_1","daxiq_2","daxiq_3","daxiq_4" :
        result = ((object as! Panadapter).daxIqChannel == Int(components[1].dropFirst(6)))
        
      case "locked_off" :
        result = ((object as! xLib6000.Slice).locked == false)
        
      case "locked_on" :
        result = ((object as! xLib6000.Slice).locked == true)
        
      case "loopA_off" :
        result = ((object as! xLib6000.Slice).loopAEnabled == false)
        
      case "loopA_on" :
        result = ((object as! xLib6000.Slice).loopAEnabled == true)
        
      case "loopB_off" :
        result = ((object as! xLib6000.Slice).loopBEnabled == false)
        
      case "loopB_on" :
        result = ((object as! xLib6000.Slice).loopBEnabled == true)
        
      case "rit_off" :
        result = ((object as! xLib6000.Slice).ritEnabled == false)
        
      case "rit_on" :
        result = ((object as! xLib6000.Slice).ritEnabled == true)
        
      case "tx_off" :
        result = ((object as! xLib6000.Slice).txEnabled == false)
        
      case "tx_on" :
        result = ((object as! xLib6000.Slice).txEnabled == true)
        
      case "xit_off" :
        result = ((object as! xLib6000.Slice).xitEnabled == false)
        
      case "xit_on" :
        result = ((object as! xLib6000.Slice).xitEnabled == true)
        
      default:
//        _log.msg("Unknown macro action - \(components[1])", level: .error, function: #function, file: #file, line: #line)

        os_log("Unknown macro action - %{public}@", log: _log, type: .error, String(components[1]))
      }
    }
    return result
  }
  /// Evaluate the replaceable Values in a command
  ///
  /// - Parameter command:          the command string before evaluation
  /// - Returns:                    the command string after evaluation
  ///
  public  func evaluateValues(command: String) -> String {
    
    // separate all components of the command
    let components = command.components(separatedBy: " ")
    
    // evaluate each component
    let evaluatedComponents = components.map { (cmd) -> String in return extractExpression(cmd) }
    
    // put the evaluated components together in a command line
    return evaluatedComponents.joined(separator:" ")
  }
  /// Extract the replaceable parameters
  ///
  /// - Parameter string:           a command string (with / without replaceable params
  /// - Returns:                    the command string with parameters replaced
  ///
  public func extractExpression(_ string: String) -> String {
    var expandedExpr = string
    
    // does the string contain a replaceable parameter?
    if string.contains("<") && string.contains(">") {
      
      // YES, isolate it
      let i = string.firstIndex(of: "<")!
      let j = string.firstIndex(of: ">")!
      let expr = String(string[string.index(after: i)..<j])
      
      // separate the "object" from the "modifier"
      let components = expr.split(separator: ".")
      
      // obtain a reference to the object
      if let object = findObject(id: components) {
        
        // expand the param
        if let value = findValue(of: object, param: components[1]) {
          expandedExpr = String(string[..<i]) + value + String(string[string.index(after: j)...])
        }
      }
    }
    return expandedExpr
  }
  /// Find the specified object
  ///
  /// - Parameter id:               object ID
  /// - Returns:                    a refrence to the object
  ///
  public func findObject(id: [String.SubSequence]) -> AnyObject? {
    let kPanadapterBase = UInt32(0x40000000)
    
    let object = id[0].dropLast()
    let number = id[0].dropFirst()
    
    // obtain a reference to the object
    switch object {
    case "S":                       // Slice
      switch number {
      case "A":
        return Slice.findActive()
        
      case "0","1","2","3","4","5","6","7":
        return _api.radio!.slices[String(number)]
        
      default:
//        _log.msg("Macro error: slice - \(number)", level: .error, function: #function, file: #file, line: #line)

        os_log("Macro error: slice - %{public}@", log: _log, type: .error, String(number))

        return nil
      }
    case "P":                       // Panadapter
      switch number {
      case "0","1","2","3","4","5","6","7":
        return _api.radio!.panadapters[kPanadapterBase + UInt32(number)!]
        
      default:
//        _log.msg("Macro error: panadapter - \(number)", level: .error, function: #function, file: #file, line: #line)

        os_log("Macro error: panadapter - %{public}@", log: _log, type: .error, String(number))
        
        return nil
      }
      
    default:
//      _log.msg("Macro error: object - \(object)", level: .error, function: #function, file: #file, line: #line)

      os_log("Macro error: object - %{public}@", log: _log, type: .error, String(object))
      
      return nil
    }
  }
  /// Find the value of a parameter
  ///
  /// - Parameters:
  ///   - object:                     an object reference
  ///   - param:                      a parameter id
  /// - Returns:                      a String representation of the param value
  ///
  public func findValue(of object: AnyObject, param: String.SubSequence) -> String? {
    let operators = CharacterSet(charactersIn: "+-")
    var p = param
    var value = 0
    var op  = ""
    
    // is there an arithmetic operation?
    let components = param.components(separatedBy: operators)
    if components.count == 2 {
      // get the operator
      let indexOfOperator = param.index(param.startIndex, offsetBy: components[0].count)
      op = String(param[indexOfOperator])
      
      // get the value
      value = Int(components[1], radix: 10) ?? 0
      if op == "-" { value = -value }
      
      // get the param portion
      p = param[..<indexOfOperator]
    }
    
    // identify the object / param and return its value
    
    if let slice = object as? xLib6000.Slice {              // Slice params
      
      switch p.lowercased() {
      case "id":
        return slice.id
        
      case "freq":
        return (slice.frequency + value).hzToMhz
        
      default:
//        _log.msg("Macro error: slice param - \(p)", level: .error, function: #function, file: #file, line: #line)

        os_log("Macro error: slice param - %{public}@", log: _log, type: .error, String(p))
        return nil
      }
    } else if let panadapter = object as? Panadapter {      // Panadapter params
      
      switch p.lowercased() {
      case "id":
        return panadapter.id.hex
        
      case "bw":
        return String(panadapter.bandwidth)
        
      default:
//        _log.msg("Macro error: panadapter param - \(p)", level: .error, function: #function, file: #file, line: #line)

        os_log("Macro error: panadapter param - %{public}@", log: _log, type: .error, String(p))
        return nil
      }
    }
    return nil
  }
}
