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
    
    /// Query function to check if UI is currently visible
    var isUIVisible: (() -> Bool)?
    
    /// Query function to check if in app switcher mode
    var isInAppSwitcherMode: (() -> Bool)?
    
    /// Called when Up arrow is pressed while UI is visible
    var onArrowUp: (() -> Void)?

    /// Called when Down arrow is pressed while UI is visible
    var onArrowDown: (() -> Void)?
    
    /// Called when Left arrow is pressed while UI is visible
    var onArrowLeft: (() -> Void)?

    /// Called when Right arrow is pressed while UI is visible
    var onArrowRight: (() -> Void)?
    
    /// Called when a letter key is pressed while UI is visible
    var onCharacterInput: ((String) -> Void)?
    
    /// Called when Enter is pressed while UI is visible
    var onEnter: (() -> Void)?
    
    // MARK: - Configuration
    
    /// Key code for hold-to-show functionality (nil = disabled)
    var holdKeyCode: UInt16? = nil
    
    // MARK: - State Tracking
    
    private var wasShiftPressed: Bool = false
    private var wasCtrlPressed: Bool = false
    private var requiresReleaseBeforeNextShow: Bool = false  // Prevents re-show while key still held
    private var activeHoldRegistration: Int? = nil
    
    // Keyboard event tap (CGEventTap required to intercept before other apps)
    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    
    // MARK: - Dynamic Shortcuts
    
    /// Registered mouse buttons: [configId: (buttonNumber, modifierFlags, callback)]
    private var registeredMouseButtons: [Int: (buttonNumber: Int32, modifierFlags: UInt, callback: () -> Void)] = [:]
    
    /// Registered trackpad gestures: [configId: (direction, fingerCount, modifierFlags, callback)]
    private var registeredSwipes: [Int: (direction: String, fingerCount: Int, modifierFlags: UInt, callback: () -> Void)] = [:]
    private var registeredShortcuts: [Int: KeyboardRegistration] = [:]

    struct KeyboardRegistration {
        let keyCode: UInt16
        let modifierFlags: UInt
        let isHoldMode: Bool
        let onPress: () -> Void
        let onRelease: (() -> Void)?
    }
    
    /// Registered two-finger taps: [configId: (side, modifierFlags, callback)]
    private var registeredTwoFingerTaps: [Int: (side: TapSide, modifierFlags: UInt, callback: (TapSide) -> Void)] = [:]
    
    // MARK: - Event Monitors
    
    private var globalKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyUpMonitor: Any?  // For hold key release
    private var localKeyUpMonitor: Any?   // For hold key release
    
    // Swipe gesture monitoring
    private var globalSwipeMonitor: Any?
    
    // Unified multitouch gesture coordination (circles, swipes, taps, two-finger taps)
    private var multitouchCoordinator: MultitouchCoordinator?

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
        
        // Use CGEventTap for keyboard shortcuts (intercepts before other apps)
        startKeyboardEventTap()
        
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
        globalSwipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe]) { [weak self] event in
            self?.handleSwipeEvent(event)
        }
        
        // DIAGNOSTIC: Also try listening for other gesture-related events
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
        
        // Log all registered shortcuts with details
        if !registeredShortcuts.isEmpty {
            print("   Registered shortcuts:")
            for (configId, registration) in registeredShortcuts {
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (keyCode=\(registration.keyCode), modifiers=\(registration.modifierFlags))")
            }
        } else {
            print("   No shortcuts registered yet!")
        }
        
        // Log all registered mouse buttons
        if !registeredMouseButtons.isEmpty {
            print("   Registered mouse buttons:")
            for (configId, registration) in registeredMouseButtons {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (button=\(registration.buttonNumber), modifiers=\(registration.modifierFlags))")
            }
            // Start mouse monitoring if needed
            if mouseEventTap == nil {
                startMouseMonitoring()
            }
        }
        
        // Calibration trigger: Ctrl+9
        registerShortcut(keyCode: 25, modifierFlags: NSEvent.ModifierFlags.control.rawValue, forConfigId: 99999) { [weak self] in
            print("Starting circle calibration...")
            self?.startCircleCalibration()
        }
        
        // Start unified multitouch monitoring (handles all gesture types)
        if multitouchCoordinator == nil {
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
        stopCircleMonitoring()
        
        // Stop mouse monitoring
        stopMouseMonitoring()
        
        // Stop keyboard event tap
        stopKeyboardEventTap()
        
        print("[HotkeyManager] Monitoring stopped")
    }
    
    /// Reset internal state (call when UI hides)
    func resetState() {
        wasShiftPressed = false
        wasCtrlPressed = false
    }
    
    // MARK: - Configuration Methods
    
    
    /// Require the hold key to be released before allowing the next show
    /// Call this when an action is executed while the hold key is still pressed
    func requireReleaseBeforeNextShow() {
        requiresReleaseBeforeNextShow = true
        print("[HotkeyManager] Hold key must be released before next show")
    }
    
    // MARK: - Dynamic Shortcut Registration
    
    /// Register a keyboard shortcut for a ring configuration
    func registerShortcut(
        keyCode: UInt16,
        modifierFlags: UInt,
        isHoldMode: Bool = false,
        forConfigId configId: Int,
        onPress: @escaping () -> Void,
        onRelease: (() -> Void)? = nil
    ) {
        let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        let modeLabel = isHoldMode ? "HOLD" : "TAP"
        print("[HotkeyManager] Registering \(modeLabel) shortcut for config \(configId): \(shortcutDisplay)")
        
        // Check for conflicts with existing shortcuts
        for (existingId, existing) in registeredShortcuts {
            if existing.keyCode == keyCode && existing.modifierFlags == modifierFlags {
                print("   Conflict with config \(existingId) - unregistering old")
                unregisterShortcut(forConfigId: existingId)
                break
            }
        }
        
        // Store registration
        registeredShortcuts[configId] = KeyboardRegistration(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            isHoldMode: isHoldMode,
            onPress: onPress,
            onRelease: onRelease
        )
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
        guard multitouchCoordinator == nil else {
            print("[HotkeyManager] Multitouch coordinator already exists")
            return
        }
        
        print("[HotkeyManager] Starting unified multitouch monitoring...")
        
        let coordinator = MultitouchCoordinator()
        coordinator.debugLogging = false  // Set to true for debugging
        
        // Add circle recognizer
        let circleRecognizer = CircleRecognizer()
        coordinator.addRecognizer(circleRecognizer)
        
        // Add two-finger tap recognizer
        let twoFingerRecognizer = TwoFingerTapRecognizer()
        coordinator.addRecognizer(twoFingerRecognizer)
        
        // Add multi-finger gesture recognizer (swipes, taps, add gestures)
        let multiFingerRecognizer = MultiFingerGestureRecognizer()
        multiFingerRecognizer.debugLogging = true  // Set to true for debugging
        coordinator.addRecognizer(multiFingerRecognizer)
        
        coordinator.onGesture = { [weak self] event in
            self?.handleGestureEvent(event)
        }
        
        // Load saved circle calibration
        if let saved = DatabaseManager.shared.loadCircleCalibration() {
            print("[HotkeyManager] Found saved calibration in database:")
            print("   Calibrated: \(saved.calibratedAt.formatted())")
            print("   maxRadiusVariance: \(String(format: "%.4f", saved.maxRadiusVariance))")
            print("   minCircles: \(String(format: "%.2f", saved.minCircles))")
            print("   minRadius: \(String(format: "%.3f", saved.minRadius))")
            
            if let circleRec = coordinator.recognizer(identifier: "circle") as? CircleRecognizer {
                circleRec.config.maxRadiusVariance = saved.maxRadiusVariance
                circleRec.config.minCircles = saved.minCircles
                circleRec.config.minRadius = saved.minRadius
                print("   Applied calibration to recognizer")
            }
        } else {
            print("[HotkeyManager] No saved calibration found - using defaults")
        }

        // Save when calibration completes
        coordinator.onCircleCalibrationComplete = { config in
            print("[HotkeyManager] Calibration complete - saving to database")
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
        multitouchCoordinator = coordinator
        
        print("[HotkeyManager] Multitouch coordinator started with \(coordinator.recognizerCount) recognizer(s)")
    }

    private func stopCircleMonitoring() {
        guard let coordinator = multitouchCoordinator else { return }
        
        LiveDataCoordinator.shared.unregister(coordinator)
        coordinator.stopMonitoring()
        multitouchCoordinator = nil
        print("[HotkeyManager] Multitouch coordinator stopped")
    }

    private func handleGestureEvent(_ event: GestureEvent) {
        let isUIVisible = isUIVisible?() ?? false
        
        guard !isUIVisible else {
            print("   Ignoring gesture - UI is visible")
            return
        }
        
        // Get current modifier flags
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        switch event {
        case .circle(let direction, let fingerCount):
            for (configId, registration) in registeredCircles {
                if registration.direction == direction &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    let display = formatCircleGesture(direction: direction, fingerCount: fingerCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Circle MATCHED for config \(configId): \(display)")
                    
                    DispatchQueue.main.async {
                        registration.callback(direction)
                    }
                    return
                }
            }
            print("   No matching circle gesture found")
            
        case .twoFingerTap(let side):
            for (configId, registration) in registeredTwoFingerTaps {
                if registration.side == side && registration.modifierFlags == eventModifiers {
                    let display = formatTwoFingerTap(side: side, modifiers: eventModifiers)
                    print("[HotkeyManager] Two-finger tap MATCHED for config \(configId): \(display)")
                    
                    DispatchQueue.main.async {
                        registration.callback(side)
                    }
                    return
                }
            }
            print("   No matching two-finger tap found")
            
        case .swipe(let direction, let fingerCount):
            let directionString = direction.rawValue
            print("[HotkeyManager] Swipe detected: \(directionString), fingers=\(fingerCount), modifiers=\(eventModifiers)")
            for (configId, registration) in registeredSwipes {
                if registration.direction == directionString &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    let display = formatTrackpadGesture(direction: registration.direction, fingerCount: registration.fingerCount, modifiers: registration.modifierFlags)
                    print("[HotkeyManager] Swipe MATCHED for config \(configId): \(display)")
                    
                    DispatchQueue.main.async {
                        registration.callback()
                    }
                    return
                }
            }
            print("   No matching swipe gesture found")
            
        case .tap(let fingerCount):
            // Taps are registered as swipes with direction "tap"
            for (configId, registration) in registeredSwipes {
                if registration.direction == "tap" &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    let display = formatTrackpadGesture(direction: "tap", fingerCount: fingerCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Tap MATCHED for config \(configId): \(display)")
                    
                    DispatchQueue.main.async {
                        registration.callback()
                    }
                    return
                }
            }
            print("   No matching tap gesture found")
            
        case .fingerAdd(let fromCount, let toCount):
            // Check for registered "add" gestures
            for (configId, registration) in registeredSwipes {
                if registration.direction == "add" &&
                   registration.fingerCount == toCount &&
                   registration.modifierFlags == eventModifiers {
                    let display = formatTrackpadGesture(direction: "add", fingerCount: toCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Add MATCHED for config \(configId): \(display)")
                    
                    DispatchQueue.main.async {
                        registration.callback()
                    }
                    return
                }
            }
            print("   No matching add gesture found")
        }
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
            print("[HotkeyManager] Failed to create mouse event tap")
            print("   NOTE: This requires Accessibility permissions!")
            return
        }
        
        mouseEventTap = eventTap
        mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("[HotkeyManager] Mouse button monitoring started")
        
        // Log registered mouse buttons
        if !registeredMouseButtons.isEmpty {
            print("   Registered mouse buttons:")
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
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        
        // Escape = Hide UI (only when UI is visible)
        if event.keyCode == 53 && isUIVisible {
            print("[HotkeyManager] Escape pressed")
            onHide?()
            return true
        }
        
        // Arrow keys (only when UI is visible)
        if isUIVisible {
            switch event.keyCode {
            case 125:  // Down arrow
                print("[HotkeyManager] Down arrow pressed")
                onArrowDown?()
                return true
            case 126:  // Up arrow
                print("[HotkeyManager] Up arrow pressed")
                onArrowUp?()
                return true
            case 123:  // Left arrow
                print("[HotkeyManager] Left arrow pressed")
                onArrowLeft?()
                return true
            case 124:  // Right arrow
                print("[HotkeyManager] Right arrow pressed")
                onArrowRight?()
                return true
            case 36, 76:  // Return key, Keypad Enter
                print("[HotkeyManager] Enter pressed")
                onEnter?()
                return true
            default:
                break
            }
            
            // Letter keys for type-ahead search (only when UI is visible)
            // Allow only if no command/control/option modifiers (shift is ok for typing capitals)
            let hasBlockingModifiers = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            
            if !hasBlockingModifiers,
               let characters = event.charactersIgnoringModifiers?.lowercased(),
               characters.count == 1,
               let char = characters.first,
               char.isLetter {
                print("[HotkeyManager] Letter key pressed: '\(characters)'")
                onCharacterInput?(characters)
                return true
            }
        }
        
        // Find all registrations matching this keyCode
        let matchingRegistrations = registeredShortcuts.filter { $0.value.keyCode == event.keyCode }
        
        guard !matchingRegistrations.isEmpty else {
            return false  // No registrations for this key
        }
        
        // Find the BEST match: exact modifier match, preferring MORE modifiers (more specific)
        var bestMatch: (configId: Int, registration: KeyboardRegistration)? = nil
        var bestModifierCount = -1
        
        for (configId, registration) in matchingRegistrations {
            let registeredModifiers = NSEvent.ModifierFlags(rawValue: registration.modifierFlags)
                .intersection([.command, .control, .option, .shift])
            
            // Must be exact match
            guard eventModifiers == registeredModifiers else { continue }
            
            // Count modifiers (more = more specific)
            let modifierCount = registeredModifiers.rawValue.nonzeroBitCount
            
            if modifierCount > bestModifierCount {
                bestModifierCount = modifierCount
                bestMatch = (configId, registration)
            }
        }
        
        guard let match = bestMatch else {
            print("[HotkeyManager] No exact modifier match for keyCode \(event.keyCode)")
            return false
        }
        
        let display = formatShortcut(keyCode: match.registration.keyCode, modifiers: match.registration.modifierFlags)
        
        if match.registration.isHoldMode {
            // HOLD MODE
            // Check if already holding this one
            if activeHoldRegistration == match.configId {
                print("[HotkeyManager] Hold key already active - ignoring repeat")
                return true
            }
            
            // Check if we need release first
            if requiresReleaseBeforeNextShow && activeHoldRegistration != nil {
                print("[HotkeyManager] Waiting for release before next show")
                return true
            }
            
            print("[HotkeyManager] HOLD mode MATCHED for config \(match.configId): \(display)")
            activeHoldRegistration = match.configId
            match.registration.onPress()
            return true
            
        } else {
            // TAP MODE
            print("[HotkeyManager] TAP mode MATCHED for config \(match.configId): \(display)")
            match.registration.onPress()
            return true
        }
    }
    private func handleKeyUpEvent(_ event: NSEvent) {
        // Check if we have an active hold registration for this key
        guard let activeConfigId = activeHoldRegistration,
              let registration = registeredShortcuts[activeConfigId],
              registration.keyCode == event.keyCode else {
            return
        }
        
        let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
        print("[HotkeyManager] HOLD key released for config \(activeConfigId): \(display)")
        
        // Clear active state
        activeHoldRegistration = nil
        
        // Clear requires-release flag
        if requiresReleaseBeforeNextShow {
            requiresReleaseBeforeNextShow = false
            print("   Ready for next show")
        }
        
        // Call release callback
        registration.onRelease?()
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
                print("[HotkeyManager] Mouse button MATCHED for config \(configId): \(display)")
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
        print("[HotkeyManager] handleSwipeEvent CALLED!")
        print("   Event type: \(event.type.rawValue)")
        print("   Event subtype: \(event.subtype.rawValue)")
        print("   deltaX: \(event.deltaX), deltaY: \(event.deltaY)")
        
        let isUIVisible = isUIVisible?() ?? false
        print("   isUIVisible: \(isUIVisible)")
        
        // Only handle swipes when UI is hidden
        guard !isUIVisible else {
            print("   Ignoring swipe - UI is visible")
            return
        }
        
        // Determine swipe direction from deltaX and deltaY
        let deltaX = event.deltaX
        let deltaY = event.deltaY
        
        print("   Delta values: X=\(deltaX), Y=\(deltaY)")
        
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
        
        print("[HotkeyManager] Swipe gesture detected (NSEvent - no finger count): direction=\(direction), modifiers=\(eventModifiers)")
        
        // Note: NSEvent.swipe doesn't provide finger count, so we can't match against it
        // This handler is kept for debugging but MultitouchGestureDetector is the primary mechanism
        print("   NSEvent swipe handler called - finger count unknown, cannot match registered gestures")
        print("   Registered gestures require finger count from MultitouchGestureDetector")
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
            directionSymbol = "\(fingerCount)-Finger Tap"
        default:
            directionSymbol = "\(fingerCount)-Finger Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
    }
    
    // MARK: - Two-Finger Tap Registration

    func registerTwoFingerTap(
        side: TapSide,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping (TapSide) -> Void
    ) {
        let display = formatTwoFingerTap(side: side, modifiers: modifierFlags)
        print("[HotkeyManager] Registering two-finger tap for config \(configId): \(display)")
        
        // Check for conflicts
        for (existingId, existing) in registeredTwoFingerTaps {
            if existing.side == side && existing.modifierFlags == modifierFlags {
                print("   [HotkeyManager] Two-finger tap conflict with config \(existingId) - unregistering old")
                unregisterTwoFingerTap(forConfigId: existingId)
                break
            }
        }
        
        registeredTwoFingerTaps[configId] = (side, modifierFlags, callback)
    }

    func unregisterTwoFingerTap(forConfigId configId: Int) {
        if let _ = registeredTwoFingerTaps.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered two-finger tap for config \(configId)")
        }
    }

    func unregisterAllTwoFingerTaps() {
        let count = registeredTwoFingerTaps.count
        registeredTwoFingerTaps.removeAll()
        print("[HotkeyManager] Unregistered all \(count) two-finger tap(s)")
    }

    private func formatTwoFingerTap(side: TapSide, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let sideSymbol = side == .left ? "←" : "→"
        parts.append("\(sideSymbol) Two-Finger Tap \(side.rawValue.capitalized)")
        
        return parts.joined()
    }
    
    // MARK: - Keyboard Event Tap

    private func startKeyboardEventTap() {
        guard keyboardEventTap == nil else {
            print("[HotkeyManager] Keyboard event tap already active")
            return
        }
        
        print("[HotkeyManager] Starting keyboard event tap...")
        
        // Tap keyDown and keyUp events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let mySelf = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return mySelf.handleKeyboardEventTap(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create keyboard event tap")
            print("   NOTE: This requires Accessibility permissions!")
            return
        }
        
        keyboardEventTap = eventTap
        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("[HotkeyManager] Keyboard event tap started (intercepts before other apps)")
    }

    private func stopKeyboardEventTap() {
        if let eventTap = keyboardEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
            keyboardEventTap = nil
            keyboardRunLoopSource = nil
            print("[HotkeyManager] Keyboard event tap stopped")
        }
    }

    private func handleKeyboardEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events (re-enable if system disabled it)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = keyboardEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let cgFlags = event.flags
        
        // Convert CGEventFlags to NSEvent.ModifierFlags for comparison
        var eventModifiers: UInt = 0
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        // Normalize to only the modifier keys we care about
        let normalizedModifiers = eventModifiers & (
            NSEvent.ModifierFlags.command.rawValue |
            NSEvent.ModifierFlags.control.rawValue |
            NSEvent.ModifierFlags.option.rawValue |
            NSEvent.ModifierFlags.shift.rawValue
        )
        
        if type == .keyDown {
            // Check if this matches any registered shortcut
            for (configId, registration) in registeredShortcuts {
                if registration.keyCode == keyCode && registration.modifierFlags == normalizedModifiers {
                    let display = formatShortcut(keyCode: keyCode, modifiers: normalizedModifiers)
                    
                    if registration.isHoldMode {
                        // HOLD MODE
                        if activeHoldRegistration == configId {
                            // Already holding - consume but don't re-trigger
                            return nil
                        }
                        
                        if requiresReleaseBeforeNextShow && activeHoldRegistration != nil {
                            return nil
                        }
                        
                        print("[HotkeyManager] HOLD mode MATCHED for config \(configId): \(display) (intercepted)")
                        activeHoldRegistration = configId
                        
                        DispatchQueue.main.async {
                            registration.onPress()
                        }
                    } else {
                        // TAP MODE
                        print("[HotkeyManager] TAP mode MATCHED for config \(configId): \(display) (intercepted)")
                        
                        DispatchQueue.main.async {
                            registration.onPress()
                        }
                    }
                    
                    // Consume the event - don't let other apps see it
                    return nil
                }
            }
            
        } else if type == .keyUp {
            // Check if we have an active hold registration for this key
            if let activeConfigId = activeHoldRegistration,
               let registration = registeredShortcuts[activeConfigId],
               registration.keyCode == keyCode {
                
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("[HotkeyManager] HOLD key released for config \(activeConfigId): \(display)")
                
                activeHoldRegistration = nil
                
                if requiresReleaseBeforeNextShow {
                    requiresReleaseBeforeNextShow = false
                    print("   Ready for next show")
                }
                
                DispatchQueue.main.async {
                    registration.onRelease?()
                }
                
                // Consume the release too
                return nil
            }
        }
        
        // Not our shortcut - pass through to other apps
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Circle Calibration

    /// Start circle gesture calibration - draw 5 circles to set thresholds
    func startCircleCalibration() {
        multitouchCoordinator?.startCircleCalibration()
    }

    /// Cancel calibration
    func cancelCircleCalibration() {
        multitouchCoordinator?.cancelCircleCalibration()

    }

    /// Check if currently calibrating
    var isCircleCalibrating: Bool {
        multitouchCoordinator?.isCalibrating ?? false
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
