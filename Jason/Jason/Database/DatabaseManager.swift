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
    private let databaseFileName = "Jason_01.db"
    let queue = DispatchQueue(label: "com.jason.database", qos: .userInitiated)
    
    // MARK: - Initialization
    
    private init() {
        do {
            let dbPath = try getDatabasePath()
            print("[DatabaseManager] Database path: \(dbPath)")
            
            // Open database
            if sqlite3_open(dbPath, &db) == SQLITE_OK {
                print("[DatabaseManager] Database opened successfully")
                try setupDatabase()
            } else {
                print("[DatabaseManager] Failed to open database")
                if let error = sqlite3_errmsg(db) {
                    print("   Error: \(String(cString: error))")
                }
            }
        } catch {
            print("[DatabaseManager] Failed to initialize database: \(error)")
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
        
        // Use bundle identifier for directory name (falls back to "Jason" if not available)
        let bundleID = Bundle.main.bundleIdentifier ?? "Jason"
        let jasonDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        
        if !fileManager.fileExists(atPath: jasonDir.path) {
            try fileManager.createDirectory(at: jasonDir, withIntermediateDirectories: true)
            print("📁 [DatabaseManager] Created directory at: \(jasonDir.path)")
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
            presentation_mode TEXT NOT NULL DEFAULT 'ring',
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
        
        // Create ring_triggers table
        let ringTriggersSQL = """
        CREATE TABLE IF NOT EXISTS ring_triggers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ring_id INTEGER NOT NULL,
            trigger_type TEXT NOT NULL,
            key_code INTEGER,
            modifier_flags INTEGER DEFAULT 0,
            button_number INTEGER,
            swipe_direction TEXT,
            finger_count INTEGER,
            is_hold_mode INTEGER DEFAULT 0,
            auto_execute_on_release INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            FOREIGN KEY (ring_id) REFERENCES ring_configurations(id) ON DELETE CASCADE
        );
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
        
        // Create clipboard_history table
        let clipboardHistorySQL = """
        CREATE TABLE IF NOT EXISTS clipboard_history (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            rtf_data BLOB,
            html_data BLOB,
            copied_at REAL NOT NULL,
            source_app_bundle_id TEXT
        );
        """
        
        let todosSQL = """
        CREATE TABLE IF NOT EXISTS todos (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_completed INTEGER DEFAULT 0,
            group_name TEXT DEFAULT 'default',
            created_at REAL NOT NULL
        );
        """
        
        let snippetsSQL = """
        CREATE TABLE IF NOT EXISTS snippets (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            trigger_text TEXT,
            sort_order INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
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
            circleCalibrationSQL,
            ringTriggersSQL,
            clipboardHistorySQL,
            todosSQL,
            snippetsSQL
        ]
        
        for sql in tables {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to create table: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        print("[DatabaseManager] Database schema created successfully")
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
