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
            base_asset TEXT DEFAULT '_folder-blue_',
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
            preferred_layout TEXT DEFAULT 'fullCircle',
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
        
        // Create folder_cache table (performance optimization)
        let folderCacheSQL = """
        CREATE TABLE IF NOT EXISTS folder_cache (
            path TEXT PRIMARY KEY,
            last_scanned INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            item_count INTEGER NOT NULL
        );
        """
        
        // Create preferences table (general settings)
        let preferencesSQL = """
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Execute all schema creation
        let tables = [foldersSQL, favoriteFoldersSQL, favoriteAppsSQL, favoriteFilesSQL, favoriteDynamicFilesSQL, folderCacheSQL, preferencesSQL]
        
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
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case pathNotFound
    case schemaCreationFailed
    case saveFailed
    case fetchFailed
}
