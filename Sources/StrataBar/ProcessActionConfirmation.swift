import Foundation
import StrataCore

enum ProcessActionConfirmation {
  case signal(PreparedProcessAction)
  case applicationQuit(PreparedApplicationQuit)
  var name: String {
    switch self {
    case .signal(let action): action.name
    case .applicationQuit(let action): action.name
    }
  }
  var identity: ProcessIdentity {
    switch self {
    case .signal(let action): action.identity
    case .applicationQuit(let action): action.identity
    }
  }
  var count: Int {
    switch self {
    case .signal(let action): action.identities.count
    case .applicationQuit: 1
    }
  }
  var title: String {
    switch self {
    case .signal(let action): action.signal.title
    case .applicationQuit: String(localized: "Quit")
    }
  }
  var explanation: String {
    switch self {
    case .signal(let action): action.signal.explanation
    case .applicationQuit:
      String(localized: "Ask the application to quit normally. It can show a save prompt or decline. Strata Monitor will not escalate this request.")
    }
  }
}
