//
//  ProviderNotifications.swift
//  Jason
//
//  Created by Timothy Velberg on 29/10/2025.
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a provider's content has been updated
    static let providerContentUpdated = Notification.Name("providerContentUpdated")
}

// MARK: - Update Info

/// Type-safe container for provider update notifications
struct ProviderUpdateInfo {
    let providerId: String
    let folderPath: String?
    let metadata: [String: Any]?
    
    init(providerId: String, folderPath: String? = nil, metadata: [String: Any]? = nil) {
        self.providerId = providerId
        self.folderPath = folderPath
        self.metadata = metadata
    }
    
    /// Convert to userInfo dictionary for NotificationCenter
    var userInfo: [String: Any] {
        var info: [String: Any] = ["providerId": providerId]
        if let folderPath = folderPath {
            info["folderPath"] = folderPath
        }
        if let metadata = metadata {
            info["metadata"] = metadata
        }
        return info
    }
    
    /// Extract from notification userInfo
    static func from(_ notification: Notification) -> ProviderUpdateInfo? {
        guard let userInfo = notification.userInfo,
              let providerId = userInfo["providerId"] as? String else {
            return nil
        }
        
        let folderPath = userInfo["folderPath"] as? String
        let metadata = userInfo["metadata"] as? [String: Any]
        
        return ProviderUpdateInfo(
            providerId: providerId,
            folderPath: folderPath,
            metadata: metadata
        )
    }
}

// MARK: - Convenience Posting Methods

extension NotificationCenter {
    
    /// Post a provider content update notification
    func postProviderUpdate(_ info: ProviderUpdateInfo) {
        post(
            name: .providerContentUpdated,
            object: nil,
            userInfo: info.userInfo
        )
    }
    
    /// Quick post for simple provider updates (no extra context)
    func postProviderUpdate(providerId: String) {
        postProviderUpdate(ProviderUpdateInfo(providerId: providerId))
    }
    
    /// Quick post for folder-based updates
    func postProviderUpdate(providerId: String, folderPath: String) {
        postProviderUpdate(ProviderUpdateInfo(providerId: providerId, folderPath: folderPath))
    }
}
