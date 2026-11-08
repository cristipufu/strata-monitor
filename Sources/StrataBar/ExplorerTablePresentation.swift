import AppKit
import StrataCore

@MainActor enum ExplorerTablePresentation {
  static func scrollView<Row>(
    for table: NSTableView, columns: [ExplorerColumn<Row>], autosaveName: String? = nil
  ) -> NSScrollView {
    table.style = .inset
    table.rowHeight = 30
    table.usesAlternatingRowBackgroundColors = true
    table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    table.allowsEmptySelection = true
    for (index, definition) in columns.enumerated() {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.id))
      column.minWidth = index == 0 ? 100 : min(definition.width, 60)
      column.width = definition.width
      column.sortDescriptorPrototype = definition.sortPrototype
      column.isHidden = !definition.isShownByDefault
      setTitle(definition.title, of: column)
      table.addTableColumn(column)
    }
    // Restores the person's widths, order and shown columns once every column exists.
    if let autosaveName {
      table.autosaveName = autosaveName
      table.autosaveTableColumns = true
    }
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = table
    return scroll
  }
  // Header titles grow when localized; a column never starts narrower than its title.
  static func setTitle(_ title: String, of column: NSTableColumn) {
    column.title = title
    column.headerToolTip = title
    let titleWidth = (column.headerCell.cellSize.width + 12).rounded(.up)
    column.minWidth = max(column.minWidth, titleWidth)
    if column.width < titleWidth { column.width = titleWidth }
  }
  static func setTitles<Row>(of definitions: [ExplorerColumn<Row>], in table: NSTableView) {
    for definition in definitions {
      guard let column = table.tableColumn(withIdentifier: .init(definition.id)) else { continue }
      if column.title != definition.title { setTitle(definition.title, of: column) }
    }
  }
  static func showSortOrder(_ descriptors: [NSSortDescriptor], in table: NSTableView) {
    if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
  }
  static func cell<Row>(
    in table: NSTableView, column: NSTableColumn?, definitions: [ExplorerColumn<Row>], row: Row
  ) -> NSView? {
    guard let identifier = column?.identifier,
      let index = definitions.firstIndex(where: { $0.id == identifier.rawValue })
    else { return nil }
    let cell =
      table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
      ?? centeredCell(identifier)
    configure(cell, definition: definitions[index], isPrimary: index == 0, row: row)
    return cell
  }
  // Each reading updates the cells already on screen; replacing them allocated a new cell
  // for every visible value every two seconds.
  static func refreshVisibleCells<Row>(
    in table: NSTableView, definitions: [ExplorerColumn<Row>], row: (Int) -> Row?
  ) {
    let range = table.rows(in: table.visibleRect)
    guard range.location != NSNotFound, range.length > 0 else { return }
    for rowIndex in range.location..<min(table.numberOfRows, range.location + range.length) {
      guard let value = row(rowIndex) else { continue }
      for (columnIndex, column) in table.tableColumns.enumerated() {
        guard let index = definitions.firstIndex(where: { $0.id == column.identifier.rawValue }),
          let cell = table.view(atColumn: columnIndex, row: rowIndex, makeIfNecessary: false)
            as? NSTableCellView
        else { continue }
        configure(cell, definition: definitions[index], isPrimary: index == 0, row: value)
      }
    }
  }
  private static func configure<Row>(
    _ cell: NSTableCellView, definition: ExplorerColumn<Row>, isPrimary: Bool, row: Row
  ) {
    guard let field = cell.textField else { return }
    let text = definition.value(row)
    if field.stringValue != text {
      field.stringValue = text
      field.toolTip = text
    }
    let font: NSFont =
      definition.monospaced
      ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
    if field.font != font { field.font = font }
    let color: NSColor = isPrimary ? .labelColor : .secondaryLabelColor
    if field.textColor != color { field.textColor = color }
  }
  private static func centeredCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let field = NSTextField(labelWithString: "")
    field.translatesAutoresizingMaskIntoConstraints = false
    field.lineBreakMode = .byTruncatingMiddle
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    cell.addSubview(field)
    cell.textField = field
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
      field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
}

extension ResourceKind {
  var title: String {
    switch self {
    case .file: String(localized: "File")
    case .directory: String(localized: "Folder")
    case .device: String(localized: "Device")
    case .pipe: String(localized: "Pipe")
    case .unixSocket: String(localized: "Unix socket")
    case .tcp: String(localized: "TCP")
    case .udp: String(localized: "UDP")
    case .other: String(localized: "Other")
    }
  }
}

extension ProcessResource {
  var location: String { path.isEmpty ? endpoint : path }
}

// The header's menu shows and hides columns; the table's autosave keeps the choice.
@MainActor final class ExplorerColumnMenu: NSObject, NSMenuDelegate {
  private weak var table: NSTableView?
  private var keptColumn: String?
  func install(on table: NSTableView, keeping keptColumn: String?) {
    self.table = table
    self.keptColumn = keptColumn
    let menu = NSMenu()
    menu.delegate = self
    table.headerView?.menu = menu
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    for column in table?.tableColumns ?? [] where column.identifier.rawValue != keptColumn {
      let item = menu.addItem(
        withTitle: column.title, action: #selector(toggle(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = column.identifier.rawValue
      item.state = column.isHidden ? .off : .on
    }
  }
  @objc private func toggle(_ item: NSMenuItem) {
    guard let identifier = item.representedObject as? String,
      let column = table?.tableColumn(withIdentifier: .init(identifier))
    else { return }
    column.isHidden.toggle()
  }
}
