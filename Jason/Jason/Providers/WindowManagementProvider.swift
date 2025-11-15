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
            
            // Center - Fullscreen
            FunctionNode(
                id: "window-fullscreen",
                name: "Fullscreen",
                type: .action,
                icon: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil) ?? NSImage(),
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
//            // 12 o'clock (Top) - Top 50%
//            FunctionNode(
//                id: "window-top-half",
//                name: "Top Half",
//                type: .action,
//                icon: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) ?? NSImage(),
//                preferredLayout: nil,
//                showLabel: true,
//                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.positionTopHalf(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.positionTopHalf()
//                    }
//                }),
//                onRightClick: ModifierAwareInteraction(base: .doNothing),
//                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
//                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.positionTopHalf(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.positionTopHalf()
//                    }
//                })
//            ),
            
            // 1 o'clock - Top-right quarter
            FunctionNode(
                id: "window-top-right",
                name: "Top Right",
                type: .action,
                icon: NSImage(systemSymbolName: "chevron.up.forward.2", accessibilityDescription: nil) ?? NSImage(),
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
                icon: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage(),
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
            
            // 4:30 - Bottom-right quarter
            FunctionNode(
                id: "window-bottom-right",
                name: "Bottom Right",
                type: .action,
                icon: NSImage(systemSymbolName: "chevron.down.right.2", accessibilityDescription: nil) ?? NSImage(),
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
            
            // Hide
            FunctionNode(
                id: "window-hide",
                name: "Hide",
                type: .action,
                icon: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage(),
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
            
//            // 6 o'clock (Bottom) - Bottom 50%
//            FunctionNode(
//                id: "window-bottom-half",
//                name: "Bottom Half",
//                type: .action,
//                icon: NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil) ?? NSImage(),
//                preferredLayout: nil,
//                showLabel: true,
//                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.positionBottomHalf(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.positionBottomHalf()
//                    }
//                }),
//                onRightClick: ModifierAwareInteraction(base: .doNothing),
//                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
//                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.positionBottomHalf(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.positionBottomHalf()
//                    }
//                })
//            ),
            
            // 7:30 - Bottom-left quarter
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
            
            // 10:30 - Top-left quarter
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
        
//            
//            // Send to other monitor
//            FunctionNode(
//                id: "window-send-to-other-monitor",
//                name: "Other Monitor",
//                type: .action,
//                icon: NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil) ?? NSImage(),
//                preferredLayout: nil,
//                showLabel: true,
//                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.sendToOtherMonitor(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.sendToOtherMonitor()
//                    }
//                }),
//                onRightClick: ModifierAwareInteraction(base: .doNothing),
//                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
//                onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
//                    if let manager = self?.circularUIManager {
//                        WindowManager.sendToOtherMonitor(targetApp: manager.previousApp)
//                    } else {
//                        WindowManager.sendToOtherMonitor()
//                    }
//                })
//            ),
            
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
    
    private static func getScreenForWindow(_ window: AXUIElement) -> NSScreen? {
        // Get the window's current position
        var positionValue: AnyObject?
        let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        
        guard positionResult == .success,
              let axValue = positionValue,
              AXValueGetType(axValue as! AXValue) == .cgPoint else {
            print("⚠️ [WindowManager] Could not get window position, using main screen")
            return NSScreen.main
        }
        
        var position = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &position)
        
        print("🔍 [WindowManager] Window position: \(position)")
        
        // Find which screen contains this point
        // Check against the full frame (not visibleFrame) since window position is in screen coordinates
        for screen in NSScreen.screens {
            print("   Checking screen with frame: \(screen.frame), visibleFrame: \(screen.visibleFrame)")
            if screen.frame.contains(position) {
                print("✅ [WindowManager] Window is on screen with frame: \(screen.frame)")
                print("   Screen visibleFrame: \(screen.visibleFrame)")
                return screen
            }
        }
        
        // If exact point matching fails, find the closest screen
        print("⚠️ [WindowManager] Point not in any screen frame, finding closest screen")
        var closestScreen: NSScreen?
        var closestDistance: CGFloat = .infinity
        
        for screen in NSScreen.screens {
            let screenCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let distance = hypot(position.x - screenCenter.x, position.y - screenCenter.y)
            if distance < closestDistance {
                closestDistance = distance
                closestScreen = screen
            }
        }
        
        if let closest = closestScreen {
            print("✅ [WindowManager] Using closest screen with frame: \(closest.frame)")
            return closest
        }
        
        // Fallback to main screen if not found
        print("⚠️ [WindowManager] Could not determine screen, using main")
        return NSScreen.main
    }
    
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let frame = screen.visibleFrame
        setWindowFrame(window, frame: frame)
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width / 2,
            height: screenFrame.height
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.width / 2,
            y: screenFrame.origin.y,
            width: screenFrame.width / 2,
            height: screenFrame.height
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to right half")
    }
    
    static func positionTopHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width,
            height: screenFrame.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to top half")
    }
    
    static func positionBottomHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y + screenFrame.height / 2,
            width: screenFrame.width,
            height: screenFrame.height / 2
        )
        setWindowFrame(window, frame: frame)
        print("🪟 [WindowManager] Positioned window to bottom half")
    }
    
    static func positionTopLeft(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.width / 2,
            y: screenFrame.origin.y,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y + screenFrame.height / 2,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2
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
        
        guard let screen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine screen")
            return
        }
        
        let screenFrame = screen.visibleFrame
        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.width / 2,
            y: screenFrame.origin.y + screenFrame.height / 2,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2
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
    
    static func sendToOtherMonitor(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else {
            return
        }
        
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("❌ [WindowManager] No frontmost window found")
            return
        }
        
        guard let currentScreen = getScreenForWindow(window) else {
            print("❌ [WindowManager] Could not determine current screen")
            return
        }
        
        // Get all screens
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            print("⚠️ [WindowManager] Only one screen available")
            return
        }
        
        // Find the next screen (cycle through screens)
        guard let currentIndex = screens.firstIndex(where: { $0 == currentScreen }) else {
            print("❌ [WindowManager] Could not find current screen in screen list")
            return
        }
        
        let nextIndex = (currentIndex + 1) % screens.count
        let targetScreen = screens[nextIndex]
        
        print("🔄 [WindowManager] Moving window from screen \(currentIndex) to screen \(nextIndex)")
        
        // Get window's current frame
        var currentPositionValue: AnyObject?
        var currentSizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &currentPositionValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &currentSizeValue)
        
        var currentPosition = CGPoint.zero
        var currentSize = CGSize.zero
        
        if let posValue = currentPositionValue {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &currentPosition)
        }
        if let sizeValue = currentSizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &currentSize)
        }
        
        // Calculate relative position within current screen
        let currentScreenFrame = currentScreen.visibleFrame
        let relativeX = (currentPosition.x - currentScreenFrame.origin.x) / currentScreenFrame.width
        let relativeY = (currentPosition.y - currentScreenFrame.origin.y) / currentScreenFrame.height
        let relativeWidth = currentSize.width / currentScreenFrame.width
        let relativeHeight = currentSize.height / currentScreenFrame.height
        
        // Apply relative position to target screen
        let targetScreenFrame = targetScreen.visibleFrame
        let newFrame = CGRect(
            x: targetScreenFrame.origin.x + (relativeX * targetScreenFrame.width),
            y: targetScreenFrame.origin.y + (relativeY * targetScreenFrame.height),
            width: relativeWidth * targetScreenFrame.width,
            height: relativeHeight * targetScreenFrame.height
        )
        
        setWindowFrame(window, frame: newFrame)
        print("🪟 [WindowManager] Moved window to other monitor")
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
        print("🎯 [WindowManager] Setting window frame to: \(frame)")
        print("   Origin: (\(frame.origin.x), \(frame.origin.y))")
        print("   Size: (\(frame.width) x \(frame.height))")
        
        // Set size FIRST (some window managers adjust position based on size)
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        let sizeValue = AXValueCreate(.cgSize, &size)!
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        
        if sizeResult != .success {
            print("❌ [WindowManager] Failed to set size (error code: \(sizeResult.rawValue))")
        } else {
            print("✅ [WindowManager] Set size to (\(frame.size.width), \(frame.size.height))")
        }
        
        // Set position AFTER size
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        
        if positionResult != .success {
            print("❌ [WindowManager] Failed to set position (error code: \(positionResult.rawValue))")
        } else {
            print("✅ [WindowManager] Set position to (\(frame.origin.x), \(frame.origin.y))")
        }
    }
}
