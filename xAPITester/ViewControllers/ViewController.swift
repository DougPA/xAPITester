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
  
  /// Open the specified Radio
  ///
  /// - Parameters:
  ///   - radio:              a RadioParameters struct
  ///   - remote:             remote / local
  ///   - handle:             remote handle
  /// - Returns:              success / failure
  ///
  func openRadio(_ radio: DiscoveredRadio?, isWan: Bool, wanHandle: String) -> Bool
  
  /// Close the active Radio
  ///
  func closeRadio()
}

// ------------------------------------------------------------------------------
// MARK: - ViewController Class implementation
// ------------------------------------------------------------------------------

public final class ViewController             : NSViewController, RadioPickerDelegate,  NSTextFieldDelegate {
  
  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _api                            = Api.sharedInstance
  private let _log                            = (NSApp.delegate as! AppDelegate)
  
  @IBOutlet weak internal var _commandTextField         : NSTextField!
  @IBOutlet weak internal var _connectButton            : NSButton!
  @IBOutlet weak internal var _sendButton               : NSButton!
  @IBOutlet weak internal var _filterByPopUp            : NSPopUpButton!
  @IBOutlet weak internal var _filterObjectsByPopUp     : NSPopUpButton!
  @IBOutlet weak internal var _streamIdTextField        : NSTextField!
  @IBOutlet weak internal var _localRemoteTextField     : NSTextField!
  @IBOutlet weak internal var _boundCheckBox            : NSButton!
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  internal var _startTimestamp                : Date?

  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _previousCommand                = ""                          // last command issued
  private var _commandsIndex                  = 0
  private var _commandsArray                  = [String]()                  // commands history
  private var _radioPickerTabViewController   : NSTabViewController?
  private var _splitViewVC                    : SplitViewController?
  private var _guiClientsVC                   : NSViewController?
  private var _macros                         : Macros!

  // constants
  private let _dateFormatter                  = DateFormatter()
  private let kAutosaveName                   = NSWindow.FrameAutosaveName("xAPITesterWindow")
  private let kConnect                        = NSUserInterfaceItemIdentifier( "Connect")
  private let kDisconnect                     = NSUserInterfaceItemIdentifier( "Disconnect")
  private let kLocal                          = "Local"
  private let kRemote                         = "SmartLink"
  private let kLocalTab                       = 0
  private let kRemoteTab                      = 1
  private let kVersionKey                     = "CFBundleShortVersionString"  // CF constants
  private let kBuildKey                       = "CFBundleVersion"
  private let kDelayForAvailableRadios        : UInt32 = 1
  private let kSizeOfTimeStamp                = 9
  private let kSBI_RadioPicker                = "RadioPicker"
  private let kCommandsRepliesFileName        = "xAPITester"
  private let kCommandsRepliesFileExt         = "txt"
  private let kMacroFileName                  = "macro_1"
  private let kMacroFileExt                   = "macro"
  private let kDefaultsFile                   = "Defaults.plist"
  private let kSWI_SplitView                  = "SplitView"
  private let kSegueGuiClients                = "GuiClients"
  
  private let kMacrosFolder                   = "Macros"

  // ----------------------------------------------------------------------------
  // MARK: - Overriden methods

  public override func viewDidLoad() {
    super.viewDidLoad()
    
    // give the Api access to our logger
    Log.sharedInstance.delegate = _log
    
    // add Notifications subscriptions
    addNotifications()
    
    // setup filters
    _filterByPopUp.selectItem(withTag: Defaults[.filterByTag])
    _filterObjectsByPopUp.selectItem(withTag: Defaults[.filterObjectsByTag])

    // set datestamp format
    _dateFormatter.timeZone = NSTimeZone.local
    _dateFormatter.dateFormat = "mm:ss.SSS"
    
    // set self as delegate for the command textfield
    _commandTextField.delegate = self
    
    // disable sending
    _sendButton.isEnabled = false
    
    // setup Defaults
    defaultsSetup(from: kDefaultsFile)
    
    // set the window title
    titleSet()
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

    if segue.identifier! == kSWI_SplitView {
      _splitViewVC = segue.destinationController as? SplitViewController
      _splitViewVC!._parent = self

      _splitViewVC?.view.translatesAutoresizingMaskIntoConstraints = false
      _api.testerDelegate = _splitViewVC

      _macros = Macros()
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
    _splitViewVC?.messages.removeAll()
    _splitViewVC?.reloadTable()
    
    // clear all previous objects
    _splitViewVC?.objects.removeAll()
    _splitViewVC?.reloadObjectsTable()
  }
  /// Respond to the Connect button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func connect(_ sender: NSButton) {
    
    // Connect or Disconnect?
    switch sender.identifier {
      
    case kConnect:
      
      // open the Default Radio (if any), otherwise open the Picker
      checkForDefaultRadio()
      
    case kDisconnect:
      
      _splitViewVC?.removeApiTester()
      _splitViewVC?.removeAllGuiClients()
      
      // close the active Radio
      closeRadio()
      
    default:    // should never happen
      break
    }
  }
  /// Respond to the Copy button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     any Object
  ///
  @IBAction func copyToClipboard(_ sender: Any){
    
    // if no rows selected, select all
    if _splitViewVC!._tableView.numberOfSelectedRows == 0 { _splitViewVC!._tableView.selectAll(self) }
    
    let pasteBoard = NSPasteboard.general
    pasteBoard.clearContents()
    pasteBoard.setString( copyRows(_splitViewVC!._tableView, from: _splitViewVC!._filteredMessages), forType: NSPasteboard.PasteboardType.string )
  }
  /// Respond to the Copy to Cmd button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     any object
  ///
  @IBAction func copyToCmd(_ sender: Any) {
    
    // paste the text into the command line
    _commandTextField.stringValue = copyRows(_splitViewVC!._tableView, from: _splitViewVC!._filteredMessages, stopOnFirst: true)
  }
  /// Respond to the Copy Handle button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func copyHandle(_ sender: Any) {
    var textToCopy = ""
    
    // get the indexes of the selected rows
    let indexSet = _splitViewVC!._tableView.selectedRowIndexes
    
    for (_, rowIndex) in indexSet.enumerated() {
      
      let rowText = _splitViewVC!._filteredMessages[rowIndex]
      
      // remove the prefixes (Timestamps & Connection Handle)
      textToCopy = String(rowText.components(separatedBy: "|")[0].dropFirst(kSizeOfTimeStamp + 1))
      
      // stop after the first line
      break
    }
    // paste the text into the filter
    Defaults[.filter] = textToCopy
  }
  /// Respond to the Load button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func load(_ sender: NSButton) {
    
    let openPanel = NSOpenPanel()
    openPanel.allowedFileTypes = [kCommandsRepliesFileExt]
    openPanel.directoryURL = URL.macros

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
          self._splitViewVC?.messages = fileString.components(separatedBy: "\n")
          
          // eliminate the last one (it's blank)
          self._splitViewVC?.messages.removeLast()
          
          // force a redraw
          self._splitViewVC?.reloadTable()
          
        } catch {
          
          // something bad happened!
          self._splitViewVC?.msg("Error reading file")
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
    openPanel.allowedFileTypes = [kMacroFileExt]
    openPanel.nameFieldStringValue = kMacroFileName
    openPanel.directoryURL = URL.macros
    
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
          if self._commandsArray.count > 0 { self._commandTextField.stringValue = self._commandsArray[0] }
          
        } catch {
          
          // something bad happened!
          self._splitViewVC?.msg("Error reading file")
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
    _radioPickerTabViewController = storyboard!.instantiateController(withIdentifier: kSBI_RadioPicker) as? NSTabViewController
    
    // make this View Controller the delegate of the RadioPickers
    _radioPickerTabViewController!.tabViewItems[kLocalTab].viewController!.representedObject = self
    _radioPickerTabViewController!.tabViewItems[kRemoteTab].viewController!.representedObject = self

    // select the last-used tab
    _radioPickerTabViewController!.selectedTabViewItemIndex = ( Defaults[.showRemoteTabView] == false ? kLocalTab : kRemoteTab )

    DispatchQueue.main.async {
      
      // show the RadioPicker sheet
      self.presentAsSheet(self._radioPickerTabViewController!)
    }
  }
  /// Respond to the Run button (in the Macros box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func runMacro(_ sender: NSButton) {

    _macros.runMacro("", window: view.window!, appFolderUrl: URL.macros)
  }
  /// Respond to the Save button (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func save(_ sender: NSButton) {
    
    let savePanel = NSSavePanel()
    savePanel.allowedFileTypes = [kCommandsRepliesFileExt]
    savePanel.nameFieldStringValue = kCommandsRepliesFileName
    savePanel.directoryURL = URL.macros
    
    // open a Save Dialog
    savePanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      
      // if the user pressed Save
      if result == NSApplication.ModalResponse.OK {
        
        // write it to the File
        if let error = savePanel.url!.writeArray( self._splitViewVC!._filteredMessages ) {
          self._log.msg("\(error)", level: MessageLevel.error, function: #function, file: #file, line: #line)
        }
      }
    }
  }
  /// Respond to the Save button (in the Macros box)
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func saveMacro(_ sender: NSButton) {

    let savePanel = NSSavePanel()
    savePanel.allowedFileTypes = [kMacroFileExt]
    savePanel.nameFieldStringValue = kMacroFileName
    savePanel.directoryURL = URL.macros
    
    // open a Save Dialog
    savePanel.beginSheetModal(for: self.view.window!) { [unowned self] (result: NSApplication.ModalResponse) in
      
      // if the user pressed Save
      if result == NSApplication.ModalResponse.OK {
        
        // write it to the File
        if let error = savePanel.url!.writeArray( self._commandsArray ) {
          self._log.msg("\(error)", level: .error, function: #function, file: #file, line: #line)
        }
      }
    }

  }
  /// Respond to the Send button
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func send(_ sender: NSButton) {
    
    // get the command
    let cmd = _commandTextField.stringValue
    
    // if the field isn't blank
    if cmd != "" {
      
      if cmd.first! == Macros.kMacroPrefix {
        
        // the command is a macro file name
        _macros.runMacro(String(cmd.dropFirst()), window: view.window!, appFolderUrl: URL.macros, choose: false)

      } else if cmd.first! == Macros.kConditionPrefix {
      
        // parse the condition
        let evaluatedCommand = _macros.parse(cmd)
        
        // was the condition was satisfied?
        if evaluatedCommand.active {
          // YES, send the command
          let _ = _api.send( _macros.evaluateValues(command: evaluatedCommand.cmd) )
        
        } else {
          // NO, log it
          _log.msg("Condition false: \(evaluatedCommand.condition)", level: .error, function: #function, file: #file, line: #line)
        }
      
      } else {
        
        // send the command via TCP
        let _ = _api.send( _macros.evaluateValues(command: cmd) )
        
        if cmd != _previousCommand { _commandsArray.append(cmd) }
        
        _previousCommand = cmd
        _commandsIndex = _commandsArray.count - 1
        
        // optionally clear the Command field
        if Defaults[.clearOnSend] { _commandTextField.stringValue = "" }
      }
    }
  }
  /// Respond to the Show Timestamps checkbox
  ///
  /// - Parameter sender:   the button
  ///
  @IBAction func showTimestamps(_ sender: NSButton) {
    
    // force a redraw
    _splitViewVC?.reloadTable()
    _splitViewVC?.reloadObjectsTable()
  }
  /// Respond to the Close menu item
  ///
  /// - Parameter sender:     the button
  ///
  @IBAction func terminate(_ sender: AnyObject) {
    
    // disconnect the active radio
    _api.shutdown()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect.rawValue
    _localRemoteTextField.stringValue = ""
    
    NSApp.terminate(self)
  }
  /// The Filter text field changed (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilter(_ sender: NSTextField) {
    
    // force a redraw
    _splitViewVC?.reloadTable()
  }
  /// The FilterBy PopUp changed (in the Commands & Replies box)
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterBy(_ sender: NSPopUpButton) {
    
    // clear the Filter string field
    Defaults[.filter] = ""
    
    // force a redraw
    _splitViewVC?.reloadTable()
  }
  /// The Filter text field changed (in the Objects box)
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilterObjects(_ sender: NSTextField) {
    
    // force a redraw
    _splitViewVC?.reloadObjectsTable()
  }
  /// The FilterBy PopUp changed (in the Objects box)
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterObjectsBy(_ sender: NSPopUpButton) {
    
    // clear the Filter string field
    Defaults[.filterObjects] = ""
    
    // force a redraw
    _splitViewVC?.reloadObjectsTable()
  }

  // ----------------------------------------------------------------------------
  // MARK: - Private methods
  
  /// Copy selected rows from the array backing a table
  ///
  /// - Parameters:
  ///   - table:                        an NStableView instance
  ///   - array:                        the backing array
  ///   - stopOnFirst:                  stop after first row?
  /// - Returns:                        a String of the rows
  ///
  private func copyRows(_ table: NSTableView, from array: Array<String>, stopOnFirst: Bool = false) -> String {
    var text = ""
    
    // get the selected rows
    for (_, rowIndex) in table.selectedRowIndexes.enumerated() {
      
      text = array[rowIndex]
      
      // remove the prefixes (Timestamps & Connection Handle)
      text = text.components(separatedBy: "|")[1]
      
      // stop after the first line?
      if stopOnFirst { break }
      
      // accumulate the text lines
      text += text + "\n"
    }
    return text
  }
  /// Determine if the Default radio (if any) is present
  ///
  fileprivate func checkForDefaultRadio() {
    var found = false
    
    // get the default Radio
    let defaultRadioSerialNumber = Defaults[.defaultRadioSerialNumber]
    
    // is it valid?
    if defaultRadioSerialNumber != "" {
      
      // YES, allow time to hear the UDP broadcasts
      sleep(kDelayForAvailableRadios)
      
      // has the default Radio been found?
      for discoveredRadio in Discovery.sharedInstance.discoveredRadios  {
        
        // is it the default radio?
        if discoveredRadio.serialNumber == defaultRadioSerialNumber {
          
          // YES, can the default radio be opened?
          if openRadio(discoveredRadio) {
            found = true
          
          } else {
            _splitViewVC?.msg("Error opening default radio, \(discoveredRadio.nickname)")
            
            // NO, open the Radio Picker
            openRadioPicker( self)
          }
        }
      }
      if found == false {
        
        // NOT FOUND, open the Radio Picker
        openRadioPicker( self)
      }
      
    } else {
      // NOT VALID, open the Radio Picker
      openRadioPicker(self)
    }
  }
  /// Set the Window's title
  ///
  private func titleSet() {
    
    // format and set the window title
    let title = (_api.activeRadio == nil ? "" : "Connected to \(_api.activeRadio!.nickname) @ \(_api.activeRadio!.publicIp)")

    // log it (before connected)
    if _api.activeRadio == nil {
      self._log.msg( "\(AppDelegate.kName) v\(AppDelegate.kVersion.string), \(Api.kName) v\(Api.kVersion.string)", level: .info, function: #function, file: #file, line: #line)
    }
    // set the title bar
    DispatchQueue.main.async {
      self.view.window?.title = "\(AppDelegate.kName) v\(AppDelegate.kVersion.string)     \(Api.kName) v\(Api.kVersion.string)     \(title)"
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Notification Methods
  
  /// Add Notifications subscriptions
  ///
  private func addNotifications() {
    
    NC.makeObserver(self, with: #selector(radioDowngrade(_:)), of: .radioDowngrade)
    
    NC.makeObserver(self, with: #selector(radioUpgrade(_:)), of: .radioUpgrade)
  }
  /// Process .radioDowngradeRequired Notification
  ///
  /// - Parameter note:         a Notification instance
  ///
  @objc private func radioDowngrade(_ note: Notification) {
    
    let versions = note.object as! [Version]
    
    // the API & Radio versions are not compatible
    // alert if other than normal
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "The Radio's version may not be supported by this version of \(AppDelegate.kName)."
      alert.informativeText = """
      Radio:\t\tv\(versions[1].string)
      xSDR6000:\tv\(versions[0].shortString)
      
      You can use SmartSDR to DOWNGRADE the Radio
      \t\t\tOR
      Install a newer version of \(AppDelegate.kName)
      """
      alert.addButton(withTitle: "Close")
      alert.addButton(withTitle: "Continue")
      alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
          NSApp.terminate(self)
        }
      })
    }
  }
  /// Process .radioUpgradeRequired Notification
  ///
  /// - Parameter note:         a Notification instance
  ///
  @objc private func radioUpgrade(_ note: Notification) {
    
    let versions = note.object as! [Version]
    
    // the API version is later than the Radio version
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "The Radio's version may not be supported by this version of \(AppDelegate.kName)."
      alert.informativeText = """
      Radio:\t\tv\(versions[1].string)
      xSDR6000:\tv\(versions[0].shortString)
      
      You can use SmartSDR to UPGRADE the Radio
      \t\t\tOR
      Install an older version of \(AppDelegate.kName)
      """
      alert.addButton(withTitle: "Close")
      alert.addButton(withTitle: "Continue")
      alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
          NSApp.terminate(self)
        }
      })
    }
  }

  // ----------------------------------------------------------------------------
  // MARK: - RadioPickerDelegate methods
  
  var token: Token?
  
  /// Connect the selected Radio
  ///
  /// - Parameters:
  ///   - radio:                the RadioParameters
  ///   - isWan:                Local / Wan
  ///   - wanHandle:            Wan handle (if any)
  /// - Returns:                success / failure
  ///
  func openRadio(_ radio: DiscoveredRadio?, isWan: Bool = false, wanHandle: String = "") -> Bool {
    
    // fail if no Radio selected
    guard let selectedRadio = radio else { return false }
    
    // clear the previous Commands, Replies & Messages
    if Defaults[.clearAtConnect] { _splitViewVC?.messages.removeAll() ;_splitViewVC?._tableView.reloadData() }
    
    // clear the objects
    _splitViewVC?.objects.removeAll()
    _splitViewVC?._objectsTableView.reloadData()

    // WAN connect
    if isWan {
      _localRemoteTextField.stringValue = kRemote
      _api.isWan = true
      _api.wanConnectionHandle = wanHandle
    } else {
      _localRemoteTextField.stringValue = kLocal
      _api.isWan = false
      _api.wanConnectionHandle = ""
    }

    // if not a GUI connection, allow the Tester to see all stream objects
    _api.testerModeEnabled = !Defaults[.isGui]

    _startTimestamp = Date()

    // attempt to connect to it
    let station = (Host.current().localizedName ?? "Mac").replacingSpaces(with: "_")
    let clientId = Defaults[.isGui] ? UUID(uuidString: Defaults[.myClientId] ?? "") : UUID(uuidString: Defaults[.boundClientId] ?? "")
    if _api.connect(selectedRadio,
                    clientStation:  station,
                    clientProgram:  AppDelegate.kName,
                    clientId:       clientId,
                    isGui:          Defaults[.isGui]) {
            
      self._connectButton.title = self.kDisconnect.rawValue
      self._connectButton.identifier = self.kDisconnect
      self._sendButton.isEnabled = true

      titleSet()
      
      return true
    }
    titleSet()
    return false
  }
  /// Close the currently active Radio
  ///
  func closeRadio() {
    
    // disconnect the active radio
    _api.shutdown()
    
    _sendButton.isEnabled = false
    _connectButton.title = kConnect.rawValue
    _connectButton.identifier = kConnect
    _localRemoteTextField.stringValue = ""
    
    titleSet()
  }
  /// Close the application
  ///
  func terminateApp() {
    
    terminate(self)
  }

  // ----------------------------------------------------------------------------
  // MARK: - NSTextFieldDelegate methods
  
  /// Allow the user to press Enter to send a command
  ///
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    
    // nested functions -----------
    
    func previousIndex() -> Int? {
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
    
    func nextIndex() -> Int? {
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

    // ----------------------------

    if (commandSelector == #selector(NSResponder.insertNewline(_:))) {
      // "click" the send button
      _sendButton.performClick(self)
      
      return true
    } else if (commandSelector == #selector(NSResponder.moveUp(_:))) {
      
      if let previousIndex = previousIndex() {
        // show the previous command
        _commandTextField.stringValue = _commandsArray[previousIndex]
      }
      return true
      
    } else if (commandSelector == #selector(NSResponder.moveDown(_:))) {
      
      if let index = nextIndex() {
        
        if index == -1 {
          _commandTextField.stringValue = ""
        } else {
          // show the next command
          _commandTextField.stringValue = _commandsArray[index]
        }
      
      }
      return true
    }
    // return true if the action was handled; otherwise false
    return false
  }
}
