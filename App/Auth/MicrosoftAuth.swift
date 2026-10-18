import AppKit
import MSAL
import WelaCore
import WelaSync

/// Microsoft sign-in through MSAL, using the system browser sheet (no embedded web view).
final class MicrosoftAuth: AccessTokenProvider, @unchecked Sendable {
  static let scopes = ["User.Read", "Calendars.ReadWrite"]  // offline_access is implicit
  static let idPrefix = "microsoft:"

  private let app: MSALPublicClientApplication

  init(clientId: String) throws {
    let config = MSALPublicClientApplicationConfig(clientId: clientId)
    config.authority = try MSALAADAuthority(
      url: URL(string: "https://login.microsoftonline.com/common")!)
    app = try MSALPublicClientApplication(configuration: config)
  }

  /// Interactive sign-in. Returns the account to store.
  @MainActor
  func signIn() async throws -> Account {
    let presenter = AuthPresenter()
    let web = MSALWebviewParameters(authPresentationViewController: presenter.viewController)
    web.webviewType = .authenticationSession
    let params = MSALInteractiveTokenParameters(scopes: Self.scopes, webviewParameters: web)
    params.promptType = .selectAccount
    presenter.present()
    defer { presenter.dismiss() }
    let result: MSALResult = try await withCheckedThrowingContinuation { cont in
      app.acquireToken(with: params) { result, error in
        if let result {
          cont.resume(returning: result)
        } else {
          cont.resume(throwing: error ?? AuthError.cancelled)
        }
      }
    }
    let name = result.account.accountClaims?["name"] as? String
    return Account(
      id: Self.idPrefix
        + (result.account.identifier ?? result.account.username ?? UUID().uuidString),
      provider: .microsoft, email: result.account.username ?? "",
      displayName: name ?? result.account.username ?? "")
  }

  func accessToken(for account: Account) async throws -> String {
    let identifier = String(account.id.dropFirst(Self.idPrefix.count))
    let msalAccount: MSALAccount
    do {
      msalAccount = try app.account(forIdentifier: identifier)
    } catch {
      throw SyncError.needsSignIn
    }
    let params = MSALSilentTokenParameters(scopes: Self.scopes, account: msalAccount)
    return try await withCheckedThrowingContinuation { cont in
      app.acquireTokenSilent(with: params) { result, error in
        if let token = result?.accessToken {
          cont.resume(returning: token)
        } else if let error = error as NSError?, error.domain == MSALErrorDomain,
          error.code == MSALError.interactionRequired.rawValue
        {
          cont.resume(throwing: SyncError.needsSignIn)
        } else {
          cont.resume(throwing: error ?? SyncError.needsSignIn)
        }
      }
    }
  }

  /// Removes the account's cached tokens (used when the account is removed).
  func signOut(_ account: Account) {
    let identifier = String(account.id.dropFirst(Self.idPrefix.count))
    if let msalAccount = try? app.account(forIdentifier: identifier) {
      try? app.remove(msalAccount)
    }
  }
}
