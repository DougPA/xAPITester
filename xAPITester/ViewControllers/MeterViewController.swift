//
//  MeterViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 3/15/19.
//  Copyright © 2019 Douglas Adams. All rights reserved.
//

import Cocoa
import xLib6000

class MeterViewController                     : NSViewController, NSTableViewDelegate, NSTableViewDataSource {


  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  @IBOutlet weak var _tableView               : NSTableView!
  @IBOutlet weak var _meterValue              : NSTextField!
  @IBOutlet weak var _meterUnits              : NSTextField!
  
  private var _array                          = [Meter]()
  
  // ----------------------------------------------------------------------------
  // MARK: - Overridden Methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    addNotifications()
  }

  // ----------------------------------------------------------------------------
  // MARK: - Notification Methods
  
  /// Add subsciptions to Notifications
  ///     (as of 10.11, subscriptions are automatically removed on deinit when using the Selector-based approach)
  ///
  private func addNotifications() {
    
    NC.makeObserver(self, with: #selector(meterAddedRemoved(_:)), of: .meterHasBeenAdded)
    
    NC.makeObserver(self, with: #selector(meterAddedRemoved(_:)), of: .meterWillBeRemoved)
    
    NC.makeObserver(self, with: #selector(meterUpdated(_:)), of: .meterUpdated)
  }
  /// Process meterHasBeenAdded or meterWillBeRemoved Notification
  ///
  /// - Parameter note:       a Notification instance
  ///
  @objc private func meterAddedRemoved(_ note: Notification) {
  
    DispatchQueue.main.async { [weak self] in
      self?._tableView.reloadData()
    }
  }
  /// Process meterUpdated Notification
  ///
  /// - Parameter note:       a Notification instance
  ///
  @objc private func meterUpdated(_ note: Notification) {
    
      DispatchQueue.main.async { [weak self] in
        if let self = self {
          let row = self._tableView.selectedRow
          if row >= 0 {
            //      self?._tableView.reloadData()
            self._meterValue.stringValue = String(format: "%3.2f",self._array[row].value)
            self._meterUnits.stringValue = self._array[row].units
          }
        }
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
    
    if let radio = Api.sharedInstance.radio {
      _array = Array(radio.meters.values).sorted(by: {Int($0.number, radix: 10) ?? 0 < Int($1.number, radix: 10) ?? 0})
    }
    return _array.count
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
    
    // set the text
    switch tableColumn!.identifier.rawValue {
      
    case "Number":
      view.textField!.stringValue = _array[row].number
    case "Source":
      view.textField!.stringValue = _array[row].source
    case "Name":
      view.textField!.stringValue = _array[row].name
    case "Units":
      view.textField!.stringValue = _array[row].units
    case "Low":
      view.textField!.stringValue = String(format: "%3.2f",_array[row].low)
    case "High":
      view.textField!.stringValue = String(format: "%3.2f",_array[row].high)
    case "Fps":
      view.textField!.integerValue = _array[row].fps
    case "Description":
      view.textField!.stringValue = _array[row].desc
    default:
      fatalError("Invalid column id - \(tableColumn!.identifier.rawValue)")
    }

    return view
  }
}
