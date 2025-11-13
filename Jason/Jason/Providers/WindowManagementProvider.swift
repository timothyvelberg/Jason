//
//  WindowManagementProvider.swift
//  Jason
//
//  Provider for window management with directional positioning
//

import Foundation
import AppKit
import ApplicationServices

class WindowManagementProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "window-management"
    }
    
    var providerName: String {
        return "Window Management"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil) ?? NSImage()
    }
    
    // MARK: - Dependencies
    
    weak var circularUIManager: CircularUIManager?
    
    // MARK: - Initialization
    
    init() {
        print("🪟 WindowManagementProvider initialized")
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        let items = [
            // 12 o'clock (Top) - Fullscreen
            FunctionNode(
                id: "window-fullscreen",
                name: "Fullscreen",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.fullscreen(targetApp: manager.previousApp)
                    } else {
                        WindowManager.fullscreen()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.fullscreen(targetApp: manager.previousApp)
                    } else {
                        WindowManager.fullscreen()
                    }
                })
            ),
            
            // 1:30 (Top-Right) - Top-right quarter
            FunctionNode(
                id: "window-top-right",
                name: "Top Right",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionTopRight(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionTopRight()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionTopRight(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionTopRight()
                    }
                })
            ),
            
            // 3 o'clock (Right) - Right half
            FunctionNode(
                id: "window-right-half",
                name: "Right Half",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionRightHalf(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionRightHalf()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionRightHalf(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionRightHalf()
                    }
                })
            ),
            
            // 4:30 (Bottom-Right) - Bottom-right quarter
            FunctionNode(
                id: "window-bottom-right",
                name: "Bottom Right",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.down.right", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionBottomRight(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionBottomRight()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionBottomRight(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionBottomRight()
                    }
                })
            ),
            
            // 6 o'clock (Bottom) - Hide/Minimize
            FunctionNode(
                id: "window-hide",
                name: "Hide Window",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.hideWindow(targetApp: manager.previousApp)
                    } else {
                        WindowManager.hideWindow()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.hideWindow(targetApp: manager.previousApp)
                    } else {
                        WindowManager.hideWindow()
                    }
                })
            ),
            
            // 7:30 (Bottom-Left) - Bottom-left quarter
            FunctionNode(
                id: "window-bottom-left",
                name: "Bottom Left",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.down.left", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionBottomLeft(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionBottomLeft()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionBottomLeft(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionBottomLeft()
                    }
                })
            ),
            
            // 9 o'clock (Left) - Left half
            FunctionNode(
                id: "window-left-half",
                name: "Left Half",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionLeftHalf(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionLeftHalf()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionLeftHalf(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionLeftHalf()
                    }
                })
            ),
            
            // 10:30 (Top-Left) - Top-left quarter
            FunctionNode(
                id: "window-top-left",
                name: "Top Left",
                type: .action,
                icon: NSImage(systemSymbolName: "arrow.up.left", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionTopLeft(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionTopLeft()
                    }
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                    if let manager = self?.circularUIManager {
                        WindowManager.positionTopLeft(targetApp: manager.previousApp)
                    } else {
                        WindowManager.positionTopLeft()
                    }
                })
            )
        ]
        
        return [
            FunctionNode(
                id: "window-management",
                name: "Window Management",
                type: .category,
                icon: NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil) ?? NSImage(),
                children: items,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    func refresh() {
        print("🪟 [WindowManagementProvider] Refresh called (no-op)")
    }
}

// MARK: - Window Manager

class WindowManager {
    
    // MARK: - Accessibility Permissions
    
    private static func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("❌ [WindowManager] Accessibility permissions not granted")
            print("   Please grant Jason access in System Settings > Privacy & Security > Accessibility")
            
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Jason needs Accessibility permissions to manage windows. Please grant access in System Settings > Privacy & Security > Accessibility, then restart Jason."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings to Accessibility pane
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        return accessEnabled
    }
    
    // MARK: - Screen Utilities
    
    private static func getScreenFrame() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect.zero
        }
        return screen.visibleFrame
    }
    
    // MARK: - Window Positioning
    
    static func fullscreen(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        setWindowFrame(window, frame: screen)
        print("🪟 [WindowManager] Set window to fullscreen")
    }
    
    static func positionLeftHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x,
            y: screen.origin.y,
            width: screen.width / 2,
            height: screen.height
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to left half")
    }
    
    static func positionRightHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x + screen.width / 2,
            y: screen.origin.y,
            width: screen.width / 2,
            height: screen.height
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to right half")
    }
    
    static func positionTopLeft(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x,
            y: screen.origin.y,
            width: screen.width / 2,
            height: screen.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to top-left quarter")
    }
    
    static func positionTopRight(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x + screen.width / 2,
            y: screen.origin.y,
            width: screen.width / 2,
            height: screen.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to top-right quarter")
    }
    
    static func positionBottomLeft(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x,
            y: screen.origin.y + screen.height / 2,
            width: screen.width / 2,
            height: screen.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to bottom-left quarter")
    }
    
    static func positionBottomRight(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        let screen = getScreenFrame()
        let frame = CGRect(
            x: screen.origin.x + screen.width / 2,
            y: screen.origin.y + screen.height / 2,
            width: screen.width / 2,
            height: screen.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to bottom-right quarter")
    }
    
    static func hideWindow(targetApp: NSRunningApplication? = nil) {
        // Note: Hiding an app doesn't require Accessibility permissions
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        
        guard let app = app else {
            print("❌ [WindowManager] No frontmost application found")
            return
        }
        
        print("🔍 [WindowManager] Hiding app: \(app.localizedName ?? "Unknown")")
        app.hide()
        print("🪟 [WindowManager] Hid application")
    }
    
    // MARK: - Accessibility API
    
    private static func getFrontmostWindow(targetApp: NSRunningApplication? = nil) -> AXUIElement? {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        
        guard let app = app else {
            print("❌ [WindowManager] No target application")
            return nil
        }
        
        print("🔍 [WindowManager] Target app: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        
        if result == .success, let window = value {
            print("✅ [WindowManager] Got focused window")
            return (window as! AXUIElement)
        } else {
            print("❌ [WindowManager] Could not get focused window (error code: \(result.rawValue))")
            
            // Try to get any window if focused window fails
            var windowsValue: AnyObject?
            let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            
            if windowsResult == .success,
               let windows = windowsValue as? [AXUIElement],
               let firstWindow = windows.first {
                print("ℹ️ [WindowManager] Using first available window instead")
                return firstWindow
            }
        }
        
        return nil
    }
    
    private static func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        // Set position
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        
        if positionResult != .success {
            print("❌ [WindowManager] Failed to set position (error code: \(positionResult.rawValue))")
        } else {
            print("✅ [WindowManager] Set position to (\(frame.origin.x), \(frame.origin.y))")
        }
        
        // Set size
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        let sizeValue = AXValueCreate(.cgSize, &size)!
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        
        if sizeResult != .success {
            print("❌ [WindowManager] Failed to set size (error code: \(sizeResult.rawValue))")
        } else {
            print("✅ [WindowManager] Set size to (\(frame.size.width), \(frame.size.height))")
        }
    }
}
