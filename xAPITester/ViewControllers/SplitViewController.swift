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
  
  static let kAddedColor                      = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.2)
  static let kRemovedColor                    = NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.2)
  static let kOtherColor                      = NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.2)
  static let kRadioColor                      = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.2)
  
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
  
  internal var audioHandlers: [DaxStreamId: AudioHandler] {
    get { return _objectQ.sync { _audioHandlers } }
    set { _objectQ.sync(flags: .barrier) { _audioHandlers = newValue } } }
  
  internal var iqHandlers: [DaxStreamId: IqHandler] {
    get { return _objectQ.sync { _iqHandlers } }
    set { _objectQ.sync(flags: .barrier) { _iqHandlers = newValue } } }
  
  internal var panadapterHandlers: [PanadapterId: PanadapterHandler] {
    get { return _objectQ.sync { _panadapterHandlers } }
    set { _objectQ.sync(flags: .barrier) { _panadapterHandlers = newValue } } }
  
  internal var waterfallHandlers: [WaterfallId: WaterfallHandler] {
    get { return _objectQ.sync { _waterfallHandlers } }
    set { _objectQ.sync(flags: .barrier) { _waterfallHandlers = newValue } } }
  
  internal var replyHandlers: [SequenceId: ReplyTuple] {
    get { return _objectQ.sync { _replyHandlers } }
    set { _objectQ.sync(flags: .barrier) { _replyHandlers = newValue } } }
  
  internal var _filteredTextArray              : [String] {                  // filtered version of textArray
    get {
      switch FilterTag(rawValue: Defaults[.filterByTag]) ?? .none {
      case .none:
        return textArray
        
      case .prefix:
        return textArray.filter { $0.hasPrefix(Defaults[.filter]) }
        
      case .contains:
        return textArray.filter { $0.contains(Defaults[.filter]) }
        
      case .exclude:
        return textArray.filter { !$0.contains(Defaults[.filter]) }
        
      case .streamId:
        return textArray.filter { $0.hasPrefix("S" + myHandle) }
      }
    }}
  internal var _filteredObjectsArray           : [String] {                  // filtered version of objectsArray
    get {
      switch FilterObjectsTag(rawValue: Defaults[.filterObjectsByTag]) ?? .none {
      case .none:
        return objectsArray
        
      case .prefix:
        return objectsArray.filter { $0.hasPrefix(Defaults[.filterObjects]) }
        
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
  private var _audioHandlers                  = [DaxStreamId: AudioHandler]()
  private var _iqHandlers                     = [DaxStreamId: IqHandler]()
  private var _panadapterHandlers             = [PanadapterId: PanadapterHandler]()
  private var _waterfallHandlers              = [WaterfallId: WaterfallHandler]()
  private var _textArray                      = [String]()                  // backing storage for the table
  private var _objectsArray                   = [String]()                  // backing storage for the objects table
  
  private let kAutosaveName                   = NSSplitView.AutosaveName(rawValue: kClientName + "SplitView")
  
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
    
    addNotifications()
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
      if self._objectsTableView?.numberOfRows ?? 0 > 0 {
        
        self._objectsTableView?.scrollRowToVisible(self._objectsTableView!.numberOfRows - 1)
      }
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
      if let handler = replyTuple.replyTo {
        
        // YES, pass it to the ReplyHandler
        handler(command, components[0], components[1], (components.count == 3) ? components[2] : "")
      }
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
        
        // NOT SHOW ALL, only show non-zero replies with no additional information
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
        if msgText.hasPrefix("ADDED   Radio") || msgText.hasPrefix("REMOVED Radio") {
          
          // ADDED or REMOVED Radio messages
          view.textField!.backgroundColor = SplitViewController.kRadioColor
          
        } else if msgText.hasPrefix("ADDED") {
          
          // ADDED messages
          view.textField!.backgroundColor = SplitViewController.kAddedColor
          
        } else if msgText.hasPrefix("REMOVED") {
          
          // REMOVED messages
          view.textField!.backgroundColor = SplitViewController.kRemovedColor
          
        } else {
          
          // Other messages
          view.textField!.backgroundColor = SplitViewController.kOtherColor
        }
        // set the font
        view.textField!.font = _font
        
        // set the text
        view.textField!.stringValue = Defaults[.showTimestamps] ? rowText : msgText
      }
    }
    return view
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Notification Methods
  
  /// Add subsciptions to Notifications
  ///     (as of 10.11, subscriptions are automatically removed on deinit when using the Selector-based approach)
  ///
  private func addNotifications() {
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .amplifierHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .amplifierWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .audioStreamHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .audioStreamWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .iqStreamHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .iqStreamWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .memoryHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .memoryWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .meterHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .meterWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .micAudioStreamHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .micAudioStreamWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .opusHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .opusWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .panadapterHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .panadapterWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .profileHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .profileWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .radioHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .radioWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .sliceHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .sliceWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .tnfHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .tnfWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .txAudioStreamHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .txAudioStreamWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .usbCableHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .usbCableWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .waterfallHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .waterfallWillBeRemoved, object: nil)
    
    NC.makeObserver(self, with: #selector(hasBeenAdded(_:)), of: .xvtrHasBeenAdded, object: nil)
    NC.makeObserver(self, with: #selector(willBeRemoved(_:)), of: .xvtrWillBeRemoved, object: nil)    
  }
  @objc private func hasBeenAdded(_ note: Notification) {
    var text = "ADDED   "
    
    if let obj = note.object {
      
      switch obj {
      case is Amplifier:
        text += "Amplifier      \((obj as! Amplifier).id)"
        
      case is AudioStream:
        let audio = obj as! AudioStream
        text += "AudioStream    \(audio.id.hex)"
        audioHandlers[audio.id] = AudioHandler(id: audio.id, delegate: self)
        _api.radio!.audioStreams[audio.id]!.delegate = audioHandlers[audio.id]!
        
      case is IqStream:
        let iq = obj as! IqStream
        text += "IqStream       \(iq.id.hex)"
        iqHandlers[iq.id] = IqHandler(id: iq.id, delegate: self)
        _api.radio!.iqStreams[iq.id]!.delegate = iqHandlers[iq.id]!
        
      case is Memory:
        text += "Memory         \((obj as! Memory).id)"
        
      case is Meter:
        let meter = obj as! Meter
        let source = meter.source[0..<3]
        let label = (source == "slc" ? "slice  = " : "number = ")
        text += "Meter (\(source))    \(label)\(meter.number), id = \(("00" + meter.id).suffix(3)), name = \(meter.name) desc = \(meter.desc) low = \(meter.low) high = \(meter.high) fps = \(meter.fps)"

      case is MicAudioStream:
        text += "MicAudioStream \((obj as! MicAudioStream).id)"
        
      case is Opus:
        text += "Opus           \((obj as! Opus).id)"
        
      case is Panadapter:
        let panadapter = obj as! Panadapter
        text += "Panadapter     \(panadapter.id.hex) center = \(panadapter.center.hzToMhz()) bandwidth = \(panadapter.bandwidth.hzToMhz())"
        panadapterHandlers[panadapter.id] = PanadapterHandler(id: panadapter.id, delegate: self)
        _api.radio!.panadapters[panadapter.id]!.delegate = panadapterHandlers[panadapter.id]!
        
      case is Profile:
        text += "Profile"
        
      case is Radio:
        let radio = Api.sharedInstance.activeRadio
        text += "Radio          name = \(radio?.nickname ?? "") model = \(radio?.model ?? "")"
        
      case is xLib6000.Slice:
        let slice = obj as! xLib6000.Slice
        text += "Slice          \(slice.id) locked = \(slice.locked), frequency = \(slice.frequency.hzToMhz()), filterLow = \(slice.filterLow), filterHigh = \(slice.filterHigh)"
        
      case is Tnf:
        let tnf = obj as! Tnf
        text += "Tnf            \(tnf.id), width = \(tnf.width), depth = \(tnf.depth), permanent = \(tnf.permanent)"
        
      case is TxAudioStream:
        text += "TxAudioStream  \((obj as! TxAudioStream).id)"
        
      case is UsbCable:
        text += "UsbCable       \((obj as! UsbCable).id)"
        
      case is Waterfall:
        let waterfall = obj as! Waterfall
        text += "Waterfall      \(waterfall.id.hex)"
        waterfallHandlers[waterfall.id] = WaterfallHandler(id: waterfall.id, delegate: self)
        _api.radio!.waterfalls[waterfall.id]!.delegate = waterfallHandlers[waterfall.id]!
        
      case is Xvtr:
        text += "Xvtr           \((obj as! Xvtr).id)"
        
      default:
        text += "Unknown object"
      }
    }
    showInObjectsTable(text)
  }
  
  @objc private func willBeRemoved(_ note: Notification) {
    var text = "REMOVED "
    
    if let obj = note.object {
      
      switch obj {
      case is Amplifier:
        text += "Amplifier      \((obj as! Amplifier).id)"
        
      case is AudioStream:
        let audio = obj as! AudioStream
        _api.radio!.audioStreams[audio.id]!.delegate = nil
        audioHandlers[audio.id] = nil
        text += "AudioStream    \(audio.id.hex)"
        
      case is IqStream:
        let iq = obj as! IqStream
        _api.radio!.iqStreams[iq.id]!.delegate = nil
        iqHandlers[iq.id] = nil
        text += "IqStream       \(iq.id.hex)"
        
      case is Memory:
        text += "Memory         \((obj as! Memory).id)"
        
      case is Meter:
        let meter = obj as! Meter
        let source = meter.source[0..<3]
        let label = (source == "slc" ? "slice  = " : "number = ")
        text += "Meter (\(source))    \(label)\(meter.number), id = \(("00" + meter.id).suffix(3)), name = \(meter.name) desc = \(meter.desc) low = \(meter.low) high = \(meter.high) fps = \(meter.fps)"

      case is MicAudioStream:
        text += "MicAudioStream \((obj as! MicAudioStream).id)"
        
      case is Opus:
        text += "Opus           \((obj as! Opus).id)"
        
      case is Panadapter:
        let panadapter = obj as! Panadapter
        _api.radio!.panadapters[panadapter.id]!.delegate = nil
        panadapterHandlers[panadapter.id] = nil
        text += "Panadapter     \(panadapter.id.hex) center = \(panadapter.center.hzToMhz()) bandwidth = \(panadapter.bandwidth.hzToMhz())"
        
      case is Profile:
        text += "Profile"
        
      case is Radio:
        let radio = Api.sharedInstance.activeRadio
        text += "Radio          name = \(radio?.nickname ?? "") model = \(radio?.model ?? "")"
        
      case is xLib6000.Slice:
        let slice = obj as! xLib6000.Slice
        text += "Slice          \(slice.id) locked = \(slice.locked), frequency = \(slice.frequency.hzToMhz()), filterLow = \(slice.filterLow), filterHigh = \(slice.filterHigh)"

      case is Tnf:
        let tnf = obj as! Tnf
        text += "Tnf            \(tnf.id), width = \(tnf.width), depth = \(tnf.depth), permanent = \(tnf.permanent)"

      case is TxAudioStream:
        text += "TxAudioStream  \((obj as! TxAudioStream).id)"
        
      case is UsbCable:
        text += "UsbCable       \((obj as! UsbCable).id)"
        
      case is Waterfall:
        let waterfall = obj as! Waterfall
        _api.radio!.waterfalls[waterfall.id]!.delegate = nil
        waterfallHandlers[waterfall.id] = nil
        text += "Waterfall      \(waterfall.id.hex)"
        
      case is Xvtr:
        text += "Xvtr           \((obj as! Xvtr).id)"
        
      default:
        text += "Unknown object"
      }
    }
    showInObjectsTable(text)
  }
}
