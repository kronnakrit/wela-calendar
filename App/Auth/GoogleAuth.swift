import AppAuth
import WelaCore
import WelaSync

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Google sign-in through AppAuth: authorization code + PKCE in the system browser.
/// The refresh token (inside the archived `OIDAuthState`) lives only in the Keychain.
final class GoogleAuth: AccessTokenProvider, @unchecked Sendable {
  static let idPrefix = "google:"
  static let scopes = [
    "openid", "email", "profile",
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
  ]

  private let clientId: String
  private let redirectScheme: String
  private let configuration = OIDServiceConfiguration(
    authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
    tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
  private let lock = NSLock()
  private var states: [String: OIDAuthState] = [:]
  /// Held so the redirect URL can be handed back (see `resume`).
  private var currentSession: OIDExternalUserAgentSession?

  init(clientId: String, redirectScheme: String) {
    self.clientId = clientId
    self.redirectScheme = redirectScheme
  }

  /// Called from `application(_:open:)` when the redirect URL arrives.
  @discardableResult
  func resume(with url: URL) -> Bool {
    lock.lock()
    let session = currentSession
    lock.unlock()
    return session?.resumeExternalUserAgentFlow(with: url) ?? false
  }

  @MainActor
  func signIn() async throws -> Account {
    let presenter = AuthPresenter()
    let request = OIDAuthorizationRequest(
      configuration: configuration, clientId: clientId, clientSecret: nil, scopes: Self.scopes,
      redirectURL: URL(string: "\(redirectScheme):/oauthredirect")!,
      responseType: OIDResponseTypeCode, additionalParameters: nil)  // PKCE is added automatically
    presenter.present()
    defer { presenter.dismiss() }
    let state: OIDAuthState = try await withCheckedThrowingContinuation { cont in
      let session = OIDAuthState.authState(byPresenting: request, presenting: presenter.anchor) {
        state, error in
        if let state {
          cont.resume(returning: state)
        } else {
          cont.resume(throwing: error ?? AuthError.cancelled)
        }
      }
      lock.lock()
      currentSession = session
      lock.unlock()
    }
    let claims = state.lastTokenResponse?.idToken.flatMap { OIDIDToken(idTokenString: $0) }
    let email = (state.lastTokenResponse?.idToken.flatMap(Self.claims)?["email"] as? String) ?? ""
    let subject = claims?.subject ?? email
    let account = Account(
      id: Self.idPrefix + subject, provider: .google, email: email,
      displayName: (state.lastTokenResponse?.idToken.flatMap(Self.claims)?["name"] as? String)
        ?? email)
    store(state, for: account.id)
    return account
  }

  func accessToken(for account: Account) async throws -> String {
    guard let state = authState(for: account.id) else { throw SyncError.needsSignIn }
    return try await withCheckedThrowingContinuation { cont in
      state.performAction { token, _, error in
        if let token {
          self.store(state, for: account.id)  // persist refreshed tokens
          cont.resume(returning: token)
        } else if let error = error as NSError?, error.domain == OIDOAuthTokenErrorDomain {
          cont.resume(throwing: SyncError.needsSignIn)  // e.g. invalid_grant: token revoked
        } else {
          cont.resume(throwing: mapTokenError(error))
        }
      }
    }
  }

  func signOut(_ account: Account) {
    lock.lock()
    states[account.id] = nil
    lock.unlock()
    Keychain.delete(account: account.id)
  }

  // MARK: Persistence

  private func store(_ state: OIDAuthState, for id: String) {
    lock.lock()
    states[id] = state
    lock.unlock()
    if let data = try? NSKeyedArchiver.archivedData(
      withRootObject: state, requiringSecureCoding: true)
    {
      Keychain.save(data, account: id)
    }
  }

  private func authState(for id: String) -> OIDAuthState? {
    lock.lock()
    defer { lock.unlock() }
    if let cached = states[id] { return cached }
    guard let data = Keychain.load(account: id),
      let state = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
    else { return nil }
    states[id] = state
    return state
  }

  /// Decodes the (unverified) payload of an ID token; only used to show the user's own email.
  private static func claims(_ jwt: String) -> [String: Any]? {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
}
