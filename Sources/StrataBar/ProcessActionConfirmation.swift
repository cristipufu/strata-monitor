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
  var title: String {
    switch self {
    case .signal(let action): action.signal.title
    case .applicationQuit: "Quit"
    }
  }
  var explanation: String {
    switch self {
    case .signal(let action): action.signal.explanation
    case .applicationQuit:
      "Ask the application to quit normally. It can show a save prompt or decline. Strata Monitor will not escalate this request."
    }
  }
}
