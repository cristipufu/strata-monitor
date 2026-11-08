import AppKit
import StrataCore
import SwiftUI
import XCTest

@testable import StrataBar

final class ExplorerTableSortingTests: CocoaTestCase {
  @MainActor func testHeaderSortReordersTheTableAndKeepsTheSelectedProcess() {
    _ = NSApplication.shared
    let table = NSTableView()
    let columns = [
      ExplorerColumn<ProcessSample>(
        title: "Process", width: 200, value: \.name, sortedBy: ProcessSort.name),
      ExplorerColumn<ProcessSample>(
        title: "CPU", width: 80, value: { "\($0.cpuPercent ?? 0)" }, sortedBy: ProcessSort.cpu),
    ]
    _ = ExplorerTablePresentation.scrollView(for: table, columns: columns)
    XCTAssertEqual(
      table.tableColumns.map(\.sortDescriptorPrototype),
      [ProcessOrder(.name).descriptor, ProcessOrder(.cpu).descriptor])
    let processes = [
      tableProcess(10, cpu: 1), tableProcess(20, cpu: 90), tableProcess(30, cpu: 50),
    ]
    var order = ProcessOrder(.name)
    var orderWrites = 0
    let sortDescriptors = Binding(
      get: { order.descriptors },
      set: {
        order.descriptors = $0
        orderWrites += 1
      })
    var selected: ProcessIdentity? = processes[2].id
    let selection = Binding(get: { selected }, set: { selected = $0 })
    let coordinator = NativeExplorerTable<ProcessSample>.Coordinator(selection: selection)
    coordinator.table = table
    table.dataSource = coordinator
    table.delegate = coordinator
    let update = {
      coordinator.update(
        rows: processes.sorted(by: order.areInIncreasingOrder), columns: columns,
        selection: selection, sortDescriptors: sortDescriptors)
    }
    update()
    XCTAssertEqual(table.sortDescriptors, [ProcessOrder(.name).descriptor])
    XCTAssertEqual(table.selectedRow, 2)
    XCTAssertEqual(orderWrites, 0)
    table.sortDescriptors = [ProcessOrder(.cpu).descriptor, ProcessOrder(.name).descriptor]
    XCTAssertEqual(order, ProcessOrder(.cpu))
    XCTAssertEqual(orderWrites, 1)
    update()
    XCTAssertEqual(table.sortDescriptors, [ProcessOrder(.cpu).descriptor])
    XCTAssertEqual(table.selectedRow, 1)
    XCTAssertEqual(selected, processes[2].id)
    XCTAssertEqual(orderWrites, 1)
  }

  @MainActor func testFamilyHeaderSortReachesTheOrderWhileSnapshotsDoNotWriteBack() {
    _ = NSApplication.shared
    let outline = NSOutlineView()
    let columns = [
      ExplorerColumn<ProcessTreeRow>(
        title: "Process Family", width: 200, value: \.title, sortedBy: ProcessSort.name),
      ExplorerColumn<ProcessTreeRow>(
        title: "PID", width: 60, value: { String($0.id.pid) }, sortedBy: ProcessSort.pid),
    ]
    _ = ExplorerTablePresentation.scrollView(for: outline, columns: columns)
    let processes = [tableProcess(10, cpu: 1), tableProcess(20, cpu: 90)]
    var order = ProcessOrder(.pid, ascending: false)
    var orderWrites = 0
    let sortDescriptors = Binding(
      get: { order.descriptors },
      set: {
        order.descriptors = $0
        orderWrites += 1
      })
    let selection = Binding<ProcessIdentity?>.constant(nil)
    let coordinator = NativeProcessOutline.Coordinator(selection: selection)
    coordinator.outline = outline
    outline.dataSource = coordinator
    outline.delegate = coordinator
    coordinator.update(
      snapshot: ProcessTreeSnapshot(families: ProcessFamilies(processes), query: "", order: order),
      columns: columns, selection: selection, sortDescriptors: sortDescriptors)
    XCTAssertEqual(outline.sortDescriptors, [ProcessOrder(.pid, ascending: false).descriptor])
    XCTAssertEqual(orderWrites, 0)
    outline.sortDescriptors = [ProcessOrder(.name).descriptor]
    XCTAssertEqual(order, ProcessOrder(.name))
    XCTAssertEqual(orderWrites, 1)
  }
}

private func tableProcess(_ pid: Int32, cpu: Double) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: 501, name: "Process \(pid)", path: "", cpuTimeNanoseconds: nil, cpuPercent: cpu,
    residentBytes: nil, footprintBytes: nil, threads: nil)
}
