import AppKit
import SwiftUI

struct ExplorerColumn<Row> {
  let id: String
  let title: String
  let width: CGFloat
  let value: (Row) -> String
  var monospaced = false
  var sortPrototype: NSSortDescriptor?
  var isShownByDefault = true
}

extension ExplorerColumn {
  init<Key: ExplorerSortKey>(
    title: String, width: CGFloat, value: @escaping (Row) -> String, monospaced: Bool = false,
    sortedBy key: Key, isShownByDefault: Bool = true
  ) {
    self.init(
      id: key.rawValue, title: title, width: width, value: value, monospaced: monospaced,
      sortPrototype: ExplorerSortOrder(key).descriptor, isShownByDefault: isShownByDefault)
  }
}

/// AppKit owns row reuse, selection and header clicks; SwiftUI supplies immutable
/// snapshots in the chosen order. Delegate callbacks never synchronously mutate the
/// snapshot being installed.
struct NativeExplorerTable<Row: Identifiable>: NSViewRepresentable {
  let rows: [Row]
  let columns: [ExplorerColumn<Row>]
  @Binding var selection: Row.ID?
  @Binding var sortDescriptors: [NSSortDescriptor]
  var actions: (Row) -> [ExplorerRowAction] = { _ in [] }
  var autosaveName: String?

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
  func makeNSView(context: Context) -> NSScrollView {
    let table = NSTableView()
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    let menu = NSMenu()
    menu.delegate = context.coordinator
    table.menu = menu
    let scroll = ExplorerTablePresentation.scrollView(
      for: table, columns: columns, autosaveName: autosaveName)
    context.coordinator.columnMenu.install(on: table, keeping: columns.first?.id)
    context.coordinator.table = table
    return scroll
  }
  func updateNSView(_ view: NSScrollView, context: Context) {
    context.coordinator.update(
      rows: rows, columns: columns, selection: $selection, sortDescriptors: $sortDescriptors,
      actions: actions)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize?
  {
    // This scroll viewport fills its assigned region. Its initial column
    // widths must not become an implicit minimum for the enclosing window.
    CGSize(width: proposal.width ?? 400, height: proposal.height ?? 400)
  }

  @MainActor
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var table: NSTableView?
    private var rows: [Row] = []
    private var columns: [ExplorerColumn<Row>] = []
    private var selection: Binding<Row.ID?>
    private var sortDescriptors: Binding<[NSSortDescriptor]> = .constant([])
    private var revealedSelection: Row.ID?
    private var installingSnapshot = false
    private var actions: (Row) -> [ExplorerRowAction] = { _ in [] }
    private let menuActions = ExplorerMenuActions()
    let columnMenu = ExplorerColumnMenu()
    init(selection: Binding<Row.ID?>) { self.selection = selection }

    func update(
      rows: [Row], columns: [ExplorerColumn<Row>], selection: Binding<Row.ID?>,
      sortDescriptors: Binding<[NSSortDescriptor]> = .constant([]),
      actions: @escaping (Row) -> [ExplorerRowAction] = { _ in [] }
    ) {
      guard let table else { return }
      installingSnapshot = true
      defer { installingSnapshot = false }
      let structureChanged = self.rows.map(\.id) != rows.map(\.id)
      self.rows = rows
      self.columns = columns
      self.selection = selection
      self.sortDescriptors = sortDescriptors
      self.actions = actions
      ExplorerTablePresentation.showSortOrder(sortDescriptors.wrappedValue, in: table)
      ExplorerTablePresentation.setTitles(of: columns, in: table)
      if structureChanged {
        table.reloadData()
      } else {
        ExplorerTablePresentation.refreshVisibleCells(in: table, definitions: columns) {
          rows.indices.contains($0) ? rows[$0] : nil
        }
      }
      if let id = selection.wrappedValue, let index = rows.firstIndex(where: { $0.id == id }) {
        if table.selectedRow != index {
          table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        if revealedSelection != id {
          table.scrollRowToVisible(index)
          revealedSelection = id
        }
      } else {
        revealedSelection = nil
        table.deselectAll(nil)
      }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
      guard let row = table?.clickedRow, rows.indices.contains(row) else {
        menuActions.install([], in: menu)
        return
      }
      // Freeze the clicked row's values. Later sampling or sorting must not
      // change the target of an already open context menu.
      menuActions.install(actions(rows[row]), in: menu)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(
      _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      guard !installingSnapshot else { return }
      sortDescriptors.wrappedValue = tableView.sortDescriptors
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard rows.indices.contains(row) else { return nil }
      return ExplorerTablePresentation.cell(
        in: tableView, column: tableColumn, definitions: columns, row: rows[row])
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
      guard !installingSnapshot, let table else { return }
      let row = table.selectedRow
      let id = rows.indices.contains(row) ? rows[row].id : nil
      Task { @MainActor [weak self] in
        guard let self, let table = self.table else { return }
        let current =
          self.rows.indices.contains(table.selectedRow) ? self.rows[table.selectedRow].id : nil
        guard current == id else { return }
        self.selection.wrappedValue = id
      }
    }
  }
}
