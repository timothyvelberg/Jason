//
//  DatabaseManager+CircleCalibration.swift
//  Jason
//
//  Created by Timothy Velberg on 10/01/2026.
//

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Circle Calibration
    
    /// Save circle calibration (replaces any existing)
    func saveCircleCalibration(_ entry: CircleCalibrationEntry) {
        guard let db = db else { return }
        
        queue.async {
            let sql = """
            INSERT OR REPLACE INTO circle_calibration (id, max_radius_variance, min_circles, min_radius, calibrated_at)
            VALUES (1, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, Double(entry.maxRadiusVariance))
                sqlite3_bind_double(statement, 2, Double(entry.minCircles))
                sqlite3_bind_double(statement, 3, Double(entry.minRadius))
                sqlite3_bind_int64(statement, 4, Int64(entry.calibratedAt.timeIntervalSince1970))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🎯 [DatabaseManager] Saved circle calibration (variance: \(String(format: "%.4f", entry.maxRadiusVariance)), minCircles: \(String(format: "%.2f", entry.minCircles)), minRadius: \(String(format: "%.3f", entry.minRadius)))")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save circle calibration: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for circle calibration: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Load circle calibration (returns nil if not calibrated)
    func loadCircleCalibration() -> CircleCalibrationEntry? {
        guard let db = db else { return nil }
        
        var result: CircleCalibrationEntry?
        
        queue.sync {
            let sql = "SELECT max_radius_variance, min_circles, min_radius, calibrated_at FROM circle_calibration WHERE id = 1;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    let maxRadiusVariance = Float(sqlite3_column_double(statement, 0))
                    let minCircles = Float(sqlite3_column_double(statement, 1))
                    let minRadius = Float(sqlite3_column_double(statement, 2))
                    let calibratedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)))
                    
                    result = CircleCalibrationEntry(
                        maxRadiusVariance: maxRadiusVariance,
                        minCircles: minCircles,
                        minRadius: minRadius,
                        calibratedAt: calibratedAt
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for circle calibration: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Delete circle calibration (reset to defaults)
    func deleteCircleCalibration() {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM circle_calibration WHERE id = 1;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    let changes = sqlite3_changes(db)
                    if changes > 0 {
                        print("🎯 [DatabaseManager] Deleted circle calibration (reset to defaults)")
                    } else {
                        print("🎯 [DatabaseManager] No circle calibration to delete")
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete circle calibration: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for circle calibration: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
}
