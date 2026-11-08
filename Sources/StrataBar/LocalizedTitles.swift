import Foundation
import StrataCore

extension Accent {
  var title: String {
    switch self {
    case .automatic: String(localized: "Automatic")
    case .monochrome: String(localized: "Monochrome")
    case .blue: String(localized: "Blue")
    case .mint: String(localized: "Mint")
    case .teal: String(localized: "Teal")
    case .violet: String(localized: "Violet")
    case .pink: String(localized: "Pink")
    case .orange: String(localized: "Orange")
    case .red: String(localized: "Red")
    }
  }
}

extension FillStyle {
  var title: String {
    switch self {
    case .continuous: String(localized: "Continuous")
    case .segmented: String(localized: "Segmented")
    case .gradient: String(localized: "Gradient")
    }
  }
}

extension FillMotion {
  var title: String {
    switch self {
    case .grow: String(localized: "Grow")
    case .snap: String(localized: "Snap")
    }
  }
}

extension UnfoldStyle {
  var title: String {
    switch self {
    case .morph: String(localized: "Morph")
    case .fade: String(localized: "Fade")
    }
  }
}

extension Appearance {
  var title: String {
    switch self {
    case .system: String(localized: "System")
    case .light: String(localized: "Light")
    case .dark: String(localized: "Dark")
    }
  }
}

extension SigningKind {
  var title: String {
    switch self {
    case .apple: String(localized: "Apple-signed")
    case .signed: String(localized: "Signed")
    case .adHoc: String(localized: "Ad hoc")
    case .unsigned: String(localized: "Unsigned")
    case .invalid: String(localized: "Invalid signature")
    case .unavailable: String(localized: "Unavailable")
    }
  }
}

extension MemoryPressure {
  var title: String {
    switch self {
    case .normal: String(localized: "normal")
    case .elevated: String(localized: "elevated")
    case .critical: String(localized: "critical")
    case .unavailable: String(localized: "Unavailable")
    }
  }
}

extension SystemSample.ThermalPressure {
  var title: String {
    switch self {
    case .normal: String(localized: "Normal")
    case .elevated: String(localized: "Elevated")
    case .high: String(localized: "High")
    case .critical: String(localized: "Critical")
    case .unavailable: String(localized: "Unavailable")
    }
  }
}

extension ExplorerSection {
  var title: String {
    switch self {
    case .processes: String(localized: "Processes")
    case .ports: String(localized: "Ports")
    case .files: String(localized: "Open resources")
    case .timeline: String(localized: "Timeline")
    case .cpu: String(localized: "CPU")
    case .gpu: String(localized: "GPU")
    case .memory: String(localized: "Memory")
    case .disk: String(localized: "Volumes")
    case .network: String(localized: "Network")
    }
  }
}

extension ProcessResource {
  var displayState: String {
    switch state {
    case "Bound datagram": String(localized: "Bound datagram")
    case "Connected datagram": String(localized: "Connected datagram")
    case "Listening": String(localized: "Listening")
    case "Connecting": String(localized: "Connecting")
    case "Established": String(localized: "Established")
    case "Closing": String(localized: "Closing")
    case "Closed": String(localized: "Closed")
    default: state
    }
  }
}
