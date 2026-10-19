import Foundation
import GRDB

extension ProviderKind: DatabaseValueConvertible {}
extension ResponseStatus: DatabaseValueConvertible {}
extension EventStatus: DatabaseValueConvertible {}
extension ConferenceKind: DatabaseValueConvertible {}

extension Account: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "account" }
}

extension CalendarInfo: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "calendar" }
}

extension EventInstance: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "event_instance" }
}

extension SyncState: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "sync_state" }
}

extension OutboxItem: FetchableRecord, MutablePersistableRecord {
  public static var databaseTableName: String { "outbox" }

  public mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
