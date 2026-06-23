//
//  DatabaseManager+Migrations.swift
//  Jason
//
//  Schema migration system.
//
//  Historically the schema was created with `CREATE TABLE IF NOT EXISTS` only and
//  there was no version tracking, so any column added in a later release was never
//  applied to databases that already existed on disk — producing runtime
//  "no such column" errors (and silently failing inserts) on every upgrade.
//
//  This file fixes that going forward:
//   • `PRAGMA user_version` records the schema version of the on-disk database.
//   • Migration v1 reconciles a pre-versioning database up to the current column
//     set. It is idempotent (each column is added only if missing), so it is a
//     no-op on fresh installs and a catch-up on older installs.
//   • Add a new `if version < N { … }` block for each future schema change.
//

import Foundation
import SQLite3

extension DatabaseManager {

    /// Run any pending schema migrations. Call once at startup, after `setupDatabase()`.
    func runMigrations() {
        queue.sync {
            guard let db = db else { return }

            var version = readUserVersion(db)
            print("[Migrations] Database user_version = \(version)")

            if version < 1 {
                reconcileColumnsToV1(db)
                version = 1
                writeUserVersion(db, version)
                print("[Migrations] Reconciled schema; now at user_version 1")
            }

            // Future migrations go here, e.g.:
            // if version < 2 {
            //     addColumnIfMissing(db, table: "snippets", column: "usage_count", definition: "INTEGER DEFAULT 0")
            //     version = 2
            //     writeUserVersion(db, version)
            // }
        }
    }

    // MARK: - user_version

    private func readUserVersion(_ db: OpaquePointer) -> Int32 {
        var statement: OpaquePointer?
        var version: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                version = sqlite3_column_int(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        return version
    }

    private func writeUserVersion(_ db: OpaquePointer, _ version: Int32) {
        // PRAGMA statements cannot use bound parameters; `version` is an internal
        // Int32 constant (never user input), so interpolation is safe here.
        if sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil) != SQLITE_OK {
            print("[Migrations] Failed to set user_version: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - Column reconciliation (v1)

    /// Ensure every column the current code expects exists on databases that were
    /// created before version tracking. Every definition here is valid for
    /// `ALTER TABLE ADD COLUMN` — i.e. nullable, or a literal `DEFAULT` (SQLite
    /// forbids adding PRIMARY KEY / UNIQUE columns or non-constant defaults such as
    /// `strftime(...)`, so those `created_at` columns are intentionally omitted).
    private func reconcileColumnsToV1(_ db: OpaquePointer) {
        let columns: [(table: String, column: String, definition: String)] = [
            // folders
            ("folders", "icon", "TEXT"),
            ("folders", "icon_name", "TEXT"),
            ("folders", "icon_color_hex", "TEXT"),
            ("folders", "base_asset", "TEXT DEFAULT 'folder-blue'"),
            ("folders", "symbol_size", "REAL DEFAULT 24.0"),
            ("folders", "symbol_offset", "REAL DEFAULT -8.0"),
            ("folders", "access_count", "INTEGER DEFAULT 0"),

            // favorite_folders
            ("favorite_folders", "max_items", "INTEGER"),
            ("favorite_folders", "preferred_layout", "TEXT DEFAULT 'partialSlice'"),
            ("favorite_folders", "item_angle_size", "INTEGER DEFAULT 30"),
            ("favorite_folders", "slice_positioning", "TEXT DEFAULT 'startClockwise'"),
            ("favorite_folders", "child_ring_thickness", "INTEGER DEFAULT 80"),
            ("favorite_folders", "child_icon_size", "INTEGER DEFAULT 32"),
            ("favorite_folders", "content_sort_order", "TEXT DEFAULT 'modified_newest'"),

            // favorite_apps
            ("favorite_apps", "icon_override", "TEXT"),
            ("favorite_apps", "last_accessed", "INTEGER"),
            ("favorite_apps", "access_count", "INTEGER DEFAULT 0"),

            // favorite_files
            ("favorite_files", "display_name", "TEXT"),
            ("favorite_files", "icon_data", "BLOB"),
            ("favorite_files", "last_accessed", "INTEGER"),
            ("favorite_files", "access_count", "INTEGER DEFAULT 0"),

            // favorite_dynamic_files
            ("favorite_dynamic_files", "file_extensions", "TEXT"),
            ("favorite_dynamic_files", "name_pattern", "TEXT"),
            ("favorite_dynamic_files", "icon_data", "BLOB"),
            ("favorite_dynamic_files", "last_accessed", "INTEGER"),
            ("favorite_dynamic_files", "access_count", "INTEGER DEFAULT 0"),

            // ring_configurations
            ("ring_configurations", "center_hole_radius", "REAL NOT NULL DEFAULT 56.0"),
            ("ring_configurations", "start_angle", "REAL DEFAULT 0.0"),
            ("ring_configurations", "trigger_type", "TEXT DEFAULT 'keyboard'"),
            ("ring_configurations", "key_code", "INTEGER"),
            ("ring_configurations", "modifier_flags", "INTEGER"),
            ("ring_configurations", "button_number", "INTEGER"),
            ("ring_configurations", "swipe_direction", "TEXT"),
            ("ring_configurations", "finger_count", "INTEGER"),
            ("ring_configurations", "is_hold_mode", "INTEGER DEFAULT 0"),
            ("ring_configurations", "auto_execute_on_release", "INTEGER DEFAULT 1"),
            ("ring_configurations", "presentation_mode", "TEXT NOT NULL DEFAULT 'ring'"),
            ("ring_configurations", "is_active", "INTEGER DEFAULT 1"),
            ("ring_configurations", "display_order", "INTEGER DEFAULT 0"),
            ("ring_configurations", "bundle_id", "TEXT DEFAULT NULL"),

            // ring_triggers
            ("ring_triggers", "key_code", "INTEGER"),
            ("ring_triggers", "modifier_flags", "INTEGER DEFAULT 0"),
            ("ring_triggers", "button_number", "INTEGER"),
            ("ring_triggers", "swipe_direction", "TEXT"),
            ("ring_triggers", "finger_count", "INTEGER"),
            ("ring_triggers", "is_hold_mode", "INTEGER DEFAULT 0"),
            ("ring_triggers", "is_modifier_hold_mode", "INTEGER DEFAULT 0"),
            ("ring_triggers", "auto_execute_on_release", "INTEGER DEFAULT 1"),

            // ring_providers
            ("ring_providers", "parent_item_angle", "REAL"),
            ("ring_providers", "provider_config", "TEXT"),

            // clipboard_history
            ("clipboard_history", "rtf_data", "BLOB"),
            ("clipboard_history", "html_data", "BLOB"),
            ("clipboard_history", "source_app_bundle_id", "TEXT"),

            // todos
            ("todos", "is_completed", "INTEGER DEFAULT 0"),
            ("todos", "group_name", "TEXT DEFAULT 'default'"),

            // snippets
            ("snippets", "trigger_text", "TEXT"),

            // context_shortcut_groups
            ("context_shortcut_groups", "icon_name", "TEXT"),

            // context_shortcuts
            ("context_shortcuts", "description", "TEXT"),
            ("context_shortcuts", "icon_name", "TEXT"),
            ("context_shortcuts", "key_code", "INTEGER"),
            ("context_shortcuts", "modifier_flags", "INTEGER"),
            ("context_shortcuts", "menu_path", "TEXT"),
            ("context_shortcuts", "enabled", "INTEGER NOT NULL DEFAULT 1"),
            ("context_shortcuts", "group_id", "INTEGER DEFAULT NULL"),
        ]

        for entry in columns {
            addColumnIfMissing(db, table: entry.table, column: entry.column, definition: entry.definition)
        }
    }

    // MARK: - Helpers

    /// Add `column` to `table` only if it does not already exist. Idempotent.
    private func addColumnIfMissing(_ db: OpaquePointer, table: String, column: String, definition: String) {
        guard !columnExists(db, table: table, column: column) else { return }

        // `table`, `column` and `definition` all come from the hardcoded list above
        // (never user input); ALTER TABLE cannot bind identifiers anyway.
        let sql = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
        if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK {
            print("[Migrations] Added column \(table).\(column)")
        } else {
            print("[Migrations] Could not add \(table).\(column): \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func columnExists(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        var exists = false
        while sqlite3_step(statement) == SQLITE_ROW {
            // Column 1 of table_info is the column name.
            if let namePtr = sqlite3_column_text(statement, 1), String(cString: namePtr) == column {
                exists = true
                break
            }
        }
        sqlite3_finalize(statement)
        return exists
    }
}
