import AppKit
import StrataCore
import SwiftUI
import Testing

@testable import StrataBar

@Test(arguments: [ProcessGrouping.individual, .families]) @MainActor
func requestedProcessIsRevealedOnceWithoutOverridingLaterManualScrolling(
  _ grouping: ProcessGrouping
) {
  _ = NSApplication.shared
  let rows = (1...100).map { pid in
    ProcessSample(
      id: ProcessIdentity(pid: Int32(pid), startSeconds: 1, startMicroseconds: 0),
      parentPID: 1, userID: 501, name: String(format: "Process %03d", pid), path: "",
      cpuTimeNanoseconds: nil, residentBytes: nil, footprintBytes: nil, threads: nil)
  }
  var selection = rows.last?.id
  let binding = Binding(get: { selection }, set: { selection = $0 })
  let table: NSTableView
  let update: @MainActor () -> Void
  if grouping == .families {
    let outline = NSOutlineView()
    let coordinator = NativeProcessOutline.Coordinator(selection: binding)
    coordinator.outline = outline
    outline.delegate = coordinator
    outline.dataSource = coordinator
    table = outline
    update = {
      coordinator.update(
        snapshot: ProcessTreeSnapshot(
          families: ProcessFamilies(rows), query: "", order: ProcessOrder(.name)),
        columns: [ExplorerColumn<ProcessTreeRow>(id: "name", title: "Process", width: 250, value: \.title)],
        selection: binding)
    }
  } else {
    table = NSTableView()
    let coordinator = NativeExplorerTable<ProcessSample>.Coordinator(selection: binding)
    coordinator.table = table
    table.delegate = coordinator
    table.dataSource = coordinator
    update = {
      coordinator.update(
        rows: rows,
        columns: [ExplorerColumn<ProcessSample>(id: "name", title: "Process", width: 250, value: \.name)],
        selection: binding)
    }
  }
  let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
  table.addTableColumn(NSTableColumn(identifier: .init("0")))
  table.rowHeight = 28
  table.frame = NSRect(x: 0, y: 0, width: 300, height: 3000)
  scroll.documentView = table
  update()
  #expect(table.selectedRow == 99)
  #expect(table.visibleRect.intersects(table.rect(ofRow: 99)))
  table.scrollRowToVisible(0)
  let manualPosition = scroll.contentView.bounds.origin
  update()
  #expect(scroll.contentView.bounds.origin == manualPosition)
  selection = rows[50].id
  update()
  #expect(table.visibleRect.intersects(table.rect(ofRow: 50)))
}
