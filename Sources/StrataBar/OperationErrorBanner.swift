import SwiftUI

struct OperationErrorBanner: View {
  let message: String
  let dismiss: () -> Void
  var body: some View {
    HStack(spacing: Design.Spacing.small) {
      Image(systemName: "exclamationmark.circle").foregroundStyle(Design.orange)
      Text(verbatim: message).font(Design.Typography.secondary).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button(action: dismiss) { Image(systemName: "xmark").font(Design.Typography.footnote) }
        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
    }.padding(Design.Spacing.medium)
      .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Design.Radius.banner))
      .accessibilityElement(children: .contain)
  }
}
