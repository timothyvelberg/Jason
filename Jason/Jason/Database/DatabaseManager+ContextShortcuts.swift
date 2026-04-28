//
//  DatabaseManager+ContextShortcuts.swift
//  Jason
//

import Foundation
import SQLite3
import AppKit

private let SQLITE_TRANSIENT_CS = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DatabaseManager {

    // MARK: - Context Apps: Insert

    func insertContextApp(bundleId: String, displayName: String, sortOrder: Int) -> Bool {
        var success = false
        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            INSERT OR IGNORE INTO context_apps (bundle_id, display_name, sort_order)
            VALUES (?, ?, ?);
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, bundleId, -1, SQLITE_TRANSIENT_CS)
                sqlite3_bind_text(statement, 2, displayName, -1, SQLITE_TRANSIENT_CS)
                sqlite3_bind_int(statement, 3, Int32(sortOrder))

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Inserted context app: '\(displayName)' (\(bundleId))")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert context app: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        return success
    }

    // MARK: - Context Apps: Fetch All

    func fetchAllContextApps() -> [ContextApp] {
        var results: [ContextApp] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT id, bundle_id, display_name, sort_order
            FROM context_apps
            ORDER BY sort_order ASC;
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = sqlite3_column_int64(statement, 0)
                    guard let bundleIdCString = sqlite3_column_text(statement, 1),
                          let displayNameCString = sqlite3_column_text(statement, 2) else { continue }
                    let bundleId = String(cString: bundleIdCString)
                    let displayName = String(cString: displayNameCString)
                    let sortOrder = Int(sqlite3_column_int(statement, 3))
                    results.append(ContextApp(id: id, bundleId: bundleId, displayName: displayName, sortOrder: sortOrder))
                }
            }
            sqlite3_finalize(statement)
        }

        print("🎯 [DatabaseManager] Fetched \(results.count) context app(s)")
        return results
    }

    // MARK: - Context Apps: Delete

    func deleteContextApp(bundleId: String) {
        queue.async {
            guard let db = self.db else { return }

            let sql = "DELETE FROM context_apps WHERE bundle_id = ?;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, bundleId, -1, SQLITE_TRANSIENT_CS)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted context app: \(bundleId) (and all its shortcuts via CASCADE)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete context app: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Apps: Batch Sort Order Update

    func updateContextAppSortOrders(_ updates: [(id: Int64, sortOrder: Int)]) {
        queue.async {
            guard let db = self.db else { return }

            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

            let sql = "UPDATE context_apps SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            var allSucceeded = true

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for update in updates {
                    sqlite3_bind_int(statement, 1, Int32(update.sortOrder))
                    sqlite3_bind_int64(statement, 2, update.id)

                    if sqlite3_step(statement) != SQLITE_DONE {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to update sort order for app id:\(update.id): \(String(cString: error))")
                        }
                        allSucceeded = false
                    }
                    sqlite3_reset(statement)
                }
            }
            sqlite3_finalize(statement)

            if allSucceeded {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                print("✅ [DatabaseManager] Updated sort orders for \(updates.count) context app(s)")
            } else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                print("❌ [DatabaseManager] App sort order update rolled back due to errors")
            }
        }
    }

    // MARK: - Context Shortcut Groups: Insert

    func insertContextShortcutGroup(ringId: Int, name: String, iconName: String?, sortOrder: Int) -> Int64? {
        var insertedId: Int64? = nil
        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            INSERT INTO context_shortcut_groups (ring_id, name, icon_name, sort_order)
            VALUES (?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))
                sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT_CS)

                if let iconName = iconName {
                    sqlite3_bind_text(statement, 3, iconName, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 3)
                }

                sqlite3_bind_int(statement, 4, Int32(sortOrder))

                if sqlite3_step(statement) == SQLITE_DONE {
                    insertedId = sqlite3_last_insert_rowid(db)
                    print("✅ [DatabaseManager] Inserted context shortcut group: '\(name)' for ring \(ringId) (id: \(insertedId!))")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert context shortcut group: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        return insertedId
    }

    // MARK: - Context Shortcut Groups: Fetch by Ring ID

    func fetchContextShortcutGroups(for ringId: Int) -> [ContextShortcutGroup] {
        var results: [ContextShortcutGroup] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT id, ring_id, name, icon_name, sort_order
            FROM context_shortcut_groups
            WHERE ring_id = ?
            ORDER BY sort_order ASC;
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let group = contextShortcutGroupFromStatement(statement) {
                        results.append(group)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        print("🎯 [DatabaseManager] Fetched \(results.count) context shortcut group(s) for ring \(ringId)")
        return results
    }

    // MARK: - Context Shortcut Groups: Update

    func updateContextShortcutGroup(_ group: ContextShortcutGroup) {
        queue.async {
            guard let db = self.db else { return }

            let sql = """
            UPDATE context_shortcut_groups
            SET name = ?, icon_name = ?, sort_order = ?
            WHERE id = ?;
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, group.name, -1, SQLITE_TRANSIENT_CS)

                if let iconName = group.iconName {
                    sqlite3_bind_text(statement, 2, iconName, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 2)
                }

                sqlite3_bind_int(statement, 3, Int32(group.sortOrder))
                sqlite3_bind_int64(statement, 4, group.id)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated context shortcut group id:\(group.id) '\(group.name)'")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update context shortcut group: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcut Groups: Delete

    func deleteContextShortcutGroup(id: Int64) {
        queue.async {
            guard let db = self.db else { return }

            // ON DELETE SET NULL means shortcuts in this group become ungrouped automatically
            let sql = "DELETE FROM context_shortcut_groups WHERE id = ?;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, id)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted context shortcut group id:\(id) (shortcuts moved to ungrouped)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete context shortcut group: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcut Groups: Batch Sort Order Update

    func updateContextShortcutGroupSortOrders(_ updates: [(id: Int64, sortOrder: Int)]) {
        queue.async {
            guard let db = self.db else { return }

            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

            let sql = "UPDATE context_shortcut_groups SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            var allSucceeded = true

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for update in updates {
                    sqlite3_bind_int(statement, 1, Int32(update.sortOrder))
                    sqlite3_bind_int64(statement, 2, update.id)

                    if sqlite3_step(statement) != SQLITE_DONE {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to update sort order for group id:\(update.id): \(String(cString: error))")
                        }
                        allSucceeded = false
                    }
                    sqlite3_reset(statement)
                }
            }
            sqlite3_finalize(statement)

            if allSucceeded {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                print("✅ [DatabaseManager] Updated sort orders for \(updates.count) context shortcut group(s)")
            } else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                print("❌ [DatabaseManager] Group sort order update rolled back due to errors")
            }
        }
    }

    // MARK: - Context Shortcuts: Insert

    func insertContextShortcut(_ shortcut: ContextShortcut) {
        queue.async {
            guard let db = self.db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }

            let sql = """
            INSERT INTO context_shortcuts
                (ring_id, shortcut_name, description, icon_name, shortcut_type, key_code, modifier_flags, menu_path, enabled, sort_order, group_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(shortcut.ringId))
                sqlite3_bind_text(statement, 2, shortcut.shortcutName, -1, SQLITE_TRANSIENT_CS)

                if let description = shortcut.description {
                    sqlite3_bind_text(statement, 3, description, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 3)
                }

                if let iconName = shortcut.iconName {
                    sqlite3_bind_text(statement, 4, iconName, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 4)
                }

                sqlite3_bind_text(statement, 5, shortcut.shortcutType.rawValue, -1, SQLITE_TRANSIENT_CS)

                if let keyCode = shortcut.keyCode {
                    sqlite3_bind_int(statement, 6, Int32(keyCode))
                } else {
                    sqlite3_bind_null(statement, 6)
                }

                if let modifierFlags = shortcut.modifierFlags {
                    sqlite3_bind_int64(statement, 7, Int64(modifierFlags))
                } else {
                    sqlite3_bind_null(statement, 7)
                }

                if let menuPath = shortcut.menuPath {
                    sqlite3_bind_text(statement, 8, menuPath, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 8)
                }

                sqlite3_bind_int(statement, 9, shortcut.enabled ? 1 : 0)
                sqlite3_bind_int(statement, 10, Int32(shortcut.sortOrder))

                if let groupId = shortcut.groupId {
                    sqlite3_bind_int64(statement, 11, groupId)
                } else {
                    sqlite3_bind_null(statement, 11)
                }

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Inserted context shortcut: '\(shortcut.shortcutName)' for ring \(shortcut.ringId)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert context shortcut: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcuts: Fetch by Ring ID

    func fetchContextShortcuts(for ringId: Int) -> [ContextShortcut] {
        var results: [ContextShortcut] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT id, ring_id, shortcut_name, description, icon_name, shortcut_type, key_code, modifier_flags, menu_path, enabled, sort_order, group_id
            FROM context_shortcuts
            WHERE ring_id = ?
            ORDER BY sort_order ASC;
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let shortcut = contextShortcutFromStatement(statement) {
                        results.append(shortcut)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        print("🎯 [DatabaseManager] Fetched \(results.count) context shortcut(s) for ring \(ringId)")
        return results
    }

    // MARK: - Context Shortcuts: Fetch All for App (join)

    func fetchContextShortcutsForApp(bundleId: String) -> [ContextShortcut] {
        var results: [ContextShortcut] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT cs.id, cs.ring_id, cs.shortcut_name, cs.description, cs.icon_name,
                   cs.shortcut_type, cs.key_code, cs.modifier_flags, cs.menu_path, cs.enabled, cs.sort_order, cs.group_id
            FROM context_shortcuts cs
            JOIN ring_configurations rc ON cs.ring_id = rc.id
            WHERE rc.bundle_id = ?
            ORDER BY cs.ring_id ASC, cs.sort_order ASC;
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, bundleId, -1, SQLITE_TRANSIENT_CS)

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let shortcut = contextShortcutFromStatement(statement) {
                        results.append(shortcut)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        print("🎯 [DatabaseManager] Fetched \(results.count) context shortcut(s) for app \(bundleId)")
        return results
    }

    // MARK: - Context Shortcuts: Update

    func updateContextShortcut(_ shortcut: ContextShortcut) {
        queue.async {
            guard let db = self.db else { return }

            let sql = """
            UPDATE context_shortcuts
            SET shortcut_name = ?, description = ?, icon_name = ?, shortcut_type = ?, key_code = ?, modifier_flags = ?, menu_path = ?, enabled = ?, sort_order = ?, group_id = ?
            WHERE id = ?;
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, shortcut.shortcutName, -1, SQLITE_TRANSIENT_CS)

                if let description = shortcut.description {
                    sqlite3_bind_text(statement, 2, description, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 2)
                }

                if let iconName = shortcut.iconName {
                    sqlite3_bind_text(statement, 3, iconName, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 3)
                }

                sqlite3_bind_text(statement, 4, shortcut.shortcutType.rawValue, -1, SQLITE_TRANSIENT_CS)

                if let keyCode = shortcut.keyCode {
                    sqlite3_bind_int(statement, 5, Int32(keyCode))
                } else {
                    sqlite3_bind_null(statement, 5)
                }

                if let modifierFlags = shortcut.modifierFlags {
                    sqlite3_bind_int64(statement, 6, Int64(modifierFlags))
                } else {
                    sqlite3_bind_null(statement, 6)
                }

                if let menuPath = shortcut.menuPath {
                    sqlite3_bind_text(statement, 7, menuPath, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 7)
                }

                sqlite3_bind_int(statement, 8, shortcut.enabled ? 1 : 0)
                sqlite3_bind_int(statement, 9, Int32(shortcut.sortOrder))

                if let groupId = shortcut.groupId {
                    sqlite3_bind_int64(statement, 10, groupId)
                } else {
                    sqlite3_bind_null(statement, 10)
                }

                sqlite3_bind_int64(statement, 11, shortcut.id)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated context shortcut id:\(shortcut.id) '\(shortcut.shortcutName)'")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update context shortcut: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcuts: Delete

    func deleteContextShortcut(id: Int64) {
        queue.async {
            guard let db = self.db else { return }

            let sql = "DELETE FROM context_shortcuts WHERE id = ?;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, id)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted context shortcut id:\(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete context shortcut: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcuts: Batch Sort Order Update

    func updateContextShortcutSortOrders(_ updates: [(id: Int64, sortOrder: Int)]) {
        queue.async {
            guard let db = self.db else { return }

            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

            let sql = "UPDATE context_shortcuts SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            var allSucceeded = true

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                for update in updates {
                    sqlite3_bind_int(statement, 1, Int32(update.sortOrder))
                    sqlite3_bind_int64(statement, 2, update.id)

                    if sqlite3_step(statement) != SQLITE_DONE {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to update sort order for id:\(update.id): \(String(cString: error))")
                        }
                        allSucceeded = false
                    }
                    sqlite3_reset(statement)
                }
            }
            sqlite3_finalize(statement)

            if allSucceeded {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                print("✅ [DatabaseManager] Updated sort orders for \(updates.count) context shortcut(s)")
            } else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                print("❌ [DatabaseManager] Sort order update rolled back due to errors")
            }
        }
    }

    // MARK: - Private Helpers

    private func contextShortcutFromStatement(_ statement: OpaquePointer?) -> ContextShortcut? {
        guard let statement = statement else { return nil }

        let id = sqlite3_column_int64(statement, 0)
        let ringId = Int(sqlite3_column_int(statement, 1))

        guard let shortcutNameCString = sqlite3_column_text(statement, 2) else { return nil }
        let shortcutName = String(cString: shortcutNameCString)

        var description: String? = nil
        if let descCString = sqlite3_column_text(statement, 3) {
            description = String(cString: descCString)
        }

        var iconName: String? = nil
        if let iconCString = sqlite3_column_text(statement, 4) {
            iconName = String(cString: iconCString)
        }

        let shortcutType: ShortcutType
        if let typeCString = sqlite3_column_text(statement, 5) {
            shortcutType = ShortcutType(rawValue: String(cString: typeCString)) ?? .keyboard
        } else {
            shortcutType = .keyboard
        }

        let keyCode: UInt16? = sqlite3_column_type(statement, 6) != SQLITE_NULL
            ? UInt16(sqlite3_column_int(statement, 6)) : nil

        let modifierFlags: UInt? = sqlite3_column_type(statement, 7) != SQLITE_NULL
            ? UInt(sqlite3_column_int64(statement, 7)) : nil

        var menuPath: String? = nil
        if let pathCString = sqlite3_column_text(statement, 8) {
            menuPath = String(cString: pathCString)
        }

        let enabled = sqlite3_column_int(statement, 9) != 0
        let sortOrder = Int(sqlite3_column_int(statement, 10))

        var groupId: Int64? = nil
        if sqlite3_column_type(statement, 11) != SQLITE_NULL {
            groupId = sqlite3_column_int64(statement, 11)
        }

        return ContextShortcut(
            id: id,
            ringId: ringId,
            shortcutName: shortcutName,
            description: description,
            iconName: iconName,
            shortcutType: shortcutType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            menuPath: menuPath,
            enabled: enabled,
            sortOrder: sortOrder,
            groupId: groupId
        )
    }

    private func contextShortcutGroupFromStatement(_ statement: OpaquePointer?) -> ContextShortcutGroup? {
        guard let statement = statement else { return nil }

        let id = sqlite3_column_int64(statement, 0)
        let ringId = Int(sqlite3_column_int(statement, 1))

        guard let nameCString = sqlite3_column_text(statement, 2) else { return nil }
        let name = String(cString: nameCString)

        var iconName: String? = nil
        if let iconCString = sqlite3_column_text(statement, 3) {
            iconName = String(cString: iconCString)
        }

        let sortOrder = Int(sqlite3_column_int(statement, 4))

        return ContextShortcutGroup(
            id: id,
            ringId: ringId,
            name: name,
            iconName: iconName,
            sortOrder: sortOrder
        )
    }
}
