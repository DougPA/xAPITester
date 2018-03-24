//
//  ViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 12/10/16.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Cocoa
import SwiftyUserDefaults

// --------------------------------------------------------------------------------
// MARK: - RadioPicker Delegate definition
// --------------------------------------------------------------------------------

protocol RadioPickerDelegate: class {
  
  var token: Token? { get set }
  
  /// Close this sheet
  ///
  func closeRadioPicker()
  
  /// Open the specified Radio
  ///
  /// - Parameters:
  ///   - radio:              a RadioParameters struct
  ///   - remote:             remote / local
  ///   - handle:             remote handle
  /// - Returns:              success / failure
  ///
  func openRadio(_ radio: RadioParameters?, isWan: Bool, wanHandle: String) -> Bool
  
  /// Close the active Radio
  ///
  func closeRadio()
  
  /// Clear the reply table
  ///
  func clearTable()
  
  /// Close the application
  ///
  func terminateApp()
}

// ------------------------------------------------------------------------------
// MARK: - ViewController Class implementation
// ------------------------------------------------------------------------------

public final class ViewController             : NSViewController, RadioPickerDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate, ApiDelegate, NSTabViewDelegate, LogHandler {
  
  private(set) var activeRadio                : RadioParameters? {          // Radio currently in use (if any)
    didSet {
      let title = (activeRadio == nil ? "" : " - Connected to \(activeRadio!.nickname ?? "") @ \(activeRadio!.ipAddress)")
      DispatchQueue.main.async {
        self.view.window?.title = "\(kClientName)\(title)"
      }
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public enum FilterTag: Int {                                              // types of filtering
    case none = 0
    case prefix
    case contains
    case streamId
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance          // Api to the Radio
  
  @IBOutlet weak private var _filter          : NSTextField!
  @IBOutlet weak private var _command         : NSTextField!
  @IBOutlet weak private var _enablePinging   : NSButton!
  @IBOutlet weak private var _showAllReplies  : NSButton!
  @IBOutlet weak private var _showPings       : NSButton!
  @IBOutlet weak private var _connectButton   : NSButton!
  @IBOutlet weak private var _clearAtConnect  : NSButton!
  @IBOutlet weak private var _useLowBw        : NSButton!
  @IBOutlet weak private var _sendButton      : NSButton!
  @IBOutlet weak private var _filterBy        : NSPopUpButton!
  @IBOutlet weak private var _tableView       : NSTableView!
  @IBOutlet weak private var _streamId        : NSTextField!
  @IBOutlet weak private var _clearOnSend     : NSButton!
  @IBOutlet weak private var _localRemote     : NSTextField!
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties - Setters / Getters with synchronization
  
  private var myHandle: String {
    get { return _objectQ.sync { _myHandle } }
    set { _objectQ.sync(flags: .barrier) { _myHandle = newValue } } }
  
  public var replyHandlers: [SequenceId: ReplyTuple] {
    get { return _objectQ.sync { _replyHandlers } }
    set { _objectQ.sync(flags: .barrier) { _replyHandlers = newValue } } }
  
  private var textArray: [String] {
    get { return _objectQ.sync { _textArray } }
    set { _objectQ.sync(flags: .barrier) { _textArray = newValue } } }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _previousCommand                = ""                          // last command issued
  private var _commandsIndex                  = 0
  private var _commandsArray                  = [String]()                  // commands history
  private var _filteredTextArray              : [String] {                  // filtered version of textArray
    get {
      switch FilterTag(rawValue: _filterBy.selectedTag())! {
      case .none:
        return textArray
        
      case .prefix:
        return textArray.filter { $0.hasPrefix(_filter.stringValue) }
        
      case .contains:
        return textArray.filter { $0.contains(_filter.stringValue) }
        
      case .streamId:
        return textArray.filter { $0.hasPrefix("S" + myHandle) }
      }
    }}
  private var _notifications                  = [NSObjectProtocol]()        // Notification observers
  private var _font                           : NSFont!                     // font for table entries
  
  private var _radioPickerTabViewController   : NSTabViewController?
  
  private var _timestampsInUse                = false
  private var _startTimestamp                 : Date?
  
  // backing storage
  private var _myHandle                       = "" {
    didSet { DispatchQueue.main.async { self._streamId.stringValue = self._myHandle } } }
  private var _replyHandlers                  = [SequenceId: ReplyTuple]()  // Dictionary of pending replies
  private var _textArray                      = [String]()                  // backing storage for the table
  
  // constants
  private let _objectQ                        = DispatchQueue(label: kClientName + ".objectQ", attributes: [.concurrent])
  
  private let _dateFormatter                  = DateFormatter()
  
  private let kSend                           = "Send"
  private let kConnect                        = "Connect"
  private let kDisconnect                     = "Disconnect"
  private let kLocal                          = "LOCAL"
  private let kRemote                         = "REMOTE"
  private let kLocalTab                       = 0
  private let kRemoteTab                      = 1

  // ----------------------------------------------------------------------------
  // MARK: - Overriden methods
  
  public override func viewDidLoad() {
    super.viewDidLoad()
    
    // give the Log object (in the API) access to our logger
    Log.sharedInstance.delegate = self

    _dateFormatter.timeZone = NSTimeZone.local
    _dateFormatter.dateFormat = "mm:ss.SSS"
    
    _command.delegate = self
    
    _sendButton.isEnabled = false
    _sendButton.title = kSend
    
    // setup & register Defaults
    setupDefaults()
    
    // setup the font
    _font = NSFont(name: Defaults[.fontName], size: CGFloat(Defaults[.fontSize] ))!
    _tableView.rowHeight = _font.capHeight * 1.7
    
    // color the text field to match the kMyHandleColor
    _streamId.backgroundColor = Defaults[.myHandleColor]
    
    _api.delegate = self
    
    // is the default Radio available?
    if let defaultRadio = defaultRadioFound() {
      
      // YES, open the default radio (local only)
      if !openRadio(defaultRadio) {
        msg("Error opening default radio, \(defaultRadio.name ?? "")", level: .warning, function: #function, file: #file, line: #line)
        
        // open the Radio Picker
        openRadioPicker( self)
      }
      
    } else {
      
      // NO, open the Radio Picker
      openRadioPicker( self)
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Action methods
  
  /// Respond to the Close menu item
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func terminate(_ sender: AnyObject) {
    
    // disconnect the active radio
    _api.disconnect()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect
    _localRemote.stringValue = ""
    
    NSApp.terminate(self)
  }
  @IBAction func openRadioPicker(_ sender: AnyObject) {
    
    // get an instance of the RadioPicker
    _radioPickerTabViewController = storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "RadioPicker")) as? NSTabViewController
    
    // make this View Controller the delegate of the RadioPickers
    _radioPickerTabViewController!.tabViewItems[kLocalTab].viewController!.representedObject = self
    _radioPickerTabViewController!.tabViewItems[kRemoteTab].viewController!.representedObject = self

    // select the last-used tab
    _radioPickerTabViewController!.selectedTabViewItemIndex = ( Defaults[.showRemoteTabView] == false ? kLocalTab : kRemoteTab )

    DispatchQueue.main.async {
      
      // show the RadioPicker sheet
      self.presentViewControllerAsSheet(self._radioPickerTabViewController!)
    }
  }
  /// The Enable Pings checkbox changed
  ///
  /// - Parameter sender:     the checkbox
  ///
  @IBAction func updateEnablePinging(_ sender: NSButton) {
    
    // allow the user to show / not show pings
    Defaults[.showPings] = (sender.state == NSControl.StateValue.on)
  }
  /// The FilterBy PopUp changed
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterBy(_ sender: NSPopUpButton) {
    
    // save change to preferences
    Defaults[.filterByTag] = sender.selectedTag()
    
    // clear the Filter string field
    _filter.stringValue = ""
    
    // force a redraw
    reloadTable()
  }
  /// The Filter text field changed
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilter(_ sender: NSTextField) {
    
    // save change to preferences
    Defaults[.filter] = sender.stringValue
    
    // force a redraw
    reloadTable()
  }
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
    
    // force a redraw
    reloadTable()
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
    
    // force a redraw
    reloadTable()
  }
  /// Respond to the Connect button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func connect(_ sender: NSButton) {
    
    // Connect or Disconnect?
    switch sender.title {
      
    case kConnect:
      
      // open the picker
      openRadioPicker(self)
      
    case kDisconnect:
      
      // disconnect the active radio
      _api.disconnect()
      
      _sendButton.isEnabled = false
      _connectButton.title = kConnect
      _localRemote.stringValue = ""
      
    default:    // should never happen
      break
    }
  }
  /// Respond to the Send button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func send(_ sender: NSButton) {
    
    // get the command
    let cmd = _command.stringValue
    
    // if the field isn't blank
    if cmd != "" {
      
      // send the command via TCP
      let _ = _api.send(cmd)
      
      if cmd != _previousCommand { _commandsArray.append(cmd) }
      
      _previousCommand = cmd
      _commandsIndex = _commandsArray.count - 1
      
      // optionally clear the Command field
      if Defaults[.clearOnSend] { _command.stringValue = "" }
    }
  }
  /// The Connect as Gui checkbox changed
  ///
  /// - Parameter sender:     the checkbox
  ///
  @IBAction func connectAsGui(_ sender: NSButton) {
    
    Defaults[.isGui] = (sender.state == NSControl.StateValue.on)
  }
  /// Respond to the Load button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func load(_ sender: NSButton) {
    
    let openPanel = NSOpenPanel()
    openPanel.allowedFileTypes = ["txt"]
    
    // open an Open Dialog
    openPanel.beginSheetModal(for: self.view.window!, completionHandler: { (result: NSApplication.ModalResponse) -> Void in
      var fileString = ""
      
      // if the user selects Open
      if result == NSApplication.ModalResponse.OK {
        let url = openPanel.url!
        
        do {
          
          // try to read the file url
          try fileString = String(contentsOf: url)
          
          // separate into lines
          self.textArray = fileString.components(separatedBy: "\n")
          
          // eliminate the last one (it's blank)
          self.textArray.removeLast()
          
          // force a redraw
          self.reloadTable()
          
        } catch {
          
          // something bad happened!
          self.msg("Error reading file", level: .error, function: #function, file: #file, line: #line)
        }
      }
    })
  }
  /// Respond to the Clear button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func clear(_ sender: NSButton) {
    
    // clear all previous commands & replies
    textArray.removeAll()
    
    // force a redraw
    reloadTable()
  }
  /// Respond to the Save button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func save(_ sender: NSButton) {
    
    let savePanel = NSSavePanel()
    savePanel.allowedFileTypes = ["txt"]
    savePanel.nameFieldStringValue = "xAPITester"
    
    // open a Save Dialog
    savePanel.beginSheetModal(for: self.view.window!, completionHandler: { (result: NSApplication.ModalResponse) -> Void in
      
      // if the user pressed Save
      if result == NSApplication.ModalResponse.OK {
        
        var fileString = ""
        
        // build a string of all the commands & replies
        for row in self._filteredTextArray {
          
          fileString += row + "\n"
        }
        do {
          // write the string to the file url
          try fileString.write(to: savePanel.url!, atomically: true, encoding: String.Encoding.utf8)
          
        } catch let error as NSError {
          
          // something bad happened!
          self._api.log.msg("Error writing to file : \(error.localizedDescription)", level: .error, function: #function, file: #file, line: #line)
          
        } catch {
          
          // something bad happened!
          self._api.log.msg("Error writing Log", level: .error, function: #function, file: #file, line: #line)
        }
      }
    })
  }
  /// Copy text from the table view to the Command field
  ///
  /// - Parameter sender:     any object
  ///
  @IBAction func copyToCmd(_ sender: Any) {
    var cmd = ""
    
    // get the indexes of the selected rows
    let indexSet = _tableView.selectedRowIndexes
    
    for (_, rowIndex) in indexSet.enumerated() {
      
      cmd = _filteredTextArray[rowIndex]
      break
    }
    
    let cmdParts = cmd.components(separatedBy: "|")
    cmd = cmdParts.count == 2 ? cmdParts[1] : cmdParts[0]
    
    _command.stringValue = cmd
  }
  /// Copy text from the table view to the clipboard
  ///
  /// - Parameter sender:     any Object
  ///
  @IBAction func copyToClipboard(_ sender: Any){
    var textToCopy = ""
    
    // if no rows selected, select all
    if _tableView.numberOfSelectedRows == 0 { _tableView.selectAll(self) }
    
    // get the indexes of the selected rows
    let indexSet = _tableView.selectedRowIndexes
    
    for (_, rowIndex) in indexSet.enumerated() {
      
      let text = _filteredTextArray[rowIndex]
      textToCopy += text + "\n"
    }
    // eliminate the last newline
    textToCopy = String(textToCopy.dropLast())
    
    let pasteBoard = NSPasteboard.general
    pasteBoard.clearContents()
    pasteBoard.setString(textToCopy, forType:NSPasteboard.PasteboardType.string)
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Setup & Register User Defaults
  ///
  fileprivate func setupDefaults() {
    //        let messageColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.1)
    //        let commandColor = NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 0.1)
    //        let myHandleColor = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 0.1)
    //        let neutralColor = NSColor(srgbRed: 0.0, green: 1.0, blue: 1.0, alpha: 0.1)
    //        let otherHandleColor = NSColor(srgbRed: 1.0, green: 0.0, blue: 1.0, alpha: 0.1)
    
    // get the URL of the defaults file
    let defaultsUrl = Bundle.main.url(forResource: "Defaults", withExtension: "plist")!
    
    // load the contents
    let myDefaults = NSDictionary(contentsOf: defaultsUrl)!
    
    // register the defaults
    Defaults.register(defaults: myDefaults as! Dictionary<String, Any>)
    
    //        Defaults[.messageColor] = messageColor
    //        Defaults[.commandColor] = commandColor
    //        Defaults[.myHandleColor] = myHandleColor
    //        Defaults[.neutralColor] = neutralColor
    //        Defaults[.otherHandleColor] = otherHandleColor
  }
  /// Check if there is a Default Radio (local only)
  ///
  /// - Returns:        a RadioParameters struct or nil
  ///
  private func defaultRadioFound() -> RadioParameters? {
    var defaultRadioParameters: RadioParameters?
    
    // see if there is a valid default Radio
    let defaultRadio = RadioParameters( Defaults[.defaultsDictionary] )
    if defaultRadio.ipAddress != "" && defaultRadio.port != 0 {
      
      // allow time to hear the UDP broadcasts
      usleep(1500)
      
      // has the default Radio been found?
      for (_, foundRadio) in _api.availableRadios.enumerated() where foundRadio == defaultRadio {
        
        // YES, Save it in case something changed
        Defaults[.defaultsDictionary] = foundRadio.dictFromParams()
        
        //        // select it in the TableView
        //        self._radioTableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: true)
        
        _api.log.msg("\(foundRadio.nickname ?? "") @ \(foundRadio.ipAddress)", level: .info, function: #function, file: #file, line: #line)
        
        defaultRadioParameters = foundRadio
      }
    }
    return defaultRadioParameters
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
  /// Refresh the TableView & make its last row visible
  ///
  private func reloadTable() {
    
    DispatchQueue.main.async { [unowned self] in
      // reload the table
      self._tableView?.reloadData()
      
      // make sure the last row is visible
      if self._tableView.numberOfRows > 0 {
        
        self._tableView.scrollRowToVisible(self._tableView.numberOfRows - 1)
      }
    }
  }
  /// Add text to the table
  ///
  /// - Parameter text:       a text String
  ///
  public func showInTable(_ text: String, addTimestamp: Bool = true) {
    
    DispatchQueue.main.async {
      // add the Text to the Array (with or without a timestamp)
      if self._timestampsInUse && addTimestamp {
        let timeInterval = Date().timeIntervalSince(self._startTimestamp!)
        
        let timestamp = String( format: "%0.3f", timeInterval)
        self.textArray.append( timestamp + " " + text )
        
      } else {
        
        self.textArray.append( text )
      }
      
      self.reloadTable()
    }
  }
  /// Write the Log to the App Support folder
  ///
  /// - parameter filterBy:   a MessageLevel
  ///
  private func writeLogToURL(_ url: URL) {
    var fileString = ""
    
    // build a string of all the entries
    for row in _filteredTextArray {
      
      fileString += row + "\n"
    }
    // write the file
    do {
      
      try fileString.write(to: url, atomically: true, encoding: String.Encoding.utf8)
      
    } catch let error as NSError {
      
      _api.log.msg("Error writing to file : \(error.localizedDescription)", level: .error, function: #function, file: #file, line: #line)
      
    } catch {
      
      _api.log.msg("Error writing Log", level: .error, function: #function, file: #file, line: #line)
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
      
      _api.wanConnectionHandle = myHandle
      
      showInTable(text)
      
    case "M":   // Message Type
      showInTable(text)
      
    case "R":   // Reply Type
      parseReply(suffix)
      
    case "S":   // Status type
      // format: <apiHandle>|<message>, where <message> is of the form: <msgType> <otherMessageComponents>
      
      // is this a "Client connected" status
      let components = suffix.split(separator: "|")
      if components.count == 2 && components[0] == myHandle && components[1].hasPrefix("client") && components[1].contains(" connected") {
        // YES, set the API State
        _api.setConnectionState(.clientConnected)
      }
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
  public func streamHandler(_ vitaPacket: Vita) {

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
    showInTable("----- \(msg) -----", addTimestamp: false)
  }

  // ----------------------------------------------------------------------------
  // MARK: - RadioPickerDelegate methods
  
  var token: Token?
  
  /// Close the RadioPicker sheet
  ///
  func closeRadioPicker() {
    
    // close the RadioPicker
    if _radioPickerTabViewController != nil {
      
      // get the current tab & and set the default
      let selectedIndex = _radioPickerTabViewController?.selectedTabViewItemIndex
      Defaults[.showRemoteTabView] = ( selectedIndex == kRemoteTab ? true : false )
      
      dismissViewController(_radioPickerTabViewController!)
    }
    _radioPickerTabViewController = nil
  }
  /// Connect the selected Radio
  ///
  /// - Parameters:
  ///   - radio:                the RadioParameters
  ///   - isWan:                Local / Wan
  ///   - wanHandle:            Wan handle (if any)
  /// - Returns:                success / failure
  ///
  func openRadio(_ radio: RadioParameters?, isWan: Bool = false, wanHandle: String = "") -> Bool {
    
    // close the Radio Picker (if open)
    closeRadioPicker()
    
    // fail if no Radio selected
    guard let selectedRadio = radio else { return false }
    
    // WAN connect
    if isWan {
      _localRemote.stringValue = kRemote
      _api.isWan = true
      _api.wanConnectionHandle = wanHandle
    } else {
      _localRemote.stringValue = kLocal
      _api.isWan = false
      _api.wanConnectionHandle = ""
    }
    // attempt to connect to it
    if _api.connect(selectedRadio, clientName: kClientName, isGui: Defaults[.isGui]) {
      
      _timestampsInUse = Defaults[.showTimestamps]
      _startTimestamp = Date()
      
      self._connectButton.title = self.kDisconnect
      self._sendButton.isEnabled = true
      return true
    }
    return false
  }
  /// Close the currently active Radio
  ///
  func closeRadio() {
    
    // disconnect the active radio
    _api.disconnect()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect
    _localRemote.stringValue = ""
  }
  /// Clear the reply table
  ///
  func clearTable() {
    
    // clear the previous Commands, Replies & Messages
    if Defaults[.clearAtConnect] { textArray.removeAll() ;_tableView.reloadData() }
  }
  
  /// Close the application
  ///
  func terminateApp() {
    
    terminate(self)
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - NSTableView DataSource methods
  
  /// Return the number of rows in the TableView
  ///
  /// - Parameter aTableView: the TableView
  /// - Returns:              number of rows
  ///
  public func numberOfRows(in aTableView: NSTableView) -> Int {
    
    return _filteredTextArray.count
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
    
    // get the text
    let rowText = _filteredTextArray[row]
    var msgText = rowText
    
    if _timestampsInUse { msgText = msgText.components(separatedBy: " ")[1] }
    
    // determine the type of text, assign a background color
    if rowText.hasPrefix("-----") {                                         // application messages
      
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
    view.textField!.stringValue = rowText
    
    return view
  }
  /// Allow the user to press Enter to send a command
  ///
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    
    if (commandSelector == #selector(NSResponder.insertNewline(_:))) {
      // "click" the send button
      _sendButton.performClick(self)
      
      return true
    } else if (commandSelector == #selector(NSResponder.moveUp(_:))) {
      
      if let previousIndex = previousIndex() {
        // show the previous command
        _command.stringValue = _commandsArray[previousIndex]
      }
      return true
      
    } else if (commandSelector == #selector(NSResponder.moveDown(_:))) {
      
      if let index = nextIndex() {
        
        if index == -1 {
          _command.stringValue = ""
        } else {
          // show the next command
          _command.stringValue = _commandsArray[index]
        }
      
      }
      return true
    }
    // return true if the action was handled; otherwise false
    return false
  }
  
  private func previousIndex() -> Int? {
    var index: Int?
    
    guard _commandsArray.count != 0 else { return index }
    
    if _commandsIndex == 0 {
      // at top of the list (oldest command)
      index = 0
      _commandsIndex = 0
    } else {
      // somewhere in list
      index = _commandsIndex
      _commandsIndex = index! - 1
    }
    return index
  }
  
  private func nextIndex() -> Int? {
    var index: Int?
    
    guard _commandsArray.count != 0 else { return index }
    
    if _commandsIndex == _commandsArray.count - 1 {
      // at bottom of list (newest command)
      index =  -1
    } else {
      // somewhere else
      index = _commandsIndex + 1
    }
    _commandsIndex = index != -1 ? index! : _commandsArray.count - 1
    return index
  }
}


