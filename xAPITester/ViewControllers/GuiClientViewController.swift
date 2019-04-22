//
//  GuiClientViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 4/10/19.
//  Copyright © 2019 Douglas Adams. All rights reserved.
//

import Cocoa
import xLib6000

class GuiClientViewController                   : NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  @IBOutlet private weak var _tableView         : NSTableView!
  
  private var _clients                          : [GuiClient] {
    return Array(Api.sharedInstance.guiClients.values)
  }

  // ----------------------------------------------------------------------------
  // MARK: - Overridden Methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    addNotifications()
  }
  
  override func viewWillAppear() {
    view.window!.level = .floating
  }

  // ----------------------------------------------------------------------------
  // MARK: - Notification Methods
  
  /// Add subsciptions to Notifications
  ///     (as of 10.11, subscriptions are automatically removed on deinit when using the Selector-based approach)
  ///
  private func addNotifications() {

    NC.makeObserver(self, with: #selector(guiClientsChanged(_:)), of: .guiClientHasBeenAdded)

    NC.makeObserver(self, with: #selector(guiClientsChanged(_:)), of: .guiClientWillBeRemoved)
  }
  /// Process guiClientHasBeenAdded or guiClientWillBeRemoved Notification
  ///
  /// - Parameter note:       a Notification instance
  ///
  @objc private func guiClientsChanged(_ note: Notification) {

    DispatchQueue.main.async { [weak self] in
      self?._tableView.reloadData()
    }
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - NSTableView DataSource methods
  
  ///
  ///
  /// - Parameter aTableView: the TableView
  /// - Returns:              number of rows
  ///
  public func numberOfRows(in aTableView: NSTableView) -> Int {
    
    return _clients.count
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
    view.toolTip =
    """
    Host:\t\t\(_clients[row].host)
    Ip:\t\t\(_clients[row].ip)
    """
    
    // set the text
    switch tableColumn!.identifier.rawValue {
      
    case "Handle":
      view.textField!.stringValue = _clients[row].handle.hex
    case "Station":
      view.textField!.stringValue = _clients[row].station
    case "Program":
      view.textField!.stringValue = _clients[row].program
    case "Id":
      view.textField!.stringValue = _clients[row].id?.uuidString ?? "Non-Gui"
    default:
      fatalError("Invalid column id - \(tableColumn!.identifier.rawValue)")
    }
    return view
  }
}
