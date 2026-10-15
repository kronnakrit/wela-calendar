import Foundation

/// Implemented by WelaSync, injected into WelaUI by the app target.
public protocol EventActions: AnyObject {
  func join(_ event: EventInstance)
  func respond(to event: EventInstance, with response: ResponseStatus) async throws
  func refresh() async
}

public protocol AccountActions: AnyObject {
  func addAccount(provider: ProviderKind) async throws
  func removeAccount(_ account: Account) async throws
  func reconnect(_ account: Account) async throws
}
