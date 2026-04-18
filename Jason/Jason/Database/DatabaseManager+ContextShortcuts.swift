//
//  DatabaseManager+ContextShortcuts.swift
//  Jason
//
//  Created by Timothy Velberg on 18/04/2026.
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

    // MARK: - Context Shortcuts: Insert

    func insertContextShortcut(_ shortcut: ContextShortcut) {
        queue.async {
            guard let db = self.db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }

            let sql = """
            INSERT INTO context_shortcuts
                (bundle_id, display_name, shortcut_name, description, key_code, modifier_flags, enabled, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, shortcut.bundleId, -1, SQLITE_TRANSIENT_CS)
                sqlite3_bind_text(statement, 2, shortcut.displayName, -1, SQLITE_TRANSIENT_CS)
                sqlite3_bind_text(statement, 3, shortcut.shortcutName, -1, SQLITE_TRANSIENT_CS)

                if let description = shortcut.description {
                    sqlite3_bind_text(statement, 4, description, -1, SQLITE_TRANSIENT_CS)
                } else {
                    sqlite3_bind_null(statement, 4)
                }

                sqlite3_bind_int(statement, 5, Int32(shortcut.keyCode))
                sqlite3_bind_int64(statement, 6, Int64(shortcut.modifierFlags))
                sqlite3_bind_int(statement, 7, shortcut.enabled ? 1 : 0)
                sqlite3_bind_int(statement, 8, Int32(shortcut.sortOrder))

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Inserted context shortcut: '\(shortcut.shortcutName)' for \(shortcut.bundleId)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert context shortcut: \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Context Shortcuts: Fetch by Bundle ID

    func fetchContextShortcuts(for bundleId: String) -> [ContextShortcut] {
        var results: [ContextShortcut] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT id, bundle_id, display_name, shortcut_name, description, key_code, modifier_flags, enabled, sort_order
            FROM context_shortcuts
            WHERE bundle_id = ?
            ORDER BY sort_order ASC;
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

        print("🎯 [DatabaseManager] Fetched \(results.count) context shortcut(s) for \(bundleId)")
        return results
    }

    // MARK: - Context Shortcuts: Fetch All

    func fetchAllContextShortcuts() -> [ContextShortcut] {
        var results: [ContextShortcut] = []

        queue.sync {
            guard let db = self.db else { return }

            let sql = """
            SELECT id, bundle_id, display_name, shortcut_name, description, key_code, modifier_flags, enabled, sort_order
            FROM context_shortcuts
            ORDER BY bundle_id ASC, sort_order ASC;
            """

            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let shortcut = contextShortcutFromStatement(statement) {
                        results.append(shortcut)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        print("🎯 [DatabaseManager] Fetched \(results.count) total context shortcut(s)")
        return results
    }

    // MARK: - Context Shortcuts: Update

    func updateContextShortcut(_ shortcut: ContextShortcut) {
        queue.async {
            guard let db = self.db else { return }

            let sql = """
            UPDATE context_shortcuts
            SET shortcut_name = ?, description = ?, key_code = ?, modifier_flags = ?, enabled = ?, sort_order = ?
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

                sqlite3_bind_int(statement, 3, Int32(shortcut.keyCode))
                sqlite3_bind_int64(statement, 4, Int64(shortcut.modifierFlags))
                sqlite3_bind_int(statement, 5, shortcut.enabled ? 1 : 0)
                sqlite3_bind_int(statement, 6, Int32(shortcut.sortOrder))
                sqlite3_bind_int64(statement, 7, shortcut.id)

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

    // MARK: - Seeding

    func seedContextShortcutsIfNeeded() {
        queue.sync {
            guard let db = self.db else { return }

            let countSQL = "SELECT COUNT(*) FROM context_apps;"
            var statement: OpaquePointer?
            var count: Int32 = 0

            if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = sqlite3_column_int(statement, 0)
                }
            }
            sqlite3_finalize(statement)

            guard count == 0 else {
                print("🎯 [DatabaseManager] Context data already seeded (\(count) apps) — skipping")
                return
            }

            // Seed apps first
            let apps: [(bundleId: String, displayName: String)] = [
                ("com.apple.finder",    "Finder"),
                ("com.vivaldi.Vivaldi", "Vivaldi"),
            ]

            let appSQL = "INSERT INTO context_apps (bundle_id, display_name, sort_order) VALUES (?, ?, ?);"

            for (index, app) in apps.enumerated() {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, appSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, app.bundleId, -1, SQLITE_TRANSIENT_CS)
                    sqlite3_bind_text(stmt, 2, app.displayName, -1, SQLITE_TRANSIENT_CS)
                    sqlite3_bind_int(stmt, 3, Int32(index))
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }

            // Seed shortcuts
            let seeds: [(bundleId: String, displayName: String, shortcutName: String, keyCode: Int32, modifierFlags: Int64, sortOrder: Int32)] = [
                ("com.apple.finder",    "Finder",  "New Window",     45, Int64(NSEvent.ModifierFlags.command.rawValue),                      0),
                ("com.apple.finder",    "Finder",  "Close Window",   13, Int64(NSEvent.ModifierFlags.command.rawValue),                      1),
                ("com.apple.finder",    "Finder",  "Search Window",   3, Int64(NSEvent.ModifierFlags([.command, .option]).rawValue),          2),
                ("com.vivaldi.Vivaldi", "Vivaldi", "New Window",     45, Int64(NSEvent.ModifierFlags.command.rawValue),                      0),
                ("com.vivaldi.Vivaldi", "Vivaldi", "New Tab",        17, Int64(NSEvent.ModifierFlags.command.rawValue),                      1),
                ("com.vivaldi.Vivaldi", "Vivaldi", "Close Tab",      13, Int64(NSEvent.ModifierFlags.command.rawValue),                      2),
                ("com.vivaldi.Vivaldi", "Vivaldi", "Context Search", 57, Int64(NSEvent.ModifierFlags.control.rawValue),                      3),
            ]

            let shortcutSQL = """
            INSERT INTO context_shortcuts (bundle_id, display_name, shortcut_name, description, key_code, modifier_flags, enabled, sort_order)
            VALUES (?, ?, ?, NULL, ?, ?, 1, ?);
            """

            for seed in seeds {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, shortcutSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, seed.bundleId, -1, SQLITE_TRANSIENT_CS)
                    sqlite3_bind_text(stmt, 2, seed.displayName, -1, SQLITE_TRANSIENT_CS)
                    sqlite3_bind_text(stmt, 3, seed.shortcutName, -1, SQLITE_TRANSIENT_CS)
                    sqlite3_bind_int(stmt, 4, seed.keyCode)
                    sqlite3_bind_int64(stmt, 5, seed.modifierFlags)
                    sqlite3_bind_int(stmt, 6, seed.sortOrder)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }

            print("🎯 [DatabaseManager] Context data seeded: \(apps.count) apps, \(seeds.count) shortcuts")
        }
    }

    // MARK: - Private Helpers

    private func contextShortcutFromStatement(_ statement: OpaquePointer?) -> ContextShortcut? {
        guard let statement = statement else { return nil }

        let id = sqlite3_column_int64(statement, 0)

        guard let bundleIdCString = sqlite3_column_text(statement, 1),
              let displayNameCString = sqlite3_column_text(statement, 2),
              let shortcutNameCString = sqlite3_column_text(statement, 3) else {
            return nil
        }

        let bundleId = String(cString: bundleIdCString)
        let displayName = String(cString: displayNameCString)
        let shortcutName = String(cString: shortcutNameCString)

        var description: String? = nil
        if let descCString = sqlite3_column_text(statement, 4) {
            description = String(cString: descCString)
        }

        let keyCode = UInt16(sqlite3_column_int(statement, 5))
        let modifierFlags = UInt(sqlite3_column_int64(statement, 6))
        let enabled = sqlite3_column_int(statement, 7) != 0
        let sortOrder = Int(sqlite3_column_int(statement, 8))

        return ContextShortcut(
            id: id,
            bundleId: bundleId,
            displayName: displayName,
            shortcutName: shortcutName,
            description: description,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            enabled: enabled,
            sortOrder: sortOrder
        )
    }
}
