//
//  AccessibilityPermissionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 25/02/2026.
import Foundation
import ApplicationServices

enum AccessibilityPermissionState {
    case notGranted
    case grantedPendingRestart
    case active
}

@Observable
final class AccessibilityPermissionManager {

    static let shared = AccessibilityPermissionManager()

    var state: AccessibilityPermissionState

    private init() {
        state = AXIsProcessTrusted() ? .active : .notGranted
    }

    func update() {
        let trusted = AXIsProcessTrusted()
        switch state {
        case .notGranted:
            if trusted { state = .grantedPendingRestart }
        case .grantedPendingRestart:
            break // stays pending until restart
        case .active:
            if !trusted { state = .notGranted } // e.g. permission revoked after OS update
        }
    }
}
