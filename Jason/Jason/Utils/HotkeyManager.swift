//
//  HotkeyManager.swift
//  Jason
//
//  Created by Timothy Velberg on 05/11/2025.
//

import Foundation
import AppKit

/// Manages all keyboard shortcuts and modifier key tracking for the circular UI
class HotkeyManager {
    
    // MARK: - Callbacks
    
    /// Called when Escape is pressed while UI is visible
    var onHide: (() -> Void)?
    
    /// Called when Shift is pressed (for preview toggle)
    var onShiftPressed: (() -> Void)?
    
    /// Called when Ctrl is released in app switcher mode
    var onCtrlReleasedInAppSwitcher: (() -> Void)?
    
    /// Called when the hold key is pressed (show UI while held)
    var onHoldKeyPressed: (() -> Void)?
    
    /// Called when the hold key is released (hide UI)
    var onHoldKeyReleased: (() -> Void)?
    
    /// Query function to check if UI is currently visible
    var isUIVisible: (() -> Bool)?
    
    /// Query function to check if in app switcher mode
    var isInAppSwitcherMode: (() -> Bool)?
    
    // MARK: - Configuration
    
    /// Key code for hold-to-show functionality (nil = disabled)
    var holdKeyCode: UInt16? = nil
    
    /// Check if the hold key is currently physically pressed
    var isHoldKeyPhysicallyPressed: Bool {
        return isHoldKeyCurrentlyPressed
    }
    
    // MARK: - State Tracking
    
    private var wasShiftPressed: Bool = false
    private var wasCtrlPressed: Bool = false
    private var isHoldKeyCurrentlyPressed: Bool = false
    private var requiresReleaseBeforeNextShow: Bool = false  // Prevents re-show while key still held
    
    // MARK: - Dynamic Shortcuts
    
    /// Registered keyboard shortcuts: [configId: (keyCode, modifierFlags, callback)]
    private var registeredShortcuts: [Int: (keyCode: UInt16, modifierFlags: UInt, callback: () -> Void)] = [:]
    
    /// Registered mouse buttons: [configId: (buttonNumber, modifierFlags, callback)]
    private var registeredMouseButtons: [Int: (buttonNumber: Int32, modifierFlags: UInt, callback: () -> Void)] = [:]
    
    /// Registered trackpad gestures: [configId: (direction, fingerCount, modifierFlags, callback)]
    private var registeredSwipes: [Int: (direction: String, fingerCount: Int, modifierFlags: UInt, callback: () -> Void)] = [:]
    
    // MARK: - Event Monitors
    
    private var globalKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyUpMonitor: Any?  // For hold key release
    private var localKeyUpMonitor: Any?   // For hold key release
    
    // Swipe gesture monitoring
    private var globalSwipeMonitor: Any?
    
    // Multitouch gesture detection (using private MultitouchSupport framework)
    private var multitouchDetector: MultitouchGestureDetector?
    
    // Circle gesture coordination (new architecture)
    private var circleCoordinator: MultitouchCoordinator?

    /// Registered circle gestures: [configId: (direction, fingerCount, modifierFlags, callback)]
    private var registeredCircles: [Int: (direction: RotationDirection, fingerCount: Int, modifierFlags: UInt, callback: (RotationDirection) -> Void)] = [:]

    // Mouse button monitoring (CGEventTap required for buttons 3+)
    private var mouseEventTap: CFMachPort?
    private var mouseRunLoopSource: CFRunLoopSource?
    
    // MARK: - Initialization
    
    init() {
        print("[HotkeyManager] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("[HotkeyManager] Deallocated")
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring for hotkeys
    func startMonitoring() {
        guard globalKeyMonitor == nil else {
            print("[HotkeyManager] Already monitoring")
            return
        }
        
        // Listen for global key events (keyDown only)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Listen for global key up events (for hold key release)
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUpEvent(event)
        }
        
        // Listen for global modifier key changes
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Listen for local key events (when our window is active)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let handled = self?.handleKeyEvent(event) ?? false
            return handled ? nil : event
        }
        
        // Listen for local key up events (for hold key release)
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUpEvent(event)
            return event
        }
        
        // Listen for local modifier changes
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // Listen for global swipe events
        print("🔧 [HotkeyManager] Setting up swipe monitor...")
        globalSwipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe]) { [weak self] event in
            print("🔍 [HotkeyManager] .swipe EVENT RECEIVED!")
            self?.handleSwipeEvent(event)
        }
        
        if globalSwipeMonitor != nil {
            print("✅ [HotkeyManager] Global swipe monitor CREATED successfully")
        } else {
            print("❌ [HotkeyManager] Global swipe monitor FAILED to create")
        }
        
        // DIAGNOSTIC: Also try listening for other gesture-related events
        print("🔧 [HotkeyManager] Setting up diagnostic gesture monitors...")
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.gesture]) { event in
            print("📍 [DIAGNOSTIC] .gesture event: type=\(event.type.rawValue)")
        }
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.beginGesture]) { event in
            print("📍 [DIAGNOSTIC] .beginGesture event")
        }
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.endGesture]) { event in
            print("📍 [DIAGNOSTIC] .endGesture event")
        }
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.magnify]) { event in
            print("📍 [DIAGNOSTIC] .magnify event: magnification=\(event.magnification)")
        }
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.rotate]) { event in
            print("📍 [DIAGNOSTIC] .rotate event: rotation=\(event.rotation)")
        }
        let _ = NSEvent.addGlobalMonitorForEvents(matching: [.smartMagnify]) { event in
            print("📍 [DIAGNOSTIC] .smartMagnify event")
        }
        
        print("[HotkeyManager] Monitoring started")
        if holdKeyCode != nil {
            print("   Hold key configured → Hold to show, release to hide")
        }
        
        // Log all registered shortcuts with details
        if !registeredShortcuts.isEmpty {
            print("   📋 Registered shortcuts:")
            for (configId, registration) in registeredShortcuts {
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (keyCode=\(registration.keyCode), modifiers=\(registration.modifierFlags))")
            }
        } else {
            print("   No shortcuts registered yet!")
        }
        
        // Log all registered mouse buttons
        if !registeredMouseButtons.isEmpty {
            print("   🖱️  Registered mouse buttons:")
            for (configId, registration) in registeredMouseButtons {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (button=\(registration.buttonNumber), modifiers=\(registration.modifierFlags))")
            }
            // Start mouse monitoring if needed
            if mouseEventTap == nil {
                startMouseMonitoring()
            }
        }
        
        // Log all registered trackpad gestures
        if !registeredSwipes.isEmpty {
            print("Registered trackpad gestures:")
            for (configId, registration) in registeredSwipes {
                let display = formatTrackpadGesture(direction: registration.direction, fingerCount: registration.fingerCount, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (direction=\(registration.direction), fingers=\(registration.fingerCount), modifiers=\(registration.modifierFlags))")
            }
            
            // Start multitouch monitoring for trackpad gestures
            print("   🎯 Starting MultitouchSupport framework monitoring...")
            startMultitouchMonitoring()
        }
        
        // Calibration trigger: Ctrl+9
        registerShortcut(keyCode: 25, modifierFlags: NSEvent.ModifierFlags.control.rawValue, forConfigId: 99999) { [weak self] in
            print("🎯 Starting circle calibration...")
            self?.startCircleCalibration()
        }
        
        // Start circle monitoring regardless of swipe registrations
        if circleCoordinator == nil {
            startCircleMonitoring()
        }
    }
    
    /// Stop monitoring for hotkeys
    func stopMonitoring() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
        
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        
        if let monitor = globalSwipeMonitor {
            NSEvent.removeMonitor(monitor)
            globalSwipeMonitor = nil
        }
        
        // Stop multitouch monitoring
        stopMultitouchMonitoring()
        
        // Stop mouse monitoring
        stopMouseMonitoring()
        
        print("[HotkeyManager] Monitoring stopped")
    }
    
    /// Reset internal state (call when UI hides)
    func resetState() {
        wasShiftPressed = false
        wasCtrlPressed = false
        isHoldKeyCurrentlyPressed = false
        // Note: requiresReleaseBeforeNextShow is NOT reset here
        // It persists until the key is actually released (keyUp event)
    }
    
    // MARK: - Configuration Methods
    
    /// Configure the hold-to-show key
    /// - Parameter keyCode: The key code to use (e.g., KeyCode.space), or nil to disable
    func setHoldKey(_ keyCode: UInt16?) {
        holdKeyCode = keyCode
        if let keyCode = keyCode {
            print("[HotkeyManager] Hold key configured: keyCode \(keyCode)")
        } else {
            print("[HotkeyManager] Hold-to-show disabled")
        }
    }
    
    /// Require the hold key to be released before allowing the next show
    /// Call this when an action is executed while the hold key is still pressed
    func requireReleaseBeforeNextShow() {
        requiresReleaseBeforeNextShow = true
        print("[HotkeyManager] Hold key must be released before next show")
    }
    
    // MARK: - Dynamic Shortcut Registration
    
    /// Register a keyboard shortcut for a ring configuration
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - modifierFlags: The modifier flags bitfield
    ///   - configId: The ring configuration ID
    ///   - callback: The callback to execute when shortcut is pressed
    func registerShortcut(
        keyCode: UInt16,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        print("[HotkeyManager] Attempting to register shortcut for config \(configId):")
        
        // Check for conflicts with existing shortcuts
        for (existingId, existing) in registeredShortcuts {
            if existing.keyCode == keyCode && existing.modifierFlags == modifierFlags {
                let existingDisplay = formatShortcut(keyCode: existing.keyCode, modifiers: existing.modifierFlags)
                print("   [HotkeyManager] Shortcut conflict!")
                print("   Existing: Config \(existingId) with \(existingDisplay)")
                print("   New: Config \(configId) with \(shortcutDisplay)")
                print("   Unregistering old shortcut...")
                unregisterShortcut(forConfigId: existingId)
                break
            }
        }
        
        // Store registration
        registeredShortcuts[configId] = (keyCode, modifierFlags, callback)
    }
    
    /// Unregister a shortcut
    func unregisterShortcut(forConfigId configId: Int) {
        if let _ = registeredShortcuts.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered shortcut for config \(configId)")
        }
    }
    
    /// Unregister all shortcuts
    func unregisterAllShortcuts() {
        let count = registeredShortcuts.count
        registeredShortcuts.removeAll()
        print("[HotkeyManager] Unregistered all \(count) shortcut(s)")
    }
    
    // MARK: - Mouse Button Registration
    
    /// Register a mouse button trigger for a ring configuration
    /// - Parameters:
    ///   - buttonNumber: The mouse button number (2=middle, 3=back, 4=forward)
    ///   - modifierFlags: The modifier flags bitfield
    ///   - configId: The ring configuration ID
    ///   - callback: The callback to execute when button is pressed
    func registerMouseButton(
        buttonNumber: Int32,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        let buttonDisplay = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags)
        print("[HotkeyManager] Attempting to register mouse button for config \(configId): \(buttonDisplay)")
        
        // Check for conflicts with existing mouse buttons
        for (existingId, existing) in registeredMouseButtons {
            if existing.buttonNumber == buttonNumber && existing.modifierFlags == modifierFlags {
                let existingDisplay = formatMouseButton(buttonNumber: existing.buttonNumber, modifiers: existing.modifierFlags)
                print("   [HotkeyManager] Mouse button conflict!")
                print("   Existing: Config \(existingId) with \(existingDisplay)")
                print("   New: Config \(configId) with \(buttonDisplay)")
                print("   Unregistering old mouse button...")
                unregisterMouseButton(forConfigId: existingId)
                break
            }
        }
        
        // Store registration
        registeredMouseButtons[configId] = (buttonNumber, modifierFlags, callback)
        
        // Start mouse monitoring if this is the first mouse button
        if registeredMouseButtons.count == 1 && mouseEventTap == nil {
            startMouseMonitoring()
        }
    }
    
    /// Unregister a mouse button
    func unregisterMouseButton(forConfigId configId: Int) {
        if let _ = registeredMouseButtons.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered mouse button for config \(configId)")
            
            // Stop mouse monitoring if no more mouse buttons registered
            if registeredMouseButtons.isEmpty {
                stopMouseMonitoring()
            }
        }
    }
    
    /// Unregister all mouse buttons
    func unregisterAllMouseButtons() {
        let count = registeredMouseButtons.count
        registeredMouseButtons.removeAll()
        print("[HotkeyManager] Unregistered all \(count) mouse button(s)")
        
        if count > 0 {
            stopMouseMonitoring()
        }
    }
    
    
    // MARK: - Swipe Gesture Registration
    
    /// Register a swipe gesture trigger for a ring configuration
    /// - Parameters:
    ///   - direction: The swipe direction ("up", "down", "left", "right")
    ///   - modifierFlags: The modifier flags bitfield
    ///   - configId: The ring configuration ID
    ///   - callback: The callback to execute when swipe is detected
    func registerSwipe(
        direction: String,
        fingerCount: Int,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        let swipeDisplay = formatTrackpadGesture(direction: direction, fingerCount: fingerCount, modifiers: modifierFlags)
        print("[HotkeyManager] Attempting to register trackpad gesture for config \(configId): \(swipeDisplay)")
        
        // Check for conflicts with existing gestures
        for (existingId, existing) in registeredSwipes {
            if existing.direction == direction &&
               existing.fingerCount == fingerCount &&
               existing.modifierFlags == modifierFlags {
                let existingDisplay = formatTrackpadGesture(direction: existing.direction, fingerCount: existing.fingerCount, modifiers: existing.modifierFlags)
                print("   [HotkeyManager] Trackpad gesture conflict!")
                print("   Existing: Config \(existingId) with \(existingDisplay)")
                print("   New: Config \(configId) with \(swipeDisplay)")
                print("   Unregistering old gesture...")
                unregisterSwipe(forConfigId: existingId)
                break
            }
        }
        
        // Store registration
        registeredSwipes[configId] = (direction, fingerCount, modifierFlags, callback)
    }
    
    /// Unregister a swipe gesture
    func unregisterSwipe(forConfigId configId: Int) {
        if let _ = registeredSwipes.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered swipe for config \(configId)")
        }
    }
    
    /// Unregister all swipe gestures
    func unregisterAllSwipes() {
        let count = registeredSwipes.count
        registeredSwipes.removeAll()
        print("[HotkeyManager] Unregistered all \(count) swipe gesture(s)")
    }
    
    // MARK: - Multitouch Monitoring
    
    private func startMultitouchMonitoring() {
        guard multitouchDetector == nil else {
            print("   ⚠️ Multitouch detector already exists")
            return
        }
        
        let detector = MultitouchGestureDetector()
        
        // Set up swipe callback
        detector.onSwipeDetected = { [weak self] direction, fingerCount in
            self?.handleMultitouchSwipe(direction: direction, fingerCount: fingerCount)
        }
        
        // Set as shared instance for C callback
        MultitouchGestureDetector.setShared(detector)
        
        // Register with LiveDataCoordinator for sleep/wake handling
        LiveDataCoordinator.shared.register(detector)
        
        // Start monitoring
        detector.startMonitoring()
        
        multitouchDetector = detector
        
        // Start circle gesture coordinator
        startCircleMonitoring()
    }
    
    private func stopMultitouchMonitoring() {
        
        // Stop circle monitoring
        stopCircleMonitoring()
        
        if let detector = multitouchDetector {
            // Unregister from LiveDataCoordinator
            LiveDataCoordinator.shared.unregister(detector)
            
            detector.stopMonitoring()
            MultitouchGestureDetector.setShared(nil)
            multitouchDetector = nil
            print("🛑 [HotkeyManager] Multitouch monitoring stopped")
        }
    }
    
    func registerCircle(
        direction: RotationDirection,
        fingerCount: Int,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping (RotationDirection) -> Void
    ) {
        let display = formatCircleGesture(direction: direction, fingerCount: fingerCount, modifiers: modifierFlags)
        print("[HotkeyManager] Registering circle gesture for config \(configId): \(display)")
        
        // Check for conflicts
        for (existingId, existing) in registeredCircles {
            if existing.direction == direction &&
               existing.fingerCount == fingerCount &&
               existing.modifierFlags == modifierFlags {
                print("   [HotkeyManager] Circle gesture conflict with config \(existingId) - unregistering old")
                unregisterCircle(forConfigId: existingId)
                break
            }
        }
        
        registeredCircles[configId] = (direction, fingerCount, modifierFlags, callback)
    }

    func unregisterCircle(forConfigId configId: Int) {
        if let _ = registeredCircles.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered circle for config \(configId)")
        }
    }

    func unregisterAllCircles() {
        let count = registeredCircles.count
        registeredCircles.removeAll()
        print("[HotkeyManager] Unregistered all \(count) circle gesture(s)")
    }

    // MARK: - Circle Monitoring

    private func startCircleMonitoring() {
        guard circleCoordinator == nil else {
            print("⚠️ [HotkeyManager] Circle coordinator already exists")
            return
        }
        
        print("🔵 [HotkeyManager] Starting circle gesture monitoring...")
        
        let coordinator = MultitouchCoordinator.withCircleRecognition(debugLogging: true)
        coordinator.onGesture = { [weak self] event in
            self?.handleCircleGesture(event)
        }
        
        // Load saved calibration
        if let saved = DatabaseManager.shared.loadCircleCalibration() {
            print("🎯 [HotkeyManager] Found saved calibration in database:")
            print("   📅 Calibrated: \(saved.calibratedAt.formatted())")
            print("   📊 maxRadiusVariance: \(String(format: "%.4f", saved.maxRadiusVariance))")
            print("   📊 minCircles: \(String(format: "%.2f", saved.minCircles))")
            print("   📊 minRadius: \(String(format: "%.3f", saved.minRadius))")
            
            if let circleRecognizer = coordinator.recognizer(identifier: "circle") as? CircleRecognizer {
                let defaultConfig = CircleRecognizer.Config()
                print("   🔧 Default config was:")
                print("      maxRadiusVariance: \(String(format: "%.4f", defaultConfig.maxRadiusVariance))")
                print("      minCircles: \(String(format: "%.2f", defaultConfig.minCircles))")
                print("      minRadius: \(String(format: "%.3f", defaultConfig.minRadius))")
                
                circleRecognizer.config.maxRadiusVariance = saved.maxRadiusVariance
                circleRecognizer.config.minCircles = saved.minCircles
                circleRecognizer.config.minRadius = saved.minRadius
                
                print("   ✅ Applied calibration to recognizer")
            } else {
                print("   ❌ Could not find circle recognizer to apply calibration!")
            }
        } else {
            print("🎯 [HotkeyManager] No saved calibration found - using defaults")
            if let circleRecognizer = coordinator.recognizer(identifier: "circle") as? CircleRecognizer {
                print("   📊 maxRadiusVariance: \(String(format: "%.4f", circleRecognizer.config.maxRadiusVariance))")
                print("   📊 minCircles: \(String(format: "%.2f", circleRecognizer.config.minCircles))")
                print("   📊 minRadius: \(String(format: "%.3f", circleRecognizer.config.minRadius))")
            }
        }

        // Save when calibration completes
        coordinator.onCircleCalibrationComplete = { config in
            print("💾 [HotkeyManager] Calibration complete - saving to database:")
            print("   📊 maxRadiusVariance: \(String(format: "%.4f", config.maxRadiusVariance))")
            print("   📊 minCircles: \(String(format: "%.2f", config.minCircles))")
            print("   📊 minRadius: \(String(format: "%.3f", config.minRadius))")
            
            let entry = CircleCalibrationEntry(
                maxRadiusVariance: config.maxRadiusVariance,
                minCircles: config.minCircles,
                minRadius: config.minRadius,
                calibratedAt: Date()
            )
            DatabaseManager.shared.saveCircleCalibration(entry)
        }
        
        coordinator.startMonitoring()
        
        // Register with LiveDataCoordinator for sleep/wake handling
        LiveDataCoordinator.shared.register(coordinator)
        circleCoordinator = coordinator
    }

    private func stopCircleMonitoring() {
        guard let coordinator = circleCoordinator else { return }
        
        LiveDataCoordinator.shared.unregister(coordinator)
        coordinator.stopMonitoring()
        circleCoordinator = nil
    }

    private func handleCircleGesture(_ event: GestureEvent) {
        guard case .circle(let direction, let fingerCount) = event else { return }
        
        let isUIVisible = isUIVisible?() ?? false
        
        guard !isUIVisible else {
            print("   ⏭️ Ignoring circle - UI is visible")
            return
        }
        
        // Get current modifier flags
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("🔵 [HotkeyManager] Circle detected: \(direction), fingers=\(fingerCount), modifiers=\(eventModifiers)")
        
        // Match against registered circles
        for (configId, registration) in registeredCircles {
            if registration.direction == direction &&
               registration.fingerCount == fingerCount &&
               registration.modifierFlags == eventModifiers {
                let display = formatCircleGesture(direction: direction, fingerCount: fingerCount, modifiers: eventModifiers)
                print("✅ [HotkeyManager] Circle MATCHED for config \(configId): \(display)")
                
                // Dispatch to main thread for UI operations
                DispatchQueue.main.async {
                    registration.callback(direction)
                }
                return
            }
        }
        
        print("   ⚠️ No matching circle gesture found")
    }

    private func formatCircleGesture(direction: RotationDirection, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let dirSymbol = direction == .clockwise ? "↻" : "↺"
        let dirName = direction == .clockwise ? "Clockwise" : "Counter-Clockwise"
        parts.append("\(dirSymbol) \(fingerCount)-Finger \(dirName) Circle")
        
        return parts.joined()
    }
    
    private func handleMultitouchSwipe(direction: MultitouchGestureDetector.SwipeDirection, fingerCount: Int) {
        let isUIVisible = isUIVisible?() ?? false
        
        // Only handle swipes when UI is hidden
        guard !isUIVisible else {
            print("   ⏭️ Ignoring swipe - UI is visible")
            return
        }
        
        // Get current modifier flags
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        let directionString = direction.rawValue
        
        print("[HotkeyManager] Multitouch swipe detected: direction=\(directionString), fingers=\(fingerCount), modifiers=\(eventModifiers)")
        
        // Check registered trackpad gestures - must match direction, fingerCount, AND modifiers
        for (configId, registration) in registeredSwipes {
            if registration.direction == directionString &&
               registration.fingerCount == fingerCount &&
               registration.modifierFlags == eventModifiers {
                let display = formatTrackpadGesture(direction: registration.direction, fingerCount: registration.fingerCount, modifiers: registration.modifierFlags)
                print("✅ [HotkeyManager] Trackpad gesture MATCHED for config \(configId): \(display)")
                registration.callback()
                return
            }
        }
        
        print("   ⚠️ No matching trackpad gesture found for \(directionString) with \(fingerCount) fingers and modifiers \(eventModifiers)")
    }
    
    // MARK: - Mouse Monitoring
    
    /// Start monitoring for mouse button events (CGEventTap required for buttons 3+)
    private func startMouseMonitoring() {
        guard mouseEventTap == nil else {
            print("[HotkeyManager] Mouse monitoring already active")
            return
        }
        
        print("[HotkeyManager] Starting mouse button monitoring...")
        
        // Create event tap for other mouse button events (buttons 3+)
        let eventMask = (1 << CGEventType.otherMouseDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Extract self from refcon
                let mySelf = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                mySelf.handleMouseEvent(event, type: type)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [HotkeyManager] Failed to create mouse event tap")
            print("   NOTE: This requires Accessibility permissions!")
            return
        }
        
        mouseEventTap = eventTap
        mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("✅ [HotkeyManager] Mouse button monitoring started")
        
        // Log registered mouse buttons
        if !registeredMouseButtons.isEmpty {
            print("   🖱️  Registered mouse buttons:")
            for (configId, registration) in registeredMouseButtons {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (button=\(registration.buttonNumber), modifiers=\(registration.modifierFlags))")
            }
        }
    }
    
    /// Stop monitoring for mouse button events
    private func stopMouseMonitoring() {
        if let eventTap = mouseEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
            mouseEventTap = nil
            mouseRunLoopSource = nil
            print("[HotkeyManager] Mouse button monitoring stopped")
        }
    }
    
    // MARK: - Private Handlers
    
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let isUIVisible = isUIVisible?() ?? false
        
        // Log every key event for debugging
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // print("[HotkeyManager] Key event: keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue), UI visible=\(isUIVisible)")
        
        // Hold key pressed (if configured)
        if let holdKeyCode = holdKeyCode, event.keyCode == holdKeyCode && !isHoldKeyCurrentlyPressed {
            // Check if we need to wait for a release first
            if requiresReleaseBeforeNextShow {
                print("[HotkeyManager] Hold key pressed but waiting for release - ignoring")
                return true  // Consume to prevent beep
            }
            
            print("⌨️ [HotkeyManager] Hold key pressed")
            isHoldKeyCurrentlyPressed = true
            onHoldKeyPressed?()
            return true  // Consumed
        }
        
        // Escape = Hide UI (only when UI is visible)
        if event.keyCode == 53 && isUIVisible {
            print("⌨️ [HotkeyManager] Escape pressed")
            onHide?()
            return true  // Consumed
        }
        
        // Check dynamic shortcuts (always check - toggle works when visible too)
        print("🔍 [HotkeyManager] Checking \(registeredShortcuts.count) registered shortcut(s)...")
        
        for (configId, registration) in registeredShortcuts {
            let registeredModifiers = NSEvent.ModifierFlags(rawValue: registration.modifierFlags)
                .intersection([.command, .control, .option, .shift])
            
            print("   🔍 Config \(configId): keyCode=\(registration.keyCode) (want \(event.keyCode)), modifiers=\(registeredModifiers.rawValue) (have \(eventModifiers.rawValue))")
            
            if event.keyCode == registration.keyCode &&
               eventModifiers == registeredModifiers {
                print("[HotkeyManager] Dynamic shortcut MATCHED for config \(configId)!")
                registration.callback()
                return true  // Consumed
            } else {
                if event.keyCode != registration.keyCode {
                    print("   KeyCode mismatch: \(event.keyCode) != \(registration.keyCode)")
                }
                if eventModifiers != registeredModifiers {
                    print("   Modifier mismatch: \(eventModifiers.rawValue) != \(registeredModifiers.rawValue)")
                }
            }
        }
        
        print("[HotkeyManager] No matching shortcut found")
        return false  // Not handled
    }
    
    private func handleKeyUpEvent(_ event: NSEvent) {
        // Hold key released (if configured and was pressed)
        if let holdKeyCode = holdKeyCode, event.keyCode == holdKeyCode {
            print("[HotkeyManager] Hold key released")
            
            // Clear the "requires release" flag now that key is actually released
            if requiresReleaseBeforeNextShow {
                requiresReleaseBeforeNextShow = false
                print("Hold key released - ready for next show")
            }
            
            // Only trigger hide callback if key was actually pressed (not just waiting for release)
            if isHoldKeyCurrentlyPressed {
                isHoldKeyCurrentlyPressed = false
                onHoldKeyReleased?()
            }
            return
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        // Only process flag changes when UI is visible
        guard isUIVisible?() ?? false else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCtrlPressed = event.modifierFlags.contains(.control)
        
        // Handle Ctrl release in App Switcher Mode
        let inAppSwitcherMode = isInAppSwitcherMode?() ?? false
        if inAppSwitcherMode && wasCtrlPressed && !isCtrlPressed {
            print("[HotkeyManager] Ctrl released in app switcher mode")
            onCtrlReleasedInAppSwitcher?()
            wasCtrlPressed = false
            return
        }
        
        // Track Ctrl state
        wasCtrlPressed = isCtrlPressed
        
        // Only trigger on SHIFT press (transition from not-pressed to pressed)
        if isShiftPressed && !wasShiftPressed {
            print("[HotkeyManager] Shift pressed")
            onShiftPressed?()
        }
        
        wasShiftPressed = isShiftPressed
    }
    
    private func handleMouseEvent(_ event: CGEvent, type: CGEventType) {
        let isUIVisible = isUIVisible?() ?? false
        
        // Only handle mouse buttons when UI is hidden
        guard !isUIVisible else { return }
        
        // Get button number and current modifier flags
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        
        // Get current modifier flags from the event
        let cgFlags = event.flags
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("🖱️  [HotkeyManager] Mouse button \(buttonNumber) pressed, modifiers=\(eventModifiers)")
        
        // Check registered mouse buttons
        for (configId, registration) in registeredMouseButtons {
            if buttonNumber == Int64(registration.buttonNumber) && eventModifiers == registration.modifierFlags {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("✅ [HotkeyManager] Mouse button MATCHED for config \(configId): \(display)")
                registration.callback()
                return
            }
        }
        
        print("[HotkeyManager] No matching mouse button found")
    }
    
    // MARK: - Helper Methods
    
    /// Format a shortcut for display (helper for logging)
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Convert key code to string (helper for display)
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 40: return "K"
        case 49: return "Space"
        case 50: return "`"
        case 53: return "Esc"
        default: return "[\(keyCode)]"
        }
    }
    
    
    private func handleSwipeEvent(_ event: NSEvent) {
        print("🎯 [HotkeyManager] handleSwipeEvent CALLED!")
        print("   Event type: \(event.type.rawValue)")
        print("   Event subtype: \(event.subtype.rawValue)")
        print("   deltaX: \(event.deltaX), deltaY: \(event.deltaY)")
        
        let isUIVisible = isUIVisible?() ?? false
        print("   isUIVisible: \(isUIVisible)")
        
        // Only handle swipes when UI is hidden
        guard !isUIVisible else {
            print("   ⚠️ Ignoring swipe - UI is visible")
            return
        }
        
        // Determine swipe direction from deltaX and deltaY
        let deltaX = event.deltaX
        let deltaY = event.deltaY
        
        print("   📏 Delta values: X=\(deltaX), Y=\(deltaY)")
        
        let direction: String
        if abs(deltaX) > abs(deltaY) {
            // Horizontal swipe
            direction = deltaX > 0 ? "right" : "left"
            print("   → Detected HORIZONTAL swipe: \(direction)")
        } else {
            // Vertical swipe
            direction = deltaY > 0 ? "down" : "up"
            print("   → Detected VERTICAL swipe: \(direction)")
        }
        
        // Get current modifier flags
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("👆 [HotkeyManager] Swipe gesture detected (NSEvent - no finger count): direction=\(direction), modifiers=\(eventModifiers)")
        
        // Note: NSEvent.swipe doesn't provide finger count, so we can't match against it
        // This handler is kept for debugging but MultitouchGestureDetector is the primary mechanism
        print("   ⚠️ NSEvent swipe handler called - finger count unknown, cannot match registered gestures")
        print("   ℹ️ Registered gestures require finger count from MultitouchGestureDetector")
    }
    /// Format a mouse button for display (helper for logging)
    private func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert button number to readable name
        let buttonName: String
        switch buttonNumber {
        case 2:
            buttonName = "Button 3 (Middle)"
        case 3:
            buttonName = "Button 4 (Back)"
        case 4:
            buttonName = "Button 5 (Forward)"
        default:
            buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        
        return parts.joined()
    }
    
    /// Format a trackpad gesture for display (helper for logging)
    private func formatTrackpadGesture(direction: String, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert direction to arrow emoji with finger count
        let directionSymbol: String
        switch direction.lowercased() {
        case "up":
            directionSymbol = "↑ \(fingerCount)-Finger Swipe Up"
        case "down":
            directionSymbol = "↓ \(fingerCount)-Finger Swipe Down"
        case "left":
            directionSymbol = "← \(fingerCount)-Finger Swipe Left"
        case "right":
            directionSymbol = "→ \(fingerCount)-Finger Swipe Right"
        case "tap":
            directionSymbol = "👆 \(fingerCount)-Finger Tap"
        default:
            directionSymbol = "\(fingerCount)-Finger Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
    }
    
    // MARK: - Circle Calibration

    /// Start circle gesture calibration - draw 5 circles to set thresholds
    func startCircleCalibration() {
        circleCoordinator?.startCircleCalibration()
    }

    /// Cancel calibration
    func cancelCircleCalibration() {
        circleCoordinator?.cancelCircleCalibration()
    }

    /// Check if currently calibrating
    var isCircleCalibrating: Bool {
        circleCoordinator?.isCalibrating ?? false
    }
}

// MARK: - Hotkey Configuration

// MARK: - Hotkey Configuration

extension HotkeyManager {
    /// Key codes for reference
    struct KeyCode {
        static let escape: UInt16 = 53
        static let k: UInt16 = 40
        static let graveAccent: UInt16 = 50  // ` / ~
        
        // Function keys for hold-to-show (recommended - no conflicts)
        static let f13: UInt16 = 105
        static let f14: UInt16 = 107
        static let f15: UInt16 = 113
        static let f16: UInt16 = 106
        static let f17: UInt16 = 64
        static let f18: UInt16 = 79
        static let f19: UInt16 = 80
        
        // Other keys for hold-to-show
        static let space: UInt16 = 49
        static let tab: UInt16 = 48
        static let f: UInt16 = 3
        static let g: UInt16 = 5
        static let h: UInt16 = 4
    }
}
