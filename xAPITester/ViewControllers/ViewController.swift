//
//  ViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 12/10/16.
//  Copyright © 2018 Douglas Adams & Mario Illgen. All rights reserved.
//

import Cocoa
import xLib6000
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

public final class ViewController             : NSViewController, RadioPickerDelegate,  NSTextFieldDelegate {
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance          // Api to the Radio
  
  @IBOutlet weak internal var _command        : NSTextField!
  @IBOutlet weak internal var _connectButton  : NSButton!
  @IBOutlet weak internal var _sendButton     : NSButton!
  @IBOutlet weak internal var _filterBy       : NSPopUpButton!
  @IBOutlet weak internal var _filterObjectsBy: NSPopUpButton!
  @IBOutlet weak internal var _streamId       : NSTextField!
  @IBOutlet weak internal var _localRemote    : NSTextField!
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties - Setters / Getters with synchronization
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _previousCommand                = ""                          // last command issued
  private var _commandsIndex                  = 0
  private var _commandsArray                  = [String]()                  // commands history

  private var _radioPickerTabViewController   : NSTabViewController?
  
  internal var _startTimestamp                : Date?
  
  private var _splitViewViewController        : SplitViewController?
  private var _appFolderUrl                   : URL!
  private var _macros                         : Macros!
  private var _apiVersion                     = ""
  private var _apiBuild                       = ""
  
  // constants
  private let _dateFormatter                  = DateFormatter()
  
  private let kAutosaveName                   = NSWindow.FrameAutosaveName("xAPITesterWindow")
  private let kConnect                        = NSUserInterfaceItemIdentifier( "Connect")
  private let kDisconnect                     = NSUserInterfaceItemIdentifier( "Disconnect")
  private let kLocal                          = "Local"
  private let kRemote                         = "SmartLink"
  private let kLocalTab                       = 0
  private let kRemoteTab                      = 1

  private let kxLib6000Identifier             = "net.k3tzr.xLib6000"          // Bundle identifier for xLib6000
  private let kVersionKey                     = "CFBundleShortVersionString"  // CF constants
  private let kBuildKey                       = "CFBundleVersion"

  private var kSaveFolder                     = "net.k3tzr.xAPITester"
  
  // ----------------------------------------------------------------------------
  // MARK: - Overriden methods

  public func NSLocalizedString(_ key: String) -> String {
    return Foundation.NSLocalizedString(key, comment: "")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    
    // get the version info from xLib6000
    let frameworkBundle = Bundle(identifier: kxLib6000Identifier)
    _apiVersion = (frameworkBundle?.object(forInfoDictionaryKey: kVersionKey) ?? "0") as! String
    _apiBuild = (frameworkBundle?.object(forInfoDictionaryKey: kBuildKey) ?? "0") as! String

    _filterBy.selectItem(withTag: Defaults[.filterByTag])
    _filterObjectsBy.selectItem(withTag: Defaults[.filterObjectsByTag])

    _dateFormatter.timeZone = NSTimeZone.local
    _dateFormatter.dateFormat = "mm:ss.SSS"
    
    _command.delegate = self
    
    _sendButton.isEnabled = false
    
    // setup & register Defaults
    setupDefaults()
    
    // color the text field to match the kMyHandleColor
    _streamId.backgroundColor = Defaults[.myHandleColor]
    
    let fileManager = FileManager.default
    let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask )
    _appFolderUrl = urls.first!.appendingPathComponent( Bundle.main.bundleIdentifier! )
    
    // does the folder exist?
    if !fileManager.fileExists( atPath: _appFolderUrl.path ) {
      
      // NO, create it
      do {
        try fileManager.createDirectory( at: _appFolderUrl, withIntermediateDirectories: false, attributes: nil)
      } catch let error as NSError {
        fatalError("Error creating App Support folder: \(error.localizedDescription)")
      }
    }

    // is the default Radio available?
    if let defaultRadio = defaultRadioFound() {
      
      // YES, open the default radio (local only)
      if !openRadio(defaultRadio) {
        _splitViewViewController?.msg("Error opening default radio, \(defaultRadio.name ?? "")", level: .warning, function: #function, file: #file, line: #line)
        
        // open the Radio Picker
        openRadioPicker( self)
      }
      
    } else {
      
      // NO, open the Radio Picker
      openRadioPicker( self)
    }
  }
  override public func viewWillAppear() {
    
    super.viewWillAppear()
    // position it
    view.window!.setFrameUsingName(kAutosaveName)
  }
  
  override public func viewWillDisappear() {
    
    super.viewWillDisappear()
    // save its position
    view.window!.saveFrame(usingName: kAutosaveName)
  }

  public override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
    
    if segue.identifier!.rawValue == "SplitView" {
      _splitViewViewController = segue.destinationController as? SplitViewController
      _splitViewViewController!._parent = self
      
      _splitViewViewController?.view.translatesAutoresizingMaskIntoConstraints = false
      _api.testerDelegate = _splitViewViewController
      
      _macros = Macros(logHandler: _splitViewViewController!)
    }
  }
  // ----------------------------------------------------------------------------
  // MARK: - Action methods
  
  /// Respond to the Clear button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func clear(_ sender: NSButton) {
    
    // clear all previous commands & replies
    _splitViewViewController?.textArray.removeAll()
    _splitViewViewController?.reloadTable()
    
    // clear all previous objects
    _splitViewViewController?.objectsArray.removeAll()
    _splitViewViewController?.reloadObjectsTable()
  }
  /// Respond to the Connect button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func connect(_ sender: NSButton) {
    
    // Connect or Disconnect?
    switch sender.identifier {
      
    case kConnect:
      
      // open the picker
      openRadioPicker(self)
      
    case kDisconnect:
      
      // close the active Radio
      closeRadio()
      
    default:    // should never happen
      break
    }
  }
  /// The Connect as Gui checkbox changed
  ///
  /// - Parameter sender:     the checkbox
  ///
  @IBAction func connectAsGui(_ sender: NSButton) {
    
    Defaults[.isGui] = (sender.state == NSControl.StateValue.on)
  }
  /// Respond to the Copy button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     any Object
  ///
  @IBAction func copyToClipboard(_ sender: Any){
    var textToCopy = ""
    
    // if no rows selected, select all
    if _splitViewViewController!._tableView.numberOfSelectedRows == 0 { _splitViewViewController!._tableView.selectAll(self) }
    
    // get the indexes of the selected rows
    let indexSet = _splitViewViewController!._tableView.selectedRowIndexes
    
    for (_, rowIndex) in indexSet.enumerated() {
      
      var text = _splitViewViewController!._filteredTextArray[rowIndex]

      // remove the prefixes (Timestamps & Connection Handle)
      text = text.components(separatedBy: "|")[1]
      
      // accumulate the text lines
      textToCopy += text + "\n"
    }
    // eliminate the last newline
    textToCopy = String(textToCopy.dropLast())
    
    let pasteBoard = NSPasteboard.general
    pasteBoard.clearContents()
    pasteBoard.setString(textToCopy, forType:NSPasteboard.PasteboardType.string)
  }
  /// Respond to the Copy to Cmd button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     any object
  ///
  @IBAction func copyToCmd(_ sender: Any) {
    var textToCopy = ""
    
    // get the indexes of the selected rows
    let indexSet = _splitViewViewController!._tableView.selectedRowIndexes
    
    for (_, rowIndex) in indexSet.enumerated() {
      
      textToCopy = _splitViewViewController!._filteredTextArray[rowIndex]
      
      // remove the prefixes (Timestamps & Connection Handle)
      textToCopy = textToCopy.components(separatedBy: "|")[1]
      
      // stop after the first line
      break
    }
    // paste the text into the command line
    _command.stringValue = textToCopy
  }
  /// Respond to the Load button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func load(_ sender: NSButton) {
    
    let openPanel = NSOpenPanel()
    openPanel.allowedFileTypes = ["txt"]
    openPanel.directoryURL = _appFolderUrl

    // open an Open Dialog
    openPanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      var fileString = ""
      
      // if the user selects Open
      if result == NSApplication.ModalResponse.OK {
        let url = openPanel.url!
        
        do {
          
          // try to read the file url
          try fileString = String(contentsOf: url)
          
          // separate into lines
          self._splitViewViewController?.textArray = fileString.components(separatedBy: "\n")
          
          // eliminate the last one (it's blank)
          self._splitViewViewController?.textArray.removeLast()
          
          // force a redraw
          self._splitViewViewController?.reloadTable()
          
        } catch {
          
          // something bad happened!
          self._splitViewViewController?.msg("Error reading file", level: .error, function: #function, file: #file, line: #line)
        }
      }
    }
  }
  /// Respond to the Load button (in the Macros box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func loadMacro(_ sender: NSButton) {
    
    let openPanel = NSOpenPanel()
    openPanel.allowedFileTypes = ["macro"]
    openPanel.nameFieldStringValue = "macro_1"
    openPanel.directoryURL = _appFolderUrl
    
    // open an Open Dialog
    openPanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      var fileString = ""
      
      // if the user selects Open
      if result == NSApplication.ModalResponse.OK {
        let url = openPanel.url!
        
        do {
          
          // try to read the file url
          try fileString = String(contentsOf: url)
          
          // separate into lines
          self._commandsArray = fileString.components(separatedBy: "\n")
          
          // eliminate the last one (it's blank)
          self._commandsArray.removeLast()
          
          // show the first command (if any)
          if self._commandsArray.count > 0 { self._command.stringValue = self._commandsArray[0] }
          
        } catch {
          
          // something bad happened!
          self._splitViewViewController?.msg("Error reading file", level: .error, function: #function, file: #file, line: #line)
        }
      }
    }
  }
  /// Open the Radio Picker sheet
  ///
  /// - Parameter sender:     the sender
  ///
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
  /// Respond to the Run button (in the Macros box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func runMacro(_ sender: NSButton) {

    _macros.runMacro("", window: view.window!, appFolderUrl: _appFolderUrl)
  }
  /// Respond to the Save button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func save(_ sender: NSButton) {
    
    let savePanel = NSSavePanel()
    savePanel.allowedFileTypes = ["txt"]
    savePanel.nameFieldStringValue = "xAPITester"
    savePanel.directoryURL = _appFolderUrl
    
    // open a Save Dialog
    savePanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      
      // if the user pressed Save
      if result == NSApplication.ModalResponse.OK {
        
        var fileString = ""
        
        // build a string of all the commands & replies
        for row in self._splitViewViewController!._filteredTextArray {
          
          fileString += row + "\n"
        }
        // write it to the File
        self.writeToFile(savePanel.url!, text: fileString)
      }
    }
  }
  /// Respond to the Save button (in the Macros box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func saveMacro(_ sender: NSButton) {

    let savePanel = NSSavePanel()
    savePanel.allowedFileTypes = ["macro"]
    savePanel.nameFieldStringValue = "macro_1"
    savePanel.directoryURL = _appFolderUrl
    
    // open a Save Dialog
    savePanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      
      // if the user pressed Save
      if result == NSApplication.ModalResponse.OK {
        
        var fileString = ""
        
        // build a string of all the commands & replies
        for command in self._commandsArray {
          
          fileString += command + "\n"
        }
        // write it to the File
        self.writeToFile(savePanel.url!, text: fileString)
      }
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
      
      if cmd.first! == Macros.kMacroPrefix {
        
        // the command is a macro file name
        _macros.runMacro(String(cmd.dropFirst()), window: view.window!, appFolderUrl: _appFolderUrl, choose: false)

      } else if cmd.first! == Macros.kConditionPrefix {
      
        // parse the condition
        let evaluatedCommand = _macros.parse(cmd)
        
        // was the condition was satisfied?
        if evaluatedCommand.active {
          
          // YES, send the command
          let _ = _api.send( _macros.evaluateValues(command: evaluatedCommand.cmd) )
        
        } else {
          
          // NO, log it
          _api.log.msg("Condition false : \(evaluatedCommand.condition)", level: .error, function: #function, file: #file, line: #line)
        }
      
      } else {
        
        // send the command via TCP
        let _ = _api.send( _macros.evaluateValues(command: cmd) )
        
        if cmd != _previousCommand { _commandsArray.append(cmd) }
        
        _previousCommand = cmd
        _commandsIndex = _commandsArray.count - 1
        
        // optionally clear the Command field
        if Defaults[.clearOnSend] { _command.stringValue = "" }
      }
    }
  }
  /// Respond to the Show Timestamps checkbox
  ///
  /// - Parameter sender:   the button
  ///
  @IBAction func showTimestamps(_ sender: NSButton) {
    
    // force a redraw
    _splitViewViewController?.reloadTable()
    _splitViewViewController?.reloadObjectsTable()
  }
  /// Respond to the Close menu item
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func terminate(_ sender: AnyObject) {
    
    // disconnect the active radio
    _api.disconnect()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect.rawValue
    _localRemote.stringValue = ""
    
    NSApp.terminate(self)
  }
  /// The Filter text field changed (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilter(_ sender: NSTextField) {
    
    // force a redraw
    _splitViewViewController?.reloadTable()
  }
  /// The FilterBy PopUp changed (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterBy(_ sender: NSPopUpButton) {
    
    // clear the Filter string field
    Defaults[.filter] = ""
    
    // force a redraw
    _splitViewViewController?.reloadTable()
  }
  /// The Filter text field changed (in the Objects box)
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilterObjects(_ sender: NSTextField) {
    
    // force a redraw
    _splitViewViewController?.reloadObjectsTable()
  }
  /// The FilterBy PopUp changed (in the Objects box)
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterObjectsBy(_ sender: NSPopUpButton) {
    
    // clear the Filter string field
    Defaults[.filterObjects] = ""
    
    // force a redraw
    _splitViewViewController?.reloadObjectsTable()
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
  /// Write the Log to the App Support folder
  ///
  /// - parameter filterBy:   a MessageLevel
  ///
  private func writeLogToURL(_ url: URL) {
    var fileString = ""
    
    // build a string of all the entries
    for row in _splitViewViewController!._filteredTextArray {
      
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
  /// Write Text to a File url
  ///
  /// - Parameters:
  ///   - url:            a File Url
  ///   - text:           the Text
  ///
  private func writeToFile(_ url: URL, text: String) {
    do {
      // write the string to the file url
      try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
      
    } catch let error as NSError {
      
      // something bad happened!
      self._api.log.msg("Error writing to file : \(error.localizedDescription)", level: .error, function: #function, file: #file, line: #line)
      
    } catch {
      
      // something bad happened!
      self._api.log.msg("Error writing Log", level: .error, function: #function, file: #file, line: #line)
    }
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

    // if not a GUI connection, allow the Tester to see all stream objects
    _api.testerModeEnabled = !Defaults[.isGui]

    // attempt to connect to it
    if _api.connect(selectedRadio, clientName: kClientName, isGui: Defaults[.isGui]) {
      
      _startTimestamp = Date()
      
      self._connectButton.title = self.kDisconnect.rawValue
      self._connectButton.identifier = self.kDisconnect
      self._sendButton.isEnabled = true

      setTitle()
      
      return true
    }
    setTitle()
    return false
  }
  /// Close the currently active Radio
  ///
  func closeRadio() {
    
    // disconnect the active radio
    _api.disconnect()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect.rawValue
    _connectButton.identifier = kConnect
    _localRemote.stringValue = ""
    
    setTitle()
  }
  /// Clear the reply table
  ///
  func clearTable() {
    
    // clear the previous Commands, Replies & Messages
    if Defaults[.clearAtConnect] { _splitViewViewController!.textArray.removeAll() ;_splitViewViewController!._tableView.reloadData() }
    
    // clear the objects
    _splitViewViewController!.objectsArray.removeAll() ;_splitViewViewController!._objectsTableView.reloadData()
  }
  /// Set the Window's title
  ///
  func setTitle() {
    let title = (_api.activeRadio == nil ? "" : " - Connected to \(_api.activeRadio!.nickname ?? "") @ \(_api.activeRadio!.ipAddress), xLib6000 v\(_apiVersion).\(_apiBuild)")
    DispatchQueue.main.async {
      self.view.window?.title = "\(kClientName)\(title)"
    }
  }
  /// Close the application
  ///
  func terminateApp() {
    
    terminate(self)
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


