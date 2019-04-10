//
//  MeterViewController.swift
//  xAPITester
//
//  Created by Douglas Adams on 3/15/19.
//  Copyright © 2019 Douglas Adams. All rights reserved.
//

import Cocoa
import xLib6000
import SwiftyUserDefaults

class MeterViewController                     : NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public enum MetersFilters: Int {
    case none = 0
    case source
    case number
    case name
    case group
  }

  // ----------------------------------------------------------------------------
  // MARK: - Internal properties
  
  internal var _filteredMeters                : [Meter] {
    get {

      Swift.print("FilterMetersByTag = \(Defaults[.filterMetersByTag])")
      
      switch MetersFilters(rawValue: Defaults[.filterMetersByTag]) ?? .none {
      
      case .none:     return _meters
      case .source:   return _meters.filter { $0.source == Defaults[.filterMeters] }
      case .number:   return _meters.filter { $0.number == Defaults[.filterMeters] }
      case .name:     return _meters.filter { $0.name == Defaults[.filterMeters] }
      case .group:    return _meters.filter { $0.group == Defaults[.filterMeters] }
      }
    }}

  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  @IBOutlet private weak var filterMetersBy    : NSPopUpButton!
  @IBOutlet private weak var filterMetersText  : NSTextField!
  @IBOutlet private weak var _tableView        : NSTableView!
  @IBOutlet private weak var _meterValue       : NSTextField!
  @IBOutlet private weak var _meterUnits       : NSTextField!
  
  private var _meters                          = [Meter]()
  
  // ----------------------------------------------------------------------------
  // MARK: - Overridden Methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    addNotifications()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Action Methods
  
  /// The FilterBy PopUp changed (in the Objects box)
  ///
  /// - Parameter sender:     the popup
  ///
  @IBAction func updateFilterBy(_ sender: NSPopUpButton) {
    
    // clear the Filter string field
    Defaults[.filterMeters] = ""
    Defaults[.filterMetersByTag] = sender.selectedTag()
    
    // force a redraw
    reloadMetersTable()
  }
  /// The Filter text field changed (in the Objects box)
  ///
  /// - Parameter sender:     the text field
  ///
  @IBAction func updateFilterText(_ sender: NSTextField) {
    
    Defaults[.filterMeters] = sender.stringValue
    
    // force a redraw
    reloadMetersTable()
  }
  
  // ----------------------------------------------------------------------------
  // MARK: - Internal Methods
  
  /// Refresh the TableView & make its last row visible
  ///
  internal func reloadMetersTable() {
    
    DispatchQueue.main.async { [unowned self] in

      self.filterMetersText.stringValue = Defaults[.filterMeters]

      // reload the table
      self._tableView.reloadData()
    }
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
            self._meterValue.stringValue = String(format: "%3.2f", self._filteredMeters[row].value)
            self._meterUnits.stringValue = self._filteredMeters[row].units
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
      _meters = Array(radio.meters.values).sorted(by: {Int($0.number, radix: 10) ?? 0 < Int($1.number, radix: 10) ?? 0})
    }
    
    Swift.print("Meters count = \(_filteredMeters.count)")
    
    return _filteredMeters.count
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
      view.textField!.stringValue = _filteredMeters[row].number
    case "Source":
      view.textField!.stringValue = _filteredMeters[row].source
    case "Name":
      view.textField!.stringValue = _filteredMeters[row].name
    case "Units":
      view.textField!.stringValue = _filteredMeters[row].units
    case "Low":
      view.textField!.stringValue = String(format: "%3.2f", _filteredMeters[row].low)
    case "High":
      view.textField!.stringValue = String(format: "%3.2f", _filteredMeters[row].high)
    case "Fps":
      view.textField!.integerValue = _filteredMeters[row].fps
    case "Description":
      view.textField!.stringValue = _filteredMeters[row].desc
    default:
      fatalError("Invalid column id - \(tableColumn!.identifier.rawValue)")
    }

    return view
  }
}
