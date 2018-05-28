//
//  SplitViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 3/29/18.
//  Copyright © 2018 Douglas Adams. All rights reserved.
//

import Cocoa
import xLib6000
import SwiftyUserDefaults

// ------------------------------------------------------------------------------
// MARK: - SplitViewController Class implementation
// ------------------------------------------------------------------------------

class SplitViewController: NSSplitViewController, ApiDelegate, NSTableViewDelegate, NSTableViewDataSource,  LogHandler {
  
  static let kOtherColor                      = NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.2)
  static let kRadioColor                      = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.2)
  static let kStartedColor                    = NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.2)
  static let kSubordinateColor                = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.2)
  static let kStreamColor                     = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.1)
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public enum FilterTag: Int {                                              // types of filtering
    case none = 0
    case prefix
    case contains
    case exclude
    case streamId
  }
  public enum FilterObjectsTag: Int {                                              // types of filtering
    case none = 0
    case prefix
    case contains
    case exclude
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  @IBOutlet internal var _tableView           : NSTableView!
  @IBOutlet internal var _objectsTableView    : NSTableView!
  
  public var myHandle: String {
    get { return _objectQ.sync { _myHandle } }
    set { _objectQ.sync(flags: .barrier) { _myHandle = newValue } } }
  
  internal var objectsArray: [String] {
    get { return _objectQ.sync { _objectsArray } }
    set { _objectQ.sync(flags: .barrier) { _objectsArray = newValue } } }
  
  internal var textArray: [String] {
    get { return _objectQ.sync { _textArray } }
    set { _objectQ.sync(flags: .barrier) { _textArray = newValue } } }
  
  internal var replyHandlers: [SequenceId: ReplyTuple] {
    get { return _objectQ.sync { _replyHandlers } }
    set { _objectQ.sync(flags: .barrier) { _replyHandlers = newValue } } }
  
  internal var _filteredTextArray              : [String] {                  // filtered version of textArray
    get {
      switch FilterTag(rawValue: Defaults[.filterByTag]) ?? .none {
      case .none:
        return textArray
        
      case .prefix:
        Swift.print(textArray)
        return textArray.filter { $0.contains("|" + Defaults[.filter]) }
        
      case .contains:
        return textArray.filter { $0.contains(Defaults[.filter]) }
        
      case .exclude:
        return textArray.filter { !$0.contains(Defaults[.filter]) }
        
      case .streamId:
        return textArray.filter { $0.dropFirst(9).hasPrefix("S" + myHandle) }
      }
    }}
  internal var _filteredObjectsArray           : [String] {                  // filtered version of objectsArray
    get {
      switch FilterObjectsTag(rawValue: Defaults[.filterObjectsByTag]) ?? .none {
      case .none:
        return objectsArray
        
      case .prefix:
        return objectsArray.filter { $0.dropFirst(9).hasPrefix(Defaults[.filterObjects]) }
        
      case .contains:
        return objectsArray.filter { $0.contains(Defaults[.filterObjects]) }
        
      case .exclude:
        return objectsArray.filter { !$0.contains(Defaults[.filterObjects]) }
      }
    }}
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance          // Api to the Radio
  internal weak var _parent                   : ViewController?
  internal let _objectQ                       = DispatchQueue(label: kClientName + ".objectQ", attributes: [.concurrent])
  
  private var _font                           : NSFont!                     // font for table entries
  
  private var _myHandle                       = ""
  private var _replyHandlers                  = [SequenceId: ReplyTuple]()  // Dictionary of pending replies
  private var _textArray                      = [String]()                  // backing storage for the table
  private var _objectsArray                   = [String]()                  // backing storage for the objects table

  private var _timeoutTimer                   : DispatchSourceTimer!          // timer fired every "checkInterval"
  private var _timerQ                         = DispatchQueue(label: "xAPITester" + ".timerQ")

  private let kAutosaveName                   = NSSplitView.AutosaveName(rawValue: kClientName + "SplitView")
  private let checkInterval                   : TimeInterval = 1.0
  
  // ----------------------------------------------------------------------------
  // MARK: - Overridden methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    splitView.autosaveName = kAutosaveName
    
    _api.testerDelegate = self
    
    // give the Log object (in the API) access to our logger
    Log.sharedInstance.delegate = self
    
    // setup the font
    _font = NSFont(name: Defaults[.fontName], size: CGFloat(Defaults[.fontSize] ))!
    _tableView.rowHeight = _font.capHeight * 1.7
    
    // create a timer to periodically redraw the objetcs table
    _timeoutTimer = DispatchSource.makeTimerSource(flags: [.strict], queue: _timerQ)
    
    // Set timer with 100 millisecond leeway
    _timeoutTimer.schedule(deadline: DispatchTime.now(), repeating: checkInterval, leeway: .milliseconds(100))      // Every second +/- 10%
    
    // set the event handler
    _timeoutTimer.setEventHandler { [ unowned self] in
      
      // redraw the objects table when the timer fires
      self.redraw()
    }
    // start the timer
    _timeoutTimer.resume()
  }

  deinit {
    
    _timeoutTimer?.cancel()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Action methods
  
  /// 1st Responder to the Format->Font->Bigger menu (or Command=)
  ///
  /// - Parameter sender:     the sender
  ///
  @IBAction func fontBigger(_ sender: AnyObject) {
    
    // limit the font size
    var newSize =  Defaults[.fontSize] + 1
    if newSize > Defaults[.fontMaxSize] { newSize = Defaults[.fontMaxSize] }
    
    // save change to preferences
    Defaults[.fontSize] = newSize
    
    // update the font
    _font = NSFont(name: Defaults[.fontName], size: CGFloat(Defaults[.fontSize] ))!
    _tableView.rowHeight = _font.capHeight * 1.7
    _objectsTableView.rowHeight = _font.capHeight * 1.7
    
    // force a redraw
    reloadTable()
    reloadObjectsTable()
  }
  /// 1st Responder to the Format->Font->Smaller menu (or Command-)
  ///
  /// - Parameter sender:     the sender
  ///
  @IBAction func fontSmaller(_ sender: AnyObject) {
    
    // limit the font size
    var newSize =  Defaults[.fontSize] - 1
    if newSize < Defaults[.fontMinSize] { newSize = Defaults[.fontMinSize] }
    
    // save change to preferences
    Defaults[.fontSize] = newSize
    
    // update the font
    _font = NSFont(name: Defaults[.fontName], size: CGFloat(Defaults[.fontSize] ))!
    _tableView.rowHeight = _font.capHeight * 1.7
    _objectsTableView.rowHeight = _font.capHeight * 1.7
    
    // force a redraw
    reloadTable()
    reloadObjectsTable()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal methods
  
  /// Refresh the TableView & make its last row visible
  ///
  internal func reloadTable() {
    
    DispatchQueue.main.async { [unowned self] in
      // reload the table
      self._tableView.reloadData()
      
      // make sure the last row is visible
      if self._tableView.numberOfRows > 0 {
        
        self._tableView.scrollRowToVisible(self._tableView.numberOfRows - 1)
      }
    }
  }
  /// Refresh the Objects TableView & make its last row visible
  ///
  internal func reloadObjectsTable() {
    
    DispatchQueue.main.async { [unowned self] in
      // reload the table
      self._objectsTableView?.reloadData()
      
      // make sure the last row is visible
//      if self._objectsTableView?.numberOfRows ?? 0 > 0 {
//        
//        self._objectsTableView?.scrollRowToVisible(self._objectsTableView!.numberOfRows - 1)
//      }
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Add text to the table
  ///
  /// - Parameter text:       a text String
  ///
  private func showInTable(_ text: String) {
    
    // guard that a session has been started
    guard let startTimestamp = self._parent!._startTimestamp else { return }
    
    // add the Timestamp to the Text
    let timeInterval = Date().timeIntervalSince(startTimestamp)
    textArray.append( String( format: "%8.3f", timeInterval) + " " + text )
    
    reloadTable()
  }
  /// Add text to the Objects table
  ///
  /// - Parameter text:       a text String
  ///
  func showInObjectsTable(_ text: String) {
    
    // guard that a session has been started
    guard let startTimestamp = self._parent!._startTimestamp else { return }
    
    // add the Timestamp to the Text
    let timeInterval = Date().timeIntervalSince(startTimestamp)
    objectsArray.append( String( format: "%8.3f", timeInterval) + " " + text )
    
    reloadObjectsTable()
  }
  /// Parse a Reply message. format: <sequenceNumber>|<hexResponse>|<message>[|<debugOutput>]
  ///
  /// - parameter commandSuffix:    a Command Suffix
  ///
  private func parseReply(_ commandSuffix: String) {
    
    // separate it into its components
    let components = commandSuffix.components(separatedBy: "|")
    
    // ignore incorrectly formatted replies
    if components.count < 2 {
      
      _api.log.msg("Incomplete reply, c\(commandSuffix)", level: .error, function: #function, file: #file, line: #line)
      return
    }
    
    // is there an Object expecting to be notified?
    if let replyTuple = replyHandlers[ components[0] ] {
      
      // an Object is waiting for this reply, send the Command to the Handler on that Object
      
      let command = replyTuple.command
      
      // is there a ReplyHandler for this command?
      //      if let handler = replyTuple.replyTo {
      //
      //        // YES, pass it to the ReplyHandler
      //        handler(command, components[0], components[1], (components.count == 3) ? components[2] : "")
      //      }
      // Show all replies?
      if Defaults[.showAllReplies] {
        
        // SHOW ALL, is it a ping reply?
        if command == "ping" {
          
          // YES, are pings being shown?
          if Defaults[.showPings] {
            
            // YES, show the ping reply
            showInTable("R\(commandSuffix)")
          }
        } else {
          
          // SHOW ALL, it's not a ping reply
          showInTable("R\(commandSuffix)")
        }
        
      } else if components[1] != "0" || (components.count > 2 && components[2] != "") {
        
        // NOT SHOW ALL, only show non-zero replies with additional information
        showInTable("R\(commandSuffix)")
      }
      // Remove the object from the notification list
      replyHandlers[components[0]] = nil
      
    } else {
      
      // no Object is waiting for this reply, show it
      showInTable("R\(commandSuffix)")
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - ApiDelegate methods
  
  /// Process a sent message
  ///
  /// - Parameter text:       text of the command
  ///
  public func sentMessage(_ text: String) {
    
    if !text.hasSuffix("|ping") { showInTable(text) }
    
    if text.hasSuffix("|ping") && Defaults[.showPings] { showInTable(text) }
  }
  /// Process a received message
  ///
  /// - Parameter text:       text received from the Radio
  ///
  public func receivedMessage(_ text: String) {
    
    // get all except the first character
    let suffix = String(text.dropFirst())
    
    // switch on the first character
    switch text[text.startIndex] {
      
    case "C":   // Commands
      showInTable(text)
      
    case "H":   // Handle type
      // convert to drop leading zero (if any)
      let numericHandle = Int( String(suffix), radix: 16 )
      myHandle = String(format: "%X", numericHandle!)
      
      DispatchQueue.main.async { [unowned self] in
        self._parent!._streamId.stringValue = self.myHandle
      }
      
      showInTable(text)
      
    case "M":   // Message Type
      showInTable(text)
      
    case "R":   // Reply Type
      parseReply(suffix)
      
    case "S":   // Status type
      // format: <apiHandle>|<message>, where <message> is of the form: <msgType> <otherMessageComponents>
      
      showInTable(text)
      
    case "V":   // Version Type
      showInTable(text)
      
    default:    // Unknown Type
      _api.log.msg("Unexpected Message Type from radio, \(text[text.startIndex])", level: .error, function: #function, file: #file, line: #line)
    }
  }
  /// Add a Reply Handler for a specific Sequence/Command
  ///
  /// - Parameters:
  ///   - sequenceId:         sequence number of the Command
  ///   - replyTuple:         a Reply Tuple
  ///
  public func addReplyHandler(_ sequenceId: SequenceId, replyTuple: ReplyTuple) {
    
    // add the handler
    replyHandlers[sequenceId] = replyTuple
  }
  /// Process the Reply to a command, reply format: <value>,<value>,...<value>
  ///
  /// - Parameters:
  ///   - command:            the original command
  ///   - seqNum:             the Sequence Number of the original command
  ///   - responseValue:      the response value
  ///   - reply:              the reply
  ///
  public func defaultReplyHandler(_ command: String, seqNum: String, responseValue: String, reply: String) {
    
    // unused in xAPITester
  }
  /// Receive a UDP Stream packet
  ///
  /// - Parameter vita: a Vita packet
  ///
  public func vitaParser(_ vitaPacket: Vita) {
    
    // unused in xAPITester
    
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - LogHandlerDelegate methods
  
  /// Process log messages
  ///
  /// - Parameters:
  ///   - msg:        a message
  ///   - level:      the severity level of the message
  ///   - function:   the name of the function creating the msg
  ///   - file:       the name of the file containing the function
  ///   - line:       the line number creating the msg
  ///
  public func msg(_ msg: String, level: MessageLevel, function: StaticString, file: StaticString, line: Int ) -> Void {
    
    // Show API log messages
    showInTable("----- \(msg) -----")
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - NSTableView DataSource methods
  
  ///
  ///
  /// - Parameter aTableView: the TableView
  /// - Returns:              number of rows
  ///
  public func numberOfRows(in aTableView: NSTableView) -> Int {
    
    if aTableView == _tableView {
      
      return _filteredTextArray.count
      
    } else {
      
      return _filteredObjectsArray.count
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - NSTableView Delegate methods
  
  /// Return a view to be used for the row/column
  ///
  /// - Parameters:
  ///   - tableView:          the TableView
  ///   - tableColumn:        the current TableColumn
  ///   - row:                the current row number
  /// - Returns:              the view for the column & row
  ///
  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    
    // get a view for the cell
    let view = tableView.makeView(withIdentifier: tableColumn!.identifier, owner:self) as! NSTableCellView
    
    // Which table?
    if tableView === _tableView! {
      
      // validate the index
      if _filteredTextArray.count - 1 >= row {
        
        // Replies & Commands, get the text including Timestamp
        let rowText = _filteredTextArray[row]
        
        // get the text without the Timestamp
        let msgText = String(rowText.dropFirst(9))
        
        // determine the type of text, assign a background color
        if msgText.hasPrefix("-----") {                                         // application messages
          
          // application messages from this app
          view.textField!.backgroundColor = Defaults[.messageColor]
          
        } else if msgText.hasPrefix("c") || msgText.hasPrefix("C") {
          
          // commands sent by this app
          view.textField!.backgroundColor = Defaults[.commandColor]
          
        } else if msgText.hasPrefix("r") || msgText.hasPrefix("R") {
          
          // reply messages
          view.textField!.backgroundColor = Defaults[.myHandleColor]
          
        } else if msgText.hasPrefix("v") || msgText.hasPrefix("V") ||
          msgText.hasPrefix("h") || msgText.hasPrefix("H") ||
          msgText.hasPrefix("m") || msgText.hasPrefix("M") {
          
          // messages not directed to a specific client
          view.textField!.backgroundColor = Defaults[.neutralColor]
          
        } else if msgText.hasPrefix("s" + myHandle) || msgText.hasPrefix("S" + myHandle) {
          
          // status sent to myHandle
          view.textField!.backgroundColor = Defaults[.myHandleColor]
          
        } else {
          
          // status sent to a handle other than mine
          view.textField!.backgroundColor = Defaults[.otherHandleColor]
        }
        // set the font
        view.textField!.font = _font
        
        // set the text
        view.textField!.stringValue = Defaults[.showTimestamps] ? rowText : msgText
      }
      
    }
    else {
      
      // validate the index
      if _filteredObjectsArray.count - 1 >= row {
        
        // Objects, get the text including Timestamp
        let rowText = _filteredObjectsArray[row]
        
        // get the text without the Timestamp
        let msgText = String(rowText.dropFirst(9))
        
        // determine the type of text, assign a background color
        if msgText.hasPrefix("Radio") {
          
          // ADDED or REMOVED Radio messages
          view.textField!.backgroundColor = SplitViewController.kRadioColor
          
        } else if msgText.hasPrefix("STARTED") {
          
          // Subordinate messages
          view.textField!.backgroundColor = SplitViewController.kStartedColor

        } else if msgText.hasSuffix("stream") {
          
          // Subordinate messages
          view.textField!.backgroundColor = SplitViewController.kStreamColor
          
        } else if msgText.hasPrefix("    ") {
          
          // Subordinate messages
          view.textField!.backgroundColor = SplitViewController.kSubordinateColor
          
        } else {
          
          // Other messages
          view.textField!.backgroundColor = SplitViewController.kOtherColor
        }
        // set the font
        view.textField!.font = _font
        
        // set the text
        view.textField!.stringValue = msgText
      }
    }
    return view
  }

  public func redraw() {
    
    DispatchQueue.main.async { [unowned self] in
      self.objectsArray.removeAll()
      
      // Radio
      if let radio = Api.sharedInstance.activeRadio {
        self.showInObjectsTable("Radio          name = \(radio.nickname ?? "")  model = \(radio.model)")
        
        // Panadapters
        for (_, panadapter) in self._api.radio!.panadapters {
          self.showInObjectsTable("Panadapter     \(panadapter.id.hex)  center = \(panadapter.center.hzToMhz())  bandwidth = \(panadapter.bandwidth.hzToMhz())")

          // Waterfall for this Panadapter
          for (_, waterfall) in self._api.radio!.waterfalls where panadapter.id == waterfall.panadapterId {
            self.showInObjectsTable("      Waterfall      \(waterfall.id.hex) stream")
          }
          
          // Slices for this Panadapter
          for (_, slice) in self._api.radio!.slices where panadapter.id == slice.panadapterId {
            self.showInObjectsTable("      Slice          \(slice.id)  pan = \(slice.panadapterId.hex)  frequency = \(slice.frequency.hzToMhz())  filterLow = \(slice.filterLow)  filterHigh = \(slice.filterHigh)  active = \(slice.active)  locked = \(slice.locked)")
            
            // Audio Stream for this Slice
            for (_, audioStream) in self._api.radio!.audioStreams where audioStream.slice!.id == slice.id {
              self.showInObjectsTable("           DaxAudio       \(audioStream.id.hex) stream")
            }
            
            // Meters for this Slice
            for (_, meter) in self._api.radio!.meters where meter.source.hasPrefix("slc") {
              self.showInObjectsTable("           Meter  id = \(("00" + meter.id).suffix(3))  name = \(meter.name)  desc = \(meter.desc)  units = \(meter.units)  low = \(meter.low)  high = \(meter.high)  fps = \(meter.fps)")
            }

          }
          // IQ Streams for this Panadapter
          for (_, iqStream) in self._api.radio!.iqStreams where panadapter.id == iqStream.pan {
            self.showInObjectsTable("      DaxIq          \(iqStream.id.hex) stream")
          }
        }
        // Tnfs
        for (_, tnf) in self._api.radio!.tnfs {
          self.showInObjectsTable("Tnf            \(tnf.id)  frequency = \(tnf.frequency)  width = \(tnf.width)  depth = \(tnf.depth)  permanent = \(tnf.permanent)")
        }
        // Amplifiers
        for (_, amplifier) in self._api.radio!.amplifiers {
          self.showInObjectsTable("Amplifier      \(amplifier.id)")
        }
        // Memories
        for (_, memory) in self._api.radio!.memories {
          self.showInObjectsTable("Memory         \(memory.id)")
        }
        // Meters (not for a Slice)
        for (_, meter) in self._api.radio!.meters where !meter.source.hasPrefix("slc") {
          let source = meter.source[0..<3]
          self.showInObjectsTable("Meter (\(source))    number = \(("00" + meter.number).suffix(3))  id = \(("00" + meter.id).suffix(3))  name = \(meter.name)  desc = \(meter.desc)  units = \(meter.units)  low = \(meter.low)  high = \(meter.high)  fps = \(meter.fps)")
        }
        // Mic Audio Streams
        for (_, micAudioStream) in self._api.radio!.micAudioStreams {
          self.showInObjectsTable("DaxMicAudio    \(micAudioStream.id.hex) stream")
        }
        // Opus Streams
        for (_, opusStream) in self._api.radio!.opusStreams {
          self.showInObjectsTable("Opus           \(opusStream.id) stream")
        }
        // TX Audio Streams
        for (_, txAudioStream) in self._api.radio!.txAudioStreams {
          self.showInObjectsTable("DaxTxAudio     \(txAudioStream.id.hex) stream")
        }
        // USB Cables
        for (_, usbCable) in self._api.radio!.usbCables {
          self.showInObjectsTable("UsbCable       \(usbCable.id)")
        }
        // Xvtrs
        for (_, xvtr) in self._api.radio!.xvtrs {
          self.showInObjectsTable("Xvtr           \(xvtr.id)")
        }
      }
    }
  }
}
