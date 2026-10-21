import Security
import WelaCore
import WelaSync

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum AuthError: LocalizedError {
  case notConfigured(String)
  case cancelled
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured(let what):
      return "\(what) is not configured. Add it to Config/Secrets.xcconfig."
    case .cancelled: return "Sign-in was cancelled."
    case .failed(let message): return message
    }
  }
}

#if os(macOS)
  /// Browser-based sign-in needs a window to anchor to, but Wela is a menu bar app with none.
  /// This shows a tiny invisible window for the duration of a sign-in.
  @MainActor
  final class AuthPresenter {
    private var window: NSWindow?
    let viewController = NSViewController()

    init() {
      viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    var anchor: NSWindow {
      if let window { return window }
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless],
        backing: .buffered, defer: false)
      w.contentViewController = viewController
      w.alphaValue = 0
      w.isReleasedWhenClosed = false
      w.center()
      window = w
      return w
    }

    func present() {
      NSApp.activate(ignoringOtherApps: true)
      anchor.orderFrontRegardless()
    }

    func dismiss() {
      window?.orderOut(nil)
      window = nil
    }
  }
#else
  /// On iOS the sign-in sheet is presented from the frontmost view controller.
  @MainActor
  final class AuthPresenter {
    var viewController: UIViewController {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window =
        scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
      var top = window?.rootViewController ?? UIViewController()
      while let presented = top.presentedViewController { top = presented }
      return top
    }

    var anchor: UIViewController { viewController }

    func present() {}
    func dismiss() {}
  }
#endif

/// Minimal Keychain wrapper for refresh-token blobs (never written to disk elsewhere).
enum Keychain {
  static let service = "app.wela.tokens"

  static func save(_ data: Data, account: String) {
    delete(account: account)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  static func load(account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
    return item as? Data
  }

  static func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

/// Routes token requests to the right provider's auth.
struct CompositeTokenProvider: AccessTokenProvider {
  let microsoft: AccessTokenProvider?
  let google: AccessTokenProvider?

  func accessToken(for account: Account) async throws -> String {
    switch account.provider {
    case .microsoft:
      guard let microsoft else { throw SyncError.needsSignIn }
      return try await microsoft.accessToken(for: account)
    case .google:
      guard let google else { throw SyncError.needsSignIn }
      return try await google.accessToken(for: account)
    case .mock:
      throw SyncError.needsSignIn
    }
  }
}

/// Token refresh failures that are really "no network" must surface as `SyncError.offline` so the
/// sync engine keeps cached data and queued RSVPs instead of reporting an account error.
func mapTokenError(_ error: Error?) -> Error {
  guard let error else { return SyncError.needsSignIn }
  var current: NSError? = error as NSError
  while let e = current {
    if e.domain == NSURLErrorDomain { return SyncError.offline }
    current = e.userInfo[NSUnderlyingErrorKey] as? NSError
  }
  return error
}
