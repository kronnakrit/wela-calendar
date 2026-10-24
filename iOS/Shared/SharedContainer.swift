import Foundation

/// What the iOS app and its widget extension share through the App Group container: the
/// SQLite cache and the settings.
enum SharedContainer {
  /// Set in Debug when the app runs with `-UseMockData`, so widgets read the demo database.
  static let demoStoreKey = "wela.useDemoStore"

  /// From Info.plist (`WELA_APP_GROUP` in the xcconfig).
  static var appGroup: String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "WelaAppGroup") as? String,
      !value.isEmpty
    else { return nil }
    return value
  }

  static var defaults: UserDefaults {
    appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard
  }

  static var usesDemoStore: Bool {
    get { defaults.bool(forKey: demoStoreKey) }
    set { defaults.set(newValue, forKey: demoStoreKey) }
  }

  /// The group container, or the app's own Application Support folder when the App Group isn't
  /// available (an unsigned build). Widgets then show the sign-in prompt.
  static func directory() throws -> URL {
    let fm = FileManager.default
    let base: URL
    if let group = appGroup, let url = fm.containerURL(forSecurityApplicationGroupIdentifier: group)
    {
      base = url
    } else {
      base = try fm.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    let dir = base.appendingPathComponent("Wela", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func storeURL(demo: Bool) throws -> URL {
    try directory().appendingPathComponent(demo ? "wela-demo.sqlite" : "wela.sqlite")
  }
}
