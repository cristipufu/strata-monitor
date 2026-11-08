import StrataCore
import SwiftUI

struct ProcessBrowser: View {
  enum Content {
    case processes([ProcessSample])
    case families(ProcessTreeSnapshot)
  }
  let content: Content
  let scan: ScanSummary?
  let query: String
  @Binding var order: ProcessOrder
  @Binding var selection: ProcessIdentity?
  let actions: (ProcessSample) -> [ExplorerRowAction]
  var body: some View {
    switch content {
    case .processes(let rows): processTable(rows)
    case .families(let snapshot): familyOutline(snapshot)
    }
  }
  private func processTable(_ rows: [ProcessSample]) -> some View {
    NativeExplorerTable(
      rows: rows, columns: ProcessColumns.individual(), selection: $selection,
      sortDescriptors: $order.descriptors, actions: actions,
      autosaveName: "StrataBar.Explorer.Processes"
    )
    .overlay {
      if rows.isEmpty {
        emptyState(symbol: "magnifyingglass", noMatches: String(localized: "No matching processes"))
      }
    }
  }
  private func familyOutline(_ snapshot: ProcessTreeSnapshot) -> some View {
    VStack(spacing: 0) {
      NativeProcessOutline(
        snapshot: snapshot, columns: ProcessColumns.families(), selection: $selection,
        sortDescriptors: $order.descriptors, actions: actions,
        autosaveName: "StrataBar.Explorer.Families"
      )
      .overlay {
        if snapshot.rows.isEmpty {
          emptyState(symbol: "square.stack.3d.up", noMatches: String(localized: "No matching families"))
        }
      }
      Text(
        "Root rows show family totals; children show individual readings. ≥ marks a measured subtotal. Search retains ancestors and full family totals."
      )
      .footnoteStyle().padding(.horizontal, Design.Spacing.medium)
      .padding(.vertical, Design.Spacing.small).frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
    }
  }
  private func emptyState(symbol: String, noMatches: String) -> some View {
    EmptyState(
      symbol: symbol,
      title: scan == nil
        ? String(localized: "Reading processes…") : scan?.failed == true ? String(localized: "Process query unavailable") : noMatches,
      detail: scan?.explanation
        ?? (query.isEmpty
          ? String(localized: "Live measurements will appear shortly.")
          : String(localized: "Try a name, executable path, PID, or uid:501.")))
  }
}
