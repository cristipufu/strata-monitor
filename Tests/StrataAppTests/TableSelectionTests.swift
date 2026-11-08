import AppKit
import StrataCore
import SwiftUI
import Testing

@testable import StrataBar

@MainActor private final class ClickedTable: NSTableView {
  var contextRow = -1
  override var clickedRow: Int { contextRow }
}

@Test @MainActor func contextActionsFreezeTheClickedRowAcrossReordering() {
  _ = NSApplication.shared
  let table = ClickedTable()
  table.addTableColumn(NSTableColumn(identifier: .init("0")))
  let first = process(10)
  let second = process(20)
  let selection = Binding<ProcessIdentity?>.constant(first.id)
  let coordinator = NativeExplorerTable<ProcessSample>.Coordinator(selection: selection)
  coordinator.table = table
  table.dataSource = coordinator
  table.delegate = coordinator
  let columns = [ExplorerColumn<ProcessSample>(id: "name", title: "Name", width: 200, value: \.name)]
  var performed: Int32?
  let actions: (ProcessSample) -> [ExplorerRowAction] = { row in
    [ExplorerRowAction(title: "Inspect") { performed = row.id.pid }]
  }
  coordinator.update(
    rows: [first, second], columns: columns, selection: selection, actions: actions)
  table.contextRow = 1
  let menu = NSMenu()
  coordinator.menuNeedsUpdate(menu)
  #expect(menu.numberOfItems == 1)
  coordinator.update(
    rows: [second, first], columns: columns, selection: selection, actions: actions)
  menu.performActionForItem(at: 0)
  #expect(performed == second.id.pid)
  table.contextRow = -1
  coordinator.menuNeedsUpdate(menu)
  #expect(menu.numberOfItems == 0)
}

@MainActor private func process(_ pid: Int32) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: UInt64(pid), startMicroseconds: 0),
    parentPID: 1, userID: 501, name: "Process \(pid)", path: "", cpuTimeNanoseconds: nil,
    residentBytes: nil, footprintBytes: nil, threads: nil)
}

@Test @MainActor func snapshotReplacementPreservesSelectionWithoutCallingBackIntoSwiftUI() {
  _ = NSApplication.shared
  let table = NSTableView()
  table.addTableColumn(NSTableColumn(identifier: .init("0")))
  let first = process(10)
  let second = process(20)
  var selected: ProcessIdentity? = first.id
  var writes = 0
  let binding = Binding(
    get: { selected },
    set: {
      selected = $0
      writes += 1
    })
  let coordinator = NativeExplorerTable<ProcessSample>.Coordinator(selection: binding)
  coordinator.table = table
  table.delegate = coordinator
  table.dataSource = coordinator
  let columns = [ExplorerColumn<ProcessSample>(id: "name", title: "Name", width: 200, value: \.name)]
  coordinator.update(rows: [first, second], columns: columns, selection: binding)
  #expect(table.selectedRow == 0)
  coordinator.update(rows: [second, first], columns: columns, selection: binding)
  #expect(table.selectedRow == 1)
  #expect(selected == first.id && writes == 0)
  coordinator.update(rows: [second], columns: columns, selection: binding)
  #expect(table.selectedRow == -1)
  #expect(selected == first.id && writes == 0)
}

@Test @MainActor func actualUserSelectionIsDeliveredAfterTheDelegateReturns() async {
  _ = NSApplication.shared
  let table = NSTableView()
  table.addTableColumn(NSTableColumn(identifier: .init("0")))
  let first = process(10)
  let second = process(20)
  var selected: ProcessIdentity?
  let binding = Binding(get: { selected }, set: { selected = $0 })
  let coordinator = NativeExplorerTable<ProcessSample>.Coordinator(selection: binding)
  coordinator.table = table
  table.delegate = coordinator
  table.dataSource = coordinator
  coordinator.update(
    rows: [first, second], columns: [.init(id: "name", title: "Name", width: 200, value: \.name)],
    selection: binding)
  table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
  #expect(selected == nil)
  for _ in 0..<10 { await Task.yield() }
  #expect(selected == second.id)
}
