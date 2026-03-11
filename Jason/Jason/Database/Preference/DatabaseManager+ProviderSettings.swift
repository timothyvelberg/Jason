//
//  DatabaseManager+ProviderSettings.swift
//  Jason
//
//  Created by Timothy Velberg on 11/03/2026.
//

import Foundation
import SQLite3

extension DatabaseManager {

    // MARK: - Provider Settings

    /// Save (upsert) a single setting for a provider
    func saveProviderSetting(providerId: String, key: String, value: String) {
        guard let db = db else { return }

        queue.async {
            let sql = """
            INSERT OR REPLACE INTO provider_settings (provider_id, setting_key, setting_value)
            VALUES (?, ?, ?);
            """
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (providerId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (key as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (value as NSString).utf8String, -1, nil)

                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⚙️ [ProviderSettings] Saved '\(key)' = '\(value)' for provider '\(providerId)'")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [ProviderSettings] Failed to save '\(key)' for provider '\(providerId)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [ProviderSettings] Failed to prepare upsert for '\(providerId)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    /// Load a single setting value for a provider. Returns nil if not set.
    func loadProviderSetting(providerId: String, key: String) -> String? {
        guard let db = db else { return nil }

        var result: String?

        queue.sync {
            let sql = """
            SELECT setting_value FROM provider_settings
            WHERE provider_id = ? AND setting_key = ?;
            """
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (providerId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (key as NSString).utf8String, -1, nil)

                if sqlite3_step(statement) == SQLITE_ROW {
                    if let raw = sqlite3_column_text(statement, 0) {
                        result = String(cString: raw)
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [ProviderSettings] Failed to prepare SELECT for '\(key)' on '\(providerId)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }

        return result
    }

    /// Load all settings for a provider as a key-value dictionary.
    /// Returns empty dictionary if no settings have been saved yet.
    func loadAllProviderSettings(providerId: String) -> [String: String] {
        guard let db = db else { return [:] }

        var results: [String: String] = [:]

        queue.sync {
            let sql = """
            SELECT setting_key, setting_value FROM provider_settings
            WHERE provider_id = ?;
            """
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (providerId as NSString).utf8String, -1, nil)

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let rawKey = sqlite3_column_text(statement, 0),
                       let rawValue = sqlite3_column_text(statement, 1) {
                        results[String(cString: rawKey)] = String(cString: rawValue)
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [ProviderSettings] Failed to prepare SELECT all for '\(providerId)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }

        return results
    }
}
