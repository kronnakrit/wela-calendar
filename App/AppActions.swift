import WelaCore
import WelaSync

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Bridges the UI protocols to the sync engine, sign-in and the system (opening join links).
final class AppActions: EventActions, AccountActions {
  private let store: Store
  private let engine: SyncEngine
  var onAccountAdded: (@MainActor () -> Void)?
  private let microsoft: MicrosoftAuth?
  private let google: GoogleAuth?

  init(store: Store, engine: SyncEngine, microsoft: MicrosoftAuth?, google: GoogleAuth?) {
    self.store = store
    self.engine = engine
    self.microsoft = microsoft
    self.google = google
  }

  func join(_ event: EventInstance) {
    guard let url = event.joinURL, url.scheme?.lowercased() == "https" else { return }
    // Provider-supplied links are untrusted: only https and the app schemes we build ourselves.
    let candidates = JoinURLResolver.candidates(for: url, kind: event.conferenceKind).filter {
      let scheme = $0.scheme?.lowercased()
      return scheme == "https" || scheme == "msteams" || scheme == "zoommtg"
    }
    // Native app first (msteams:, zoommtg:), falling back to the https link.
    #if os(macOS)
      for candidate in candidates {
        if candidate.scheme?.lowercased() == "https"
          || NSWorkspace.shared.urlForApplication(toOpen: candidate) != nil
        {
          NSWorkspace.shared.open(candidate)
          return
        }
      }
    #else
      Task { @MainActor in
        // canOpenURL only answers for schemes listed in LSApplicationQueriesSchemes.
        for candidate in candidates {
          if candidate.scheme?.lowercased() == "https"
            || UIApplication.shared.canOpenURL(candidate)
          {
            _ = await UIApplication.shared.open(candidate)
            return
          }
        }
      }
    #endif
  }

  func respond(to event: EventInstance, with response: ResponseStatus) async throws {
    try await engine.respond(to: event, with: response)
  }

  func refresh() async { await engine.syncAll() }

  func addAccount(provider: ProviderKind) async throws {
    let account: Account
    switch provider {
    case .microsoft:
      guard let microsoft else {
        throw AuthError.notConfigured("The Microsoft client ID (MS_CLIENT_ID)")
      }
      account = try await microsoft.signIn()
    case .google:
      guard let google else {
        throw AuthError.notConfigured("The Google client ID (GOOGLE_CLIENT_ID)")
      }
      account = try await google.signIn()
    case .mock:
      return
    }
    try store.saveAccount(account)
    await MainActor.run { onAccountAdded?() }
    await engine.sync(account: account)
  }

  func reconnect(_ account: Account) async throws {
    try await addAccount(provider: account.provider)
  }

  /// Deletes the account's cached data and its tokens.
  func removeAccount(_ account: Account) async throws {
    microsoft?.signOut(account)
    google?.signOut(account)
    try store.deleteAccount(id: account.id)
  }
}
