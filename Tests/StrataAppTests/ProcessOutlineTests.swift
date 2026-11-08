import AppKit
import StrataCore
import SwiftUI
import Testing

@testable import StrataBar

@MainActor private final class ContextOutline: NSOutlineView {
  var contextRow = -1
  override var clickedRow: Int { contextRow }
}

@Test @MainActor func outlineRevealsASelectedChildWhenItsPreviouslyMissingParentAppears() {
  _ = NSApplication.shared
  let outline = NSOutlineView()
  outline.addTableColumn(NSTableColumn(identifier: .init("0")))
  let root = outlineProcess(10)
  let child = outlineProcess(20, parent: 10)
  let selection = Binding<ProcessIdentity?>.constant(child.id)
  let coordinator = NativeProcessOutline.Coordinator(selection: selection)
  coordinator.outline = outline
  outline.delegate = coordinator
  outline.dataSource = coordinator
  let columns = [ExplorerColumn<ProcessTreeRow>(id: "name", title: "Process", width: 250, value: \.title)]
  coordinator.update(
    snapshot: ProcessTreeSnapshot(families: ProcessFamilies([child]), query: "", order: ProcessOrder(.name)),
    columns: columns,
    selection: selection)
  coordinator.update(
    snapshot: ProcessTreeSnapshot(families: ProcessFamilies([root, child]), query: "", order: ProcessOrder(.name)),
    columns: columns, selection: selection)
  #expect(outline.numberOfRows == 2)
  #expect(
    (outline.item(atRow: outline.selectedRow) as? NativeProcessOutline.Item)?.identity == child.id)
}

@Test @MainActor func outlineDefersSelectionWritesAndFreezesTheClickedContextTarget() async {
  _ = NSApplication.shared
  let outline = ContextOutline()
  outline.addTableColumn(NSTableColumn(identifier: .init("0")))
  let first = outlineProcess(10)
  let second = outlineProcess(20)
  var selected: ProcessIdentity? = first.id
  let selection = Binding(get: { selected }, set: { selected = $0 })
  let coordinator = NativeProcessOutline.Coordinator(selection: selection)
  coordinator.outline = outline
  outline.delegate = coordinator
  outline.dataSource = coordinator
  let columns = [ExplorerColumn<ProcessTreeRow>(id: "name", title: "Process", width: 250, value: \.title)]
  var contextPID: Int32?
  let actions: (ProcessSample) -> [ExplorerRowAction] = { process in
    [ExplorerRowAction(title: "Inspect") { contextPID = process.id.pid }]
  }
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies([first, second]), query: "", order: ProcessOrder(.name)),
    columns: columns, selection: selection, actions: actions)
  outline.contextRow = 1
  let menu = NSMenu()
  coordinator.menuNeedsUpdate(menu)
  outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
  #expect(selected == first.id)
  for _ in 0..<10 { await Task.yield() }
  #expect(selected == second.id)
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies([outlineProcess(10, cpu: 100), second]), query: "", order: ProcessOrder(.cpu)),
    columns: columns,
    selection: selection, actions: actions)
  menu.performActionForItem(at: 0)
  #expect(contextPID == second.id.pid)
}

private func outlineProcess(_ pid: Int32, parent: Int32 = 1, start: UInt64 = 1, cpu: Double? = 10)
  -> ProcessSample
{
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0), parentPID: parent,
    userID: 501,
    name: "Process \(pid)", path: "", cpuTimeNanoseconds: nil, cpuPercent: cpu, residentBytes: nil,
    footprintBytes: 100, threads: nil)
}
@MainActor private func outlineItem(_ id: ProcessIdentity, in outline: NSOutlineView)
  -> NativeProcessOutline.Item?
{
  (0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? NativeProcessOutline.Item }
    .first { $0.identity == id }
}

@Test @MainActor func nativeOutlinePreservesExpandedSelectionAcrossUpdatesAndRejectsReusedPID()
  throws
{
  _ = NSApplication.shared
  let outline = NSOutlineView()
  outline.addTableColumn(NSTableColumn(identifier: .init("0")))
  let root = outlineProcess(10)
  let child = outlineProcess(20, parent: 10)
  let grandchild = outlineProcess(30, parent: 20)
  var selected: ProcessIdentity? = grandchild.id
  var writes = 0
  let binding = Binding(
    get: { selected },
    set: {
      selected = $0
      writes += 1
    })
  let coordinator = NativeProcessOutline.Coordinator(selection: binding)
  coordinator.outline = outline
  outline.delegate = coordinator
  outline.dataSource = coordinator
  let columns = [ExplorerColumn<ProcessTreeRow>(id: "name", title: "Process", width: 250, value: \.title)]
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies([root, child, grandchild]), query: "", order: ProcessOrder(.name)),
    columns: columns, selection: binding)
  #expect(outline.numberOfRows == 3)
  #expect(
    (outline.item(atRow: outline.selectedRow) as? NativeProcessOutline.Item)?.identity
      == grandchild.id)
  let rootItem = try #require(outlineItem(root.id, in: outline))
  #expect(outline.isItemExpanded(rootItem))
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies([grandchild, child, root, outlineProcess(40, cpu: 500)]), query: "",
      order: ProcessOrder(.cpu)),
    columns: columns, selection: binding)
  #expect(outlineItem(root.id, in: outline) === rootItem)
  #expect(outline.isItemExpanded(rootItem))
  #expect(
    (outline.item(atRow: outline.selectedRow) as? NativeProcessOutline.Item)?.identity
      == grandchild.id)
  #expect(writes == 0)
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies([root, child, outlineProcess(30, parent: 20, start: 2)]), query: "",
      order: ProcessOrder(.name)),
    columns: columns, selection: binding)
  #expect(outline.selectedRow == -1 && selected == grandchild.id && writes == 0)
}

@Test @MainActor func outlineSearchRevealsAncestorsThenRestoresUserExpansion() throws {
  _ = NSApplication.shared
  let outline = NSOutlineView()
  outline.addTableColumn(NSTableColumn(identifier: .init("0")))
  let root = outlineProcess(10)
  let child = outlineProcess(20, parent: 10)
  let grandchild = outlineProcess(30, parent: 20)
  let processes = [root, child, grandchild]
  let selection = Binding<ProcessIdentity?>.constant(nil)
  let coordinator = NativeProcessOutline.Coordinator(selection: selection)
  coordinator.outline = outline
  outline.delegate = coordinator
  outline.dataSource = coordinator
  let columns = [ExplorerColumn<ProcessTreeRow>(id: "name", title: "Process", width: 250, value: \.title)]
  coordinator.update(
    snapshot: ProcessTreeSnapshot(families: ProcessFamilies(processes), query: "", order: ProcessOrder(.name)),
    columns: columns,
    selection: selection)
  #expect(outline.numberOfRows == 1)
  let item = try #require(outlineItem(root.id, in: outline))
  outline.expandItem(item)
  #expect(outline.numberOfRows == 2)
  coordinator.update(
    snapshot: ProcessTreeSnapshot(
      families: ProcessFamilies(processes), query: "pid:30", order: ProcessOrder(.name)),
    columns: columns, selection: selection)
  #expect(outline.numberOfRows == 3)
  coordinator.update(
    snapshot: ProcessTreeSnapshot(families: ProcessFamilies(processes), query: "", order: ProcessOrder(.name)),
    columns: columns,
    selection: selection)
  #expect(outline.numberOfRows == 2)
  let restored = try #require(outlineItem(root.id, in: outline))
  #expect(outline.isItemExpanded(restored))
}

@Test func familyOrderingCountsEachMeasuredMemberOnceAndHandlesUnavailableValues() throws {
  let root = outlineProcess(10, cpu: 1)
  let child = outlineProcess(20, parent: 10, cpu: 90)
  let separate = outlineProcess(30, cpu: 50)
  let snapshot = ProcessTreeSnapshot(
    families: ProcessFamilies([separate, child, root]), query: "pid:20", order: ProcessOrder(.cpu))
  let rootRow = try #require(snapshot.rows.first { $0.id == root.id })
  #expect(rootRow.cpu == 91 && rootRow.family?.members.count == 2)
  #expect(snapshot.rows.first?.id == root.id && snapshot.matchingCount == 1)
  let unavailable = outlineProcess(50, cpu: .nan)
  let zero = outlineProcess(60, cpu: 0)
  #expect(ProcessOrder(.cpu).areInIncreasingOrder(zero, unavailable))
  #expect(!ProcessOrder(.cpu).areInIncreasingOrder(unavailable, zero))
  #expect(
    ProcessFamilies([root, child, separate]).roots.reduce(0) { $0 + ($1.cpuPercent ?? 0) } == 141)
}
