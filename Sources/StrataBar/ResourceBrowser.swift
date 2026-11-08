import StrataCore
import SwiftUI

struct ResourceBrowser: View {
  let resources: [ProcessResource]
  let listsPorts: Bool
  let summary: ScanSummary
  let isInspecting: Bool
  let isVisible: (ProcessResource) -> Bool
  @Binding var order: ResourceOrder
  @Binding var selection: String?
  let actions: (ProcessResource) -> [ExplorerRowAction]
  @State private var sortedResources = SortedRowCache<ProcessResource, ResourceOrder>()
  var body: some View {
    let rows = sortedResources.rows(resources, orderedBy: order).filter(isVisible)
    NativeExplorerTable(
      rows: rows,
      columns: [
        ExplorerColumn(
          title: String(localized: "Process"), width: 150, value: \.processName, sortedBy: ResourceSort.process),
        ExplorerColumn(
          title: String(localized: "PID"), width: 60, value: { String($0.owner.pid) }, monospaced: true,
          sortedBy: ResourceSort.pid),
        ExplorerColumn(
          title: listsPorts ? String(localized: "Local Endpoint") : String(localized: "Resource"), width: 280, value: \.location,
          sortedBy: ResourceSort.location),
        ExplorerColumn(
          title: String(localized: "Type"), width: 96, value: { $0.kind.title }, sortedBy: ResourceSort.kind),
        ExplorerColumn(title: String(localized: "State"), width: 110, value: \.displayState, sortedBy: ResourceSort.state),
      ], selection: $selection, sortDescriptors: $order.descriptors, actions: actions
    )
    .overlay {
      if rows.isEmpty {
        if isInspecting {
          ProgressView(String(localized: "Inspecting accessible processes…"))
        } else {
          EmptyState(
            symbol: listsPorts ? "network" : "doc.text.magnifyingglass",
            title: summary.failed ? String(localized: "Resource query unavailable") : String(localized: "No matching resources"),
            detail: summary.explanation
              ?? String(localized: "Refresh to inspect accessible processes, or change your search."))
        }
      }
    }
  }
}
