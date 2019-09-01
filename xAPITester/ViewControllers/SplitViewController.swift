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

class SplitViewController: NSSplitViewController, ApiDelegate, NSTableViewDelegate, NSTableViewDataSource {
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public enum MessagesFilters: Int {
    case none = 0
    case prefix
    case contains
    case exclude
    case myHandle
    case handle
  }
  public enum ObjectsFilters: Int {
    case none = 0
    case prefix
    case contains
    case exclude
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  @IBOutlet internal var _tableView           : NSTableView!
  @IBOutlet internal var _objectsTableView    : NSTableView!

  public var myHandle: UInt32? {
    get { return _objectQ.sync { _myHandle } }
    set { _objectQ.sync(flags: .barrier) { _myHandle = newValue } } }
  
  internal var objects: [String] {
    get { return _objectQ.sync { _objects } }
    set { _objectQ.sync(flags: .barrier) { _objects = newValue } } }
  
  internal var messages: [String] {
    get { return _objectQ.sync { _messages } }
    set { _objectQ.sync(flags: .barrier) { _messages = newValue } } }
  
  internal var replyHandlers: [SequenceId: ReplyTuple] {
    get { return _objectQ.sync { _replyHandlers } }
    set { _objectQ.sync(flags: .barrier) { _replyHandlers = newValue } } }
  
  internal var _filteredMessages              : [String] {                  // filtered version of textArray
    get {
      switch MessagesFilters(rawValue: Defaults[.filterByTag]) ?? .none {
      
      case .none:       return messages
      case .prefix:     return messages.filter { $0.contains("|" + Defaults[.filter]) }
      case .contains:   return messages.filter { $0.contains(Defaults[.filter]) }
      case .exclude:    return messages.filter { !$0.contains(Defaults[.filter]) }
      case .myHandle:   return messages.filter { $0.dropFirst(9).hasPrefix("S" + myHandle!.toHex("%08X")) }
      case .handle:     return messages.filter { $0.dropFirst(9).hasPrefix("S" + Defaults[.filter]) }
      }
    }}
  internal var _filteredObjects           : [String] {                  // filtered version of objectsArray
    get {
      switch ObjectsFilters(rawValue: Defaults[.filterObjectsByTag]) ?? .none {
      
      case .none:       return objects
      case .prefix:     return objects.filter { $0.dropFirst(9).hasPrefix(Defaults[.filterObjects]) }
      case .contains:   return objects.filter { $0.contains(Defaults[.filterObjects]) }
      case .exclude:    return objects.filter { !$0.contains(Defaults[.filterObjects]) }
      }
    }}
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance          // Api to the Radio
  private let _log                            = (NSApp.delegate as! AppDelegate)
  internal weak var _parent                   : ViewController?
  internal let _objectQ                       = DispatchQueue(label: AppDelegate.kName + ".objectQ", attributes: [.concurrent])
  
  private var _font                           : NSFont!                     // font for table entries
  
  private var _myHandle                       : Handle?
  private var _replyHandlers                  = [SequenceId: ReplyTuple]()  // Dictionary of pending replies
  private var _messages                       = [String]()                  // backing storage for the table
  private var _objects                        = [String]()                  // backing storage for the objects table

  private var _timeoutTimer                   : DispatchSourceTimer!          // timer fired every "checkInterval"
  private var _timerQ                         = DispatchQueue(label: "xAPITester" + ".timerQ")
  private var _guiClients                     = [GuiClient]()

  private let kAutosaveName                   = NSSplitView.AutosaveName(AppDelegate.kName + "SplitView")
  private let checkInterval                   : TimeInterval = 1.0
  
  // ----------------------------------------------------------------------------
  // MARK: - Overridden methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    splitView.autosaveName = kAutosaveName
    
    _api.testerDelegate = self
    
    // setup the font
    _font = NSFont(name: Defaults[.fontName], size: CGFloat(Defaults[.fontSize] ))!
    _tableView.rowHeight = _font.capHeight * 1.7
    
    // setup & start the Objects table timer
    timerSetup()
    
    notificationsAdd()
  }

  deinit {
    // stop the Objects table timer
    _timeoutTimer?.cancel()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Action methods
  
  /// 1st Responder to the Format->Font->Bigger menu (or Command=)
  ///
  /// - Parameter sender:     the sender
  ///
  @IBAction func fontBigger(_ sender: AnyObject) {
    
    fontSize(larger: true)
  }
  /// 1st Responder to the Format->Font->Smaller menu (or Command-)
  ///
  /// - Parameter sender:     the sender
  ///
  @IBAction func fontSmaller(_ sender: AnyObject) {
    
    fontSize(larger: false)
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
    }
  }
  
  internal func removeApiTester() {
    
    _guiClients = _guiClients.filter { $0.program != AppDelegate.kName }
  }

  internal func removeAllGuiClients() {
    _guiClients.removeAll()
  }

  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Adjust the font size larger or smaller (within limits)
  ///
  /// - Parameter larger:           larger?
  ///
  private func fontSize(larger: Bool) {
    
    // limit the font size
    var newSize =  Defaults[.fontSize] + (larger ? +1 : -1)
    if larger {
      if newSize > Defaults[.fontMaxSize] { newSize = Defaults[.fontMaxSize] }
    } else {
      if newSize < Defaults[.fontMinSize] { newSize = Defaults[.fontMinSize] }
    }
    
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
  /// Setup & start the Objects table timer
  ///
  private func timerSetup() {
    // create a timer to periodically redraw the objects table
    _timeoutTimer = DispatchSource.makeTimerSource(flags: [.strict], queue: _timerQ)
    
    // Set timer with 100 millisecond leeway
    _timeoutTimer.schedule(deadline: DispatchTime.now(), repeating: checkInterval, leeway: .milliseconds(100))      // Every second +/- 10%
    
    // set the event handler
    _timeoutTimer.setEventHandler { [ unowned self] in
      
      // redraw the objects table when the timer fires
      self.refreshObjects()
    }
    // start the timer
    _timeoutTimer.resume()
  }
  /// Add text to the table
  ///
  /// - Parameter text:       a text String
  ///
  private func showInTable(_ text: String) {
    
    // guard that a session has been started
//    guard let startTimestamp = self._parent!._startTimestamp else { return }

    // add the Timestamp to the Text
    let timeInterval = Date().timeIntervalSince(self._parent!._startTimestamp!)
    messages.append( String( format: "%8.3f", timeInterval) + " " + text )
    
    reloadTable()
  }
  /// Add text to the Objects table
  ///
  /// - Parameter text:       a text String
  ///
  func showInObjectsTable(_ text: String) {
    
//    // guard that a session has been started
//    guard let startTimestamp = self._parent!._startTimestamp else { return }
//
    // add the Timestamp to the Text
//    let timeInterval = Date().timeIntervalSince(startTimestamp)
//    objects.append( String( format: "%8.3f", timeInterval) + " " + text )
    objects.append( text )

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
      _log.msg("Incomplete reply, c\(commandSuffix)", level: MessageLevel.error, function: #function, file: #file, line: #line)
      return
    }
    
    // is there an Object expecting to be notified?
    if let replyTuple = replyHandlers[ components[0] ] {
      
      switch (Defaults[.showAllReplies], components[1], components[2]) {
        
      // NOT SHOW ALL, "0" response
      case (false, "0", _):   break
        
      // SHOW ALL, "0" response
      case (true, "0", _):
        
        switch replyTuple.command {
        case "ping":
          if Defaults[.showPings] { showInTable("R\(commandSuffix),  command = \(replyTuple.command)") }
        default:
          showInTable("R\(commandSuffix),  command = \(replyTuple.command)")
        }
      
      // ANY, non-zero, no explanation
      case (_, _, ""):        showInTable("R\(commandSuffix)\(flexErrorString(errorCode: components[1])),  command = \(replyTuple.command)")
        
      // ANY, non-zero, with explanation
      case (_, _, _):         showInTable("R\(commandSuffix),  command = \(replyTuple.command)")
      }
      
    } else {
      
      // no Object is waiting for this reply, show it
      if components[2] == "" {
        showInTable("R\(commandSuffix)\(flexErrorString(errorCode: components[1]))")
      
      } else {
        showInTable("R\(commandSuffix)")
      }
    }
  }
  /// Redraw the Objects table
  ///
  private func refreshObjects() {
    
    DispatchQueue.main.async { [unowned self] in
      self.objects.removeAll()
      self.reloadObjectsTable()
      
      // ApiTester
      if let activeRadio = Api.sharedInstance.activeRadio, let handle = Api.sharedInstance.connectionHandle {
        self.showInObjectsTable("xAPITester  \(Defaults[.isGui] ? "Gui Client" : "NON-Gui Client") (\(Defaults[.isBound] ? "Bound" : "Unbound")):  handle->\(handle.hex)  program->\(self._api.clientProgram)  station->\(self._api.clientStation)  name->\(activeRadio.nickname)  model->\(activeRadio.model), version->\(activeRadio.firmwareVersion)" +
          ", atu->\(Api.sharedInstance.radio!.atuPresent ? "Yes" : "No"), gps->\(Api.sharedInstance.radio!.gpsPresent ? "Yes" : "No")" +
          ", scu's->\(Api.sharedInstance.radio!.numberOfScus)")
        
        self.showInObjectsTable("\n")
      }
      // Gui Clients
      for client in self._guiClients {
        
        
        
        self.showInObjectsTable("DISCOVERED  Gui-Client:      handle->\(client.handle.hex)  program->\(client.program)  station->\(client.station)" +
          " id->\(client.clientId ?? "")")
      
        if let _ = Api.sharedInstance.activeRadio {
          for stream in self._api.radio!.remoteRxAudioStreams.values where stream.clientHandle == client.handle {
            self.showInObjectsTable("      RemoteRxAudioStream  \(stream.streamId.hex):  clientHandle->\(stream.clientHandle.hex)  compression->\(stream.compression)  ip->\(stream.ip)")
          }
          
          // RemoteTxAudioStreams
          for (_, stream) in self._api.radio!.remoteTxAudioStreams where stream.clientHandle == client.handle {
            self.showInObjectsTable("      RemoteTxAudioStream  \(stream.streamId.hex):  clientHandle->\(stream.clientHandle.hex)  compression->\(stream.compression)  ip->\(stream.ip)")
          }

          // Panadapters
          for (_, panadapter) in self._api.radio!.panadapters where panadapter.clientHandle == client.handle {
            self.showInObjectsTable("      Panadapter     \(panadapter.streamId.hex)  center->\(panadapter.center.hzToMhz)  bandwidth->\(panadapter.bandwidth.hzToMhz)")

            // Waterfall for this Panadapter
            for (_, waterfall) in self._api.radio!.waterfalls where panadapter.streamId == waterfall.panadapterId {
              self.showInObjectsTable("         Waterfall   \(waterfall.streamId.hex)  autoBlackEnabled->\(waterfall.autoBlackEnabled),  colorGain->\(waterfall.colorGain),  blackLevel->\(waterfall.blackLevel),  duration->\(waterfall.lineDuration)")
            }
            
           
            // IQ Streams for this Panadapter
            for (_, stream) in self._api.radio!.daxIqStreams where stream.clientHandle == client.handle && panadapter.streamId == stream.pan {
              self.showInObjectsTable("         DaxIq        \(stream.streamId.hex) stream")
            }
            
            // Slices for this Panadapter
            for (_, slice) in self._api.radio!.slices where panadapter.streamId == slice.panadapterId {
              self.showInObjectsTable("         Slice       \(slice.id)  frequency->\(slice.frequency.hzToMhz)  filterLow->\(slice.filterLow)  filterHigh->\(slice.filterHigh)  active->\(slice.active)  locked->\(slice.locked)")
              
              // DaxRxAudioStream for this Slice
              for (_, stream) in self._api.radio!.daxRxAudioStreams {
                if stream.slice?.id == slice.id {
                  self.showInObjectsTable("            DaxAudio       \(stream.streamId.hex) stream")
                }
              }
              
              // sort the Meters for this Slice
              for (_, meter) in self._api.radio!.meters.sorted(by: { $0.value.number < $1.value.number }) {
                if meter.source == "slc" && meter.group == slice.id {
                  self.showInObjectsTable("            Meter \(("00" + meter.number).suffix(3))  name->\(meter.name)  desc->\(meter.desc)  units->\(meter.units)  low ->\(meter.low)  high ->\(meter.high)  fps->\(meter.fps)")
                }
              }
            }
          }
          self.showInObjectsTable("\n")
        }
      }
      
      // FIXME: parse by Handle
      // FIXME: add RemoteRxAudioStream & RemoteTxAudioStream
      
      // Items not connected to a Client
      if let _ = Api.sharedInstance.activeRadio {
        
        // DaxIqStreams
        for stream in self._api.radio!.daxIqStreams.values where stream.pan == 0 {
          self.showInObjectsTable("DaxIqStream          \(stream.streamId.hex):  panadapter-> -not assigned-")
        }
        // DaxMicAudioStream
        for stream in self._api.radio!.daxMicAudioStreams.values {
          self.showInObjectsTable("DaxMicAudio:    \(stream.streamId.hex) stream")
        }
        // DaxRxAudioStreams
        for stream in self._api.radio!.daxRxAudioStreams.values where stream.slice == nil {
          self.showInObjectsTable("DaxRxAudioStream     \(stream.streamId.hex):  slice-> -not assigned-")
        }
        // DaxTxAudioStreams
        for stream in self._api.radio!.daxTxAudioStreams.values {
          self.showInObjectsTable("DaxTxAudioStream:    \(stream.streamId.hex)")
        }
        // Tnfs
        for tnf in self._api.radio!.tnfs.values {
          self.showInObjectsTable("Tnf:            \(tnf.id)  frequency->\(tnf.frequency)  width->\(tnf.width)  depth->\(tnf.depth)  permanent->\(tnf.permanent)")
        }
        // Amplifiers
        for amplifier in self._api.radio!.amplifiers.values {
          self.showInObjectsTable("Amplifier:      \(amplifier.id)")
        }
        // Memories
        for memory in self._api.radio!.memories.values {
          self.showInObjectsTable("Memory:         \(memory.id)")
        }
        // USB Cables
        for usbCable in self._api.radio!.usbCables.values {
          self.showInObjectsTable("UsbCable:       \(usbCable.id)")
        }
        // Xvtrs
        for xvtr in self._api.radio!.xvtrs.values {
          self.showInObjectsTable("Xvtr:           \(xvtr.id)")
        }
        // Meters (not for a Slice)
        let sortedMeters = self._api.radio!.meters.sorted(by: {
          ( $0.value.source[0..<3], Int($0.value.group.suffix(3), radix: 10)!, $0.value.number.suffix(3) ) <
            ( $1.value.source[0..<3], Int($1.value.group.suffix(3), radix: 10)!, $1.value.number.suffix(3) )
        })
        for (_, meter) in sortedMeters where !meter.source.hasPrefix("slc") {
          self.showInObjectsTable("Meter:          source->\(meter.source[0..<3])  group->\(("00" + meter.group).suffix(3))  number->\(("00" + meter.number).suffix(3))  name->\(meter.name)  desc->\(meter.desc)  units->\(meter.units)  low->\(meter.low)  high->\(meter.high)  fps->\(meter.fps)")
        }
      }
    }
  }

  private func removeAllStreams() {
    
//    Api.sharedInstance.radio!.opusStreams.removeAll()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Notification Methods
  
  /// Add subsciptions to Notifications
  ///     (as of 10.11, subscriptions are automatically removed on deinit when using the Selector-based approach)
  ///
  private func notificationsAdd() {
    
    NC.makeObserver(self, with: #selector(guiClientHasBeenAdded(_:)), of: .guiClientHasBeenAdded)
    NC.makeObserver(self, with: #selector(guiClientHasBeenRemoved(_:)), of: .guiClientHasBeenRemoved)
  }
  /// Process guiClientHasBeenAdded Notification
  ///
  /// - Parameter note:       a Notification instance
  ///
  @objc private func guiClientHasBeenAdded(_ note: Notification) {
    
    if let guiClient = note.object as? GuiClient {

      _log.msg("Gui Client Added:   Id = \(guiClient.clientId ?? "")", level: .info, function: #function, file: #file, line: #line)

      if let index = _guiClients.firstIndex(of: guiClient) {
        // a guiClientHasBeenAdded was received earlier, update it
        _guiClients[index] = guiClient
      } else {
        // the guiClientHasBeenUpdated arrived without a prior guiClientHasBeenAdded, add it
        _guiClients.append(guiClient)
        
        if Defaults[.isGui] && Defaults[.myClientId] == "" && guiClient.handle == _api.connectionHandle {
          Defaults[.myClientId] = guiClient.clientId ?? ""
          
          _log.msg("Gui \(AppDelegate.kName) App Client Id: \(guiClient.clientId ?? "")", level: .info, function: #function, file: #file, line: #line)
        }
        // v2.5.1 can only be one Gui client
        if Defaults[.isGui] == false && Defaults[.isBound] == true && Defaults[.boundClientId] == "" {
          Defaults[.boundClientId] = guiClient.clientId
          
          // cause this Non-Gui Client to be bound
          _api.radio?.boundClientId = UUID(uuidString: Defaults[.myClientId] ?? "")
          
          _log.msg("Non-Gui \(AppDelegate.kName) Bound To Added Client Id: \(guiClient.clientId ?? "")", level: .info, function: #function, file: #file, line: #line)
          
        } else if Defaults[.isGui] == false && Defaults[.isBound] == true && Defaults[.boundClientId] != "" {
          _log.msg("Non-Gui \(AppDelegate.kName) Bound To Known Client Id: \(Defaults[.boundClientId]!)", level: .info, function: #function, file: #file, line: #line)
        }

      }
    }
  }
  /// Process guiClientHasBeenRemoved Notification
  ///
  /// - Parameter note:       a Notification instance
  ///
  @objc private func guiClientHasBeenRemoved(_ note: Notification) {
    
    if let handle = note.object as? Handle {
      
      // find the GuiClient
      for (i, guiClient) in _guiClients.enumerated() {
        if guiClient.handle == handle {
          _guiClients.remove(at: i)

          _log.msg("Gui Client Removed: Handle = \(handle.hex)", level: .info, function: #function, file: #file, line: #line)

          return
        }
      }
      // none found
      return
    }
  }

  // ----------------------------------------------------------------------------
  // MARK: - Api Delegate methods
  
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
      // convert to UInt32
      myHandle = suffix.handle ?? 0
      
      DispatchQueue.main.async { [unowned self] in
        self._parent!._streamIdTextField.stringValue = self.myHandle!.toHex("%08X")
      }
      
      showInTable(text)
      
    case "M":   // Message Type
      showInTable(text)
      
    case "R":   // Reply Type
      parseReply(suffix)
      
    case "S":   // Status type
      // format: <apiHandle>|<message>, where <message> is of the form: <msgType> <otherMessageComponents>
      
      let components = text.split(separator: "|")
      if components[1].hasPrefix("client") && components[1].contains("disconnected"){
        
        removeAllStreams()
      }
      
      showInTable(text)
      
    case "V":   // Version Type
      showInTable(text)
      
    default:    // Unknown Type
//      _api.log.msg("Unexpected Message Type from radio, \(text[text.startIndex])", level: .error, function: #function, file: #file, line: #line)

      _log.msg("Unexpected Message Type from radio, \(text[text.startIndex] as! CVarArg))", level: MessageLevel.error, function: #function, file: #file, line: #line)
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
//  public func msg(_ msg: String, level: OSType, function: StaticString, file: StaticString, line: Int ) -> Void {
  public func msg(_ msg: String) -> Void {

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
      
      return _filteredMessages.count
      
    } else {
      
      return _filteredObjects.count
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
      if _filteredMessages.count - 1 >= row {
        
        // Replies & Commands, get the text including Timestamp
        let rowText = _filteredMessages[row]
        
        // get the text without the Timestamp
        let msgText = String(rowText.dropFirst(9))
        
        // determine the type of text, assign a background color
        if msgText.hasPrefix("-----") {                                                   // messages (black)
          view.textField!.backgroundColor = NSColor.black

        } else if msgText.lowercased().hasPrefix("c") {                                   // Commands (red)
          view.textField!.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3)

        } else if msgText.lowercased().hasPrefix("r") {                                   // Replies (lightGray)
          view.textField!.backgroundColor = NSColor.lightGray.withAlphaComponent(0.3)

        } else if msgText.lowercased().hasPrefix("s0") {                                  // S0 (purple)
          view.textField!.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.5)

        } else if msgText.lowercased().hasPrefix("s" + myHandle!.toHex("%08x")) {         // My Status (red)
          view.textField!.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3)

        } else if msgText.lowercased().hasPrefix("s") {                                   // Other Status (green)
          view.textField!.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3)

        } else {                                                                          // Other (brown)
          view.textField!.backgroundColor = NSColor.systemBrown.withAlphaComponent(0.3)
        }
        // set the font
        view.textField!.font = _font
        
        // set the text
        view.textField!.stringValue = Defaults[.showTimestamps] ? rowText : msgText
      }
      
    }
    else {
      
      // validate the index
      if _filteredObjects.count - 1 >= row {
        
        // Objects, get the text including Timestamp
        let rowText = _filteredObjects[row]
        // get the text without any leading spaces
        let textType = rowText.trimmingCharacters(in: .whitespaces)
        
        // determine the type of text, assign a background color
        if textType.hasPrefix("xAPITester") {
          view.textField!.backgroundColor = NSColor.systemRed.withAlphaComponent(0.4)

        } else if textType.hasPrefix("DISCOVERED") {
          view.textField!.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.4)
          
        } else if textType.hasPrefix("Panadapter") || textType.hasPrefix("Waterfall") || textType.hasPrefix("Slice") {
          view.textField!.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.4)
          
        } else if textType.hasPrefix("DaxIq") || textType.hasPrefix("DaxAudio"){
          view.textField!.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.4)

        } else if textType.hasPrefix("Meter:") {
          view.textField!.backgroundColor = NSColor.systemBrown.withAlphaComponent(0.4)
          
        } else if textType.hasPrefix("Meter ") {
          view.textField!.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.4)
          
        } else if textType.hasPrefix("\n") {
          view.textField!.backgroundColor = NSColor.black

        } else {
          view.textField!.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.4)
        }
        // set the font
        view.textField!.font = _font
        
        // set the text
        view.textField!.stringValue = rowText
      }
    }
    return view
  }
}
