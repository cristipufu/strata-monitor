import AppKit
import StrataCore
import SwiftUI

struct NativeProcessOutline: NSViewRepresentable {
  let snapshot: ProcessTreeSnapshot
  let columns: [ExplorerColumn<ProcessTreeRow>]
  @Binding var selection: ProcessIdentity?
  @Binding var sortDescriptors: [NSSortDescriptor]
  var actions: (ProcessSample) -> [ExplorerRowAction]
  var autosaveName: String?
  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
  func makeNSView(context: Context) -> NSScrollView {
    let outline = NSOutlineView()
    outline.delegate = context.coordinator
    outline.dataSource = context.coordinator
    outline.indentationPerLevel = 14
    outline.autoresizesOutlineColumn = false
    let scroll = ExplorerTablePresentation.scrollView(
      for: outline, columns: columns, autosaveName: autosaveName)
    outline.outlineTableColumn = outline.tableColumn(
      withIdentifier: NSUserInterfaceItemIdentifier(columns.first?.id ?? ""))
    context.coordinator.columnMenu.install(on: outline, keeping: columns.first?.id)
    let menu = NSMenu()
    menu.delegate = context.coordinator
    outline.menu = menu
    context.coordinator.outline = outline
    return scroll
  }
  func updateNSView(_ view: NSScrollView, context: Context) {
    context.coordinator.update(
      snapshot: snapshot, columns: columns, selection: $selection,
      sortDescriptors: $sortDescriptors, actions: actions)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize?
  {
    CGSize(width: proposal.width ?? 400, height: proposal.height ?? 400)
  }

  @MainActor final class Item: NSObject {
    let identity: ProcessIdentity
    var row: ProcessTreeRow
    var children: [Item] = []
    init(_ row: ProcessTreeRow) {
      identity = row.id
      self.row = row
    }
  }
  private struct Structure: Equatable {
    let identity: ProcessIdentity
    let parent: ProcessIdentity?
  }

  @MainActor
  final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate
  {
    weak var outline: NSOutlineView?
    private var items: [ProcessIdentity: Item] = [:]
    private var roots: [Item] = []
    private var structure: [Structure] = []
    private var columns: [ExplorerColumn<ProcessTreeRow>] = []
    private var selection: Binding<ProcessIdentity?>
    private var sortDescriptors: Binding<[NSSortDescriptor]> = .constant([])
    private var requestedSelection: ProcessIdentity?
    private var installingSnapshot = false
    private var wasSearching = false
    private var savedExpansion: Set<ProcessIdentity> = []
    private var actions: (ProcessSample) -> [ExplorerRowAction] = { _ in [] }
    private let menuActions = ExplorerMenuActions()
    let columnMenu = ExplorerColumnMenu()
    init(selection: Binding<ProcessIdentity?>) { self.selection = selection }

    func update(
      snapshot: ProcessTreeSnapshot, columns: [ExplorerColumn<ProcessTreeRow>],
      selection: Binding<ProcessIdentity?>,
      sortDescriptors: Binding<[NSSortDescriptor]> = .constant([]),
      actions: @escaping (ProcessSample) -> [ExplorerRowAction] = { _ in [] }
    ) {
      guard let outline else { return }
      installingSnapshot = true
      defer { installingSnapshot = false }
      let expanded = Set(items.values.filter(outline.isItemExpanded).map(\.identity))
      let selectionWasVisible =
        selection.wrappedValue.flatMap { items[$0] }.map { outline.row(forItem: $0) >= 0 } ?? false
      if snapshot.isSearching && !wasSearching { savedExpansion = expanded }
      self.columns = columns
      self.selection = selection
      self.sortDescriptors = sortDescriptors
      self.actions = actions
      ExplorerTablePresentation.showSortOrder(sortDescriptors.wrappedValue, in: outline)
      ExplorerTablePresentation.setTitles(of: columns, in: outline)
      let changed = install(snapshot.rows)
      restoreExpansion(after: snapshot, structureChanged: changed, previouslyExpanded: expanded)
      synchronizeSelection(structureChanged: changed, wasVisible: selectionWasVisible)
      if !changed { reloadVisibleRows() }
    }
    private func install(_ rows: [ProcessTreeRow]) -> Bool {
      let next = rows.map { Structure(identity: $0.id, parent: $0.parent) }
      guard structure != next else {
        for row in rows { items[row.id]?.row = row }
        return false
      }
      var cache: [ProcessIdentity: Item] = [:]
      for row in rows {
        let item = items[row.id] ?? Item(row)
        item.row = row
        item.children = []
        cache[row.id] = item
      }
      items = cache
      rebuildRelationships(rows)
      structure = next
      outline?.reloadData()
      return true
    }
    private func rebuildRelationships(_ rows: [ProcessTreeRow]) {
      roots = []
      for row in rows {
        guard let item = items[row.id] else { continue }
        if let parent = row.parent.flatMap({ items[$0] }) {
          parent.children.append(item)
        } else {
          roots.append(item)
        }
      }
    }
    private func restoreExpansion(
      after snapshot: ProcessTreeSnapshot, structureChanged: Bool,
      previouslyExpanded: Set<ProcessIdentity>
    ) {
      if snapshot.isSearching {
        expandAncestors(of: Set(snapshot.rows.map(\.id)))
      } else if wasSearching {
        outline?.collapseItem(nil, collapseChildren: true)
        restoreExpansion(savedExpansion)
        savedExpansion.removeAll()
      } else if structureChanged {
        restoreExpansion(previouslyExpanded)
      }
      wasSearching = snapshot.isSearching
    }
    private func synchronizeSelection(structureChanged: Bool, wasVisible: Bool) {
      guard let outline else { return }
      let shouldReveal = selection.wrappedValue != requestedSelection
      if let id = selection.wrappedValue, items[id] != nil,
        id != requestedSelection || (structureChanged && wasVisible)
      {
        expandAncestors(of: [id])
        requestedSelection = id
      }
      if selection.wrappedValue == nil { requestedSelection = nil }
      guard let id = selection.wrappedValue, let item = items[id], outline.row(forItem: item) >= 0
      else {
        if selection.wrappedValue.flatMap({ items[$0] }) == nil { requestedSelection = nil }
        outline.deselectAll(nil)
        return
      }
      let row = outline.row(forItem: item)
      if outline.selectedRow != row {
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      }
      if shouldReveal { outline.scrollRowToVisible(row) }
    }
    private func restoreExpansion(_ identities: Set<ProcessIdentity>) {
      // Parents must be visible before their child expansion is restored.
      var pending = roots.reversed().map { $0 }
      while let item = pending.popLast() {
        if identities.contains(item.identity) { outline?.expandItem(item) }
        pending.append(contentsOf: item.children.reversed())
      }
    }
    private func expandAncestors(of identities: Set<ProcessIdentity>) {
      var ancestors = Set<ProcessIdentity>()
      for identity in identities {
        var parent = items[identity]?.row.parent
        while let next = parent, ancestors.insert(next).inserted {
          parent = items[next]?.row.parent
        }
      }
      restoreExpansion(ancestors)
    }
    private func reloadVisibleRows() {
      guard let outline else { return }
      ExplorerTablePresentation.refreshVisibleCells(in: outline, definitions: columns) {
        (outline.item(atRow: $0) as? Item)?.row
      }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
      (item as? Item)?.children.count ?? roots.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
      ((item as? Item)?.children ?? roots)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
      (item as? Item)?.children.isEmpty == false
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
      -> NSView?
    {
      guard let item = item as? Item else { return nil }
      return ExplorerTablePresentation.cell(
        in: outlineView, column: tableColumn, definitions: columns, row: item.row)
    }
    func outlineView(
      _ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      guard !installingSnapshot else { return }
      sortDescriptors.wrappedValue = outlineView.sortDescriptors
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
      guard !installingSnapshot, let outline else { return }
      let identity = (outline.item(atRow: outline.selectedRow) as? Item)?.identity
      Task { @MainActor [weak self] in
        guard let self, let outline = self.outline,
          (outline.item(atRow: outline.selectedRow) as? Item)?.identity == identity
        else { return }
        self.selection.wrappedValue = identity
      }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
      guard let outline, let item = outline.item(atRow: outline.clickedRow) as? Item else {
        menuActions.install([], in: menu)
        return
      }
      menuActions.install(actions(item.row.process), in: menu)
    }
  }
}
