//
//  DatabaseManager.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3
import AppKit

class DatabaseManager {
    
    // MARK: - Singleton
    
    static let shared = DatabaseManager()
    
    // MARK: - Properties
    
    var db: OpaquePointer?
    private let databaseFileName = "Jason.db"
    let queue = DispatchQueue(label: "com.jason.database", qos: .userInitiated)
    
    // MARK: - Initialization
    
    private init() {
        do {
            let dbPath = try getDatabasePath()
            print("📦 [DatabaseManager] Database path: \(dbPath)")
            
            // Open database
            if sqlite3_open(dbPath, &db) == SQLITE_OK {
                print("✅ [DatabaseManager] Database opened successfully")
                try setupDatabase()
                try runMigrations()
            } else {
                print("❌ [DatabaseManager] Failed to open database")
                if let error = sqlite3_errmsg(db) {
                    print("   Error: \(String(cString: error))")
                }
            }
        } catch {
            print("❌ [DatabaseManager] Failed to initialize database: \(error)")
        }
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Path
    
    private func getDatabasePath() throws -> String {
        let fileManager = FileManager.default
        
        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.pathNotFound
        }
        
        // Create Jason directory if it doesn't exist
        let jasonDir = appSupport.appendingPathComponent("Jason", isDirectory: true)
        
        if !fileManager.fileExists(atPath: jasonDir.path) {
            try fileManager.createDirectory(at: jasonDir, withIntermediateDirectories: true)
            print("📁 [DatabaseManager] Created Jason directory at: \(jasonDir.path)")
        }
        
        let dbPath = jasonDir.appendingPathComponent(databaseFileName).path
        return dbPath
    }
    
    // MARK: - Schema Setup
    
    private func setupDatabase() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        // Create folders table (all folders - registry + usage tracking)
        let foldersSQL = """
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            icon TEXT,
            icon_name TEXT,
            icon_color_hex TEXT,
            base_asset TEXT DEFAULT 'folder-blue',
            symbol_size REAL DEFAULT 24.0,
            symbol_offset REAL DEFAULT -8.0,
            last_accessed INTEGER NOT NULL,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create favorite_folders table (which folders are favorites)
        let favoriteFoldersSQL = """
        CREATE TABLE IF NOT EXISTS favorite_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL,
            max_items INTEGER,
            preferred_layout TEXT DEFAULT 'partialSlice',
            item_angle_size INTEGER DEFAULT 30,
            slice_positioning TEXT DEFAULT 'startClockwise',
            child_ring_thickness INTEGER DEFAULT 80,
            child_icon_size INTEGER DEFAULT 32,
            content_sort_order TEXT DEFAULT 'modified_newest',
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
        );
        """
        
        // Create favorite_apps table (favorite applications)
        let favoriteAppsSQL = """
        CREATE TABLE IF NOT EXISTS favorite_apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_identifier TEXT UNIQUE NOT NULL,
            display_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            icon_override TEXT,
            last_accessed INTEGER,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create favorite_files table (static file references)
        let favoriteFilesSQL = """
        CREATE TABLE IF NOT EXISTS favorite_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            display_name TEXT,
            sort_order INTEGER NOT NULL,
            icon_data BLOB,
            last_accessed INTEGER,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create favorite_dynamic_files table (rule-based file queries)
        let favoriteDynamicFilesSQL = """
        CREATE TABLE IF NOT EXISTS favorite_dynamic_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            display_name TEXT NOT NULL,
            folder_path TEXT NOT NULL,
            query_type TEXT NOT NULL,
            file_extensions TEXT,
            name_pattern TEXT,
            sort_order INTEGER NOT NULL,
            icon_data BLOB,
            last_accessed INTEGER,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create preferences table (general settings)
        let preferencesSQL = """
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Create ring_configurations table
        let ringConfigurationsSQL = """
        CREATE TABLE IF NOT EXISTS ring_configurations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            shortcut TEXT NOT NULL,
            ring_radius REAL NOT NULL,
            center_hole_radius REAL NOT NULL DEFAULT 56.0,
            icon_size REAL NOT NULL,
            start_angle REAL DEFAULT 0.0,
            trigger_type TEXT DEFAULT 'keyboard',
            key_code INTEGER,
            modifier_flags INTEGER,
            button_number INTEGER,
            swipe_direction TEXT,
            finger_count INTEGER,
            is_hold_mode INTEGER DEFAULT 0,
            auto_execute_on_release INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            is_active INTEGER DEFAULT 1,
            display_order INTEGER DEFAULT 0
        );
        """

        // Create unique index for active shortcuts
        let ringConfigurationsIndexSQL = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_shortcut 
        ON ring_configurations(shortcut) 
        WHERE is_active = 1;
        """

        // Create ring_providers table
        let ringProvidersSQL = """
        CREATE TABLE IF NOT EXISTS ring_providers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ring_id INTEGER NOT NULL,
            provider_type TEXT NOT NULL,
            provider_order INTEGER NOT NULL,
            parent_item_angle REAL,
            provider_config TEXT,
            FOREIGN KEY (ring_id) REFERENCES ring_configurations(id) ON DELETE CASCADE
        );
        """
        
        let circleCalibrationSQL = """
            CREATE TABLE IF NOT EXISTS circle_calibration (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                max_radius_variance REAL NOT NULL,
                min_circles REAL NOT NULL,
                min_radius REAL NOT NULL,
                calibrated_at INTEGER NOT NULL
            );
            """

        // Create unique index for provider order within rings
        let ringProvidersIndexSQL = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_ring_provider_order 
        ON ring_providers(ring_id, provider_order);
        """
        
        let tables = [
            foldersSQL,
            favoriteFoldersSQL,
            favoriteAppsSQL,
            favoriteFilesSQL,
            favoriteDynamicFilesSQL,
            preferencesSQL,
            ringConfigurationsSQL,
            ringConfigurationsIndexSQL,
            ringProvidersSQL,
            ringProvidersIndexSQL,
            circleCalibrationSQL
        ]
        
        for sql in tables {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to create table: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        print("✅ [DatabaseManager] Database schema created successfully")
    }
    
    // MARK: - Migrations
    
    private func runMigrations() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        print("🔄 [DatabaseManager] Running database migrations...")
        
        // Migration 1: Add trigger_type and button_number columns to ring_configurations
        // Check if trigger_type column exists
        let pragmaSQL = "PRAGMA table_info(ring_configurations);"
        var statement: OpaquePointer?
        var hasTriggerType = false
        var hasButtonNumber = false
        var hasIsHoldMode = false
        var hasAutoExecuteOnRelease = false
        var hasFingerCount = false
        
        if sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let columnName = sqlite3_column_text(statement, 1) {
                    let name = String(cString: columnName)
                    if name == "trigger_type" {
                        hasTriggerType = true
                    }
                    if name == "button_number" {
                        hasButtonNumber = true
                    }
                    if name == "is_hold_mode" {
                        hasIsHoldMode = true
                    }
                    if name == "auto_execute_on_release" {
                        hasAutoExecuteOnRelease = true
                    }
                    if name == "finger_count" {
                        hasFingerCount = true
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        
        // Add trigger_type column if missing
        if !hasTriggerType {
            print("🔄 [DatabaseManager] Adding trigger_type column to ring_configurations...")
            let addTriggerTypeSQL = "ALTER TABLE ring_configurations ADD COLUMN trigger_type TEXT DEFAULT 'keyboard';"
            if sqlite3_exec(db, addTriggerTypeSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Added trigger_type column")
                
                // Update existing rows to explicitly set trigger_type = 'keyboard'
                let updateSQL = "UPDATE ring_configurations SET trigger_type = 'keyboard' WHERE trigger_type IS NULL;"
                if sqlite3_exec(db, updateSQL, nil, nil, nil) == SQLITE_OK {
                    print("✅ [DatabaseManager] Updated existing rows to keyboard trigger type")
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to add trigger_type column: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        // Add button_number column if missing
        if !hasButtonNumber {
            print("🔄 [DatabaseManager] Adding button_number column to ring_configurations...")
            let addButtonNumberSQL = "ALTER TABLE ring_configurations ADD COLUMN button_number INTEGER;"
            if sqlite3_exec(db, addButtonNumberSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Added button_number column")
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to add button_number column: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        // Add is_hold_mode column if missing
        if !hasIsHoldMode {
            print("🔄 [DatabaseManager] Adding is_hold_mode column to ring_configurations...")
            let addIsHoldModeSQL = "ALTER TABLE ring_configurations ADD COLUMN is_hold_mode INTEGER DEFAULT 0;"
            if sqlite3_exec(db, addIsHoldModeSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Added is_hold_mode column")
                
                // Update existing rows to explicitly set is_hold_mode = 0 (tap mode)
                let updateSQL = "UPDATE ring_configurations SET is_hold_mode = 0 WHERE is_hold_mode IS NULL;"
                if sqlite3_exec(db, updateSQL, nil, nil, nil) == SQLITE_OK {
                    print("✅ [DatabaseManager] Updated existing rows to tap mode (is_hold_mode = 0)")
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to add is_hold_mode column: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        // Add auto_execute_on_release column if missing
        if !hasAutoExecuteOnRelease {
            print("🔄 [DatabaseManager] Adding auto_execute_on_release column to ring_configurations...")
            let addAutoExecuteSQL = "ALTER TABLE ring_configurations ADD COLUMN auto_execute_on_release INTEGER DEFAULT 1;"
            if sqlite3_exec(db, addAutoExecuteSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Added auto_execute_on_release column")
                
                // Update existing rows to explicitly set auto_execute_on_release = 1 (enabled by default)
                let updateSQL = "UPDATE ring_configurations SET auto_execute_on_release = 1 WHERE auto_execute_on_release IS NULL;"
                if sqlite3_exec(db, updateSQL, nil, nil, nil) == SQLITE_OK {
                    print("✅ [DatabaseManager] Updated existing rows to auto-execute enabled (auto_execute_on_release = 1)")
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to add auto_execute_on_release column: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        // Add finger_count column if missing
        if !hasFingerCount {
            print("🔄 [DatabaseManager] Adding finger_count column to ring_configurations...")
            let addFingerCountSQL = "ALTER TABLE ring_configurations ADD COLUMN finger_count INTEGER;"
            if sqlite3_exec(db, addFingerCountSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Added finger_count column")
                
                // Migrate existing "swipe" triggers to "trackpad" with finger_count = 3
                let migrateSwipeSQL = """
                UPDATE ring_configurations 
                SET trigger_type = 'trackpad', finger_count = 3 
                WHERE trigger_type = 'swipe';
                """
                if sqlite3_exec(db, migrateSwipeSQL, nil, nil, nil) == SQLITE_OK {
                    print("✅ [DatabaseManager] Migrated 'swipe' triggers to 'trackpad' with finger_count = 3")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("⚠️ [DatabaseManager] Warning: Could not migrate swipe triggers: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to add finger_count column: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        print("✅ [DatabaseManager] Migrations completed successfully")
    }
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case pathNotFound
    case schemaCreationFailed
    case saveFailed
    case fetchFailed
}
