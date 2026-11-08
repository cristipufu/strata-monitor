import Foundation
import StrataSystem

struct MenuBarInteraction: Equatable {
  let id = UUID()
  let pointerX: CGFloat
  let barBottom: CGFloat
}

@MainActor final class MenuBarMenuSession {
  private let hasMenu: @Sendable (CGFloat, CGFloat) async -> Bool
  private var task: Task<Void, Never>?
  private var id: UUID?
  private static let pollingInterval: Duration = .milliseconds(100)
  private static let openingAttempts = 8

  init(observer: MenuBarMenuObserver = MenuBarMenuObserver()) {
    hasMenu = { pointerX, barBottom in await observer.hasMenu(at: pointerX, below: barBottom) }
  }

  init(hasMenu: @escaping @Sendable (CGFloat, CGFloat) async -> Bool) {
    self.hasMenu = hasMenu
  }

  func observe(
    _ interaction: MenuBarInteraction,
    ended: @escaping @MainActor (UUID) -> Void
  ) {
    guard id != interaction.id else { return }
    stop()
    id = interaction.id
    let hasMenu = hasMenu
    task = Task { [weak self] in
      var opened = false
      for _ in 0..<Self.openingAttempts {
        guard !Task.isCancelled else { return }
        if await hasMenu(interaction.pointerX, interaction.barBottom) {
          opened = true
          break
        }
        do { try await Task.sleep(for: Self.pollingInterval) } catch { return }
      }
      while opened && !Task.isCancelled {
        do { try await Task.sleep(for: Self.pollingInterval) } catch { return }
        opened = await hasMenu(interaction.pointerX, interaction.barBottom)
      }
      guard !Task.isCancelled, self?.id == interaction.id else { return }
      self?.id = nil
      self?.task = nil
      ended(interaction.id)
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    id = nil
  }

  isolated deinit { task?.cancel() }
}
