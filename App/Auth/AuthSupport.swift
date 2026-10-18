import AppKit
import Security
import WelaCore
import WelaSync

enum AuthError: LocalizedError {
  case notConfigured(String)
  case cancelled
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured(let what): return "\(what) is not configured. Add it to Config/Secrets.xcconfig."
    case .cancelled: return "Sign-in was cancelled."
    case .failed(let message): return message
    }
  }
}

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
