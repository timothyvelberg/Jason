//
//  MouseButtonRecorder.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Button recorder that captures mouse button presses via a CGEvent tap.
//  Used inside AddTriggerSheet.
//

import SwiftUI
import AppKit

// MARK: - Mouse Button Recorder

struct MouseButtonRecorder: View {
    @Binding var buttonNumber: Int32?
    @Binding var modifierFlags: UInt?

    @State private var isRecording = false
    @State private var eventTap: CFMachPort?
    @State private var runLoopSource: CFRunLoopSource?
    @State private var handler: MouseButtonRecorderHandler?

    var displayText: String {
        if isRecording {
            return "Click mouse button..."
        } else if let buttonNumber {
            return formatDisplay(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
        } else {
            return "Click to record"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                isRecording ? stopRecording() : startRecording()
            }) {
                HStack {
                    Image(systemName: isRecording ? "record.circle.fill" : "computermouse")
                        .foregroundColor(isRecording ? .red : .blue)

                    Text(displayText)
                        .frame(minWidth: 120, alignment: .leading)
                        .foregroundColor(isRecording ? .secondary : .primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if buttonNumber != nil {
                Button(action: clearButton) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear mouse button")
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true

        let eventMask = (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let handler = Unmanaged<MouseButtonRecorderHandler>.fromOpaque(refcon!).takeUnretainedValue()
            handler.handleMouseEvent(event: event, type: type)
            return Unmanaged.passRetained(event)
        }

        let newHandler = MouseButtonRecorderHandler(
            buttonNumber: $buttonNumber,
            modifierFlags: $modifierFlags,
            isRecording: $isRecording,
            stopRecordingCallback: { self.stopRecording() }
        )
        handler = newHandler

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(newHandler).toOpaque()
        ) else {
            print("❌ [MouseRecorder] Failed to create event tap — check Accessibility permissions")
            isRecording = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("🖱️ [MouseRecorder] Recording started")
    }

    private func stopRecording() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        handler = nil
        isRecording = false
        print("🖱️ [MouseRecorder] Recording stopped")
    }

    private func clearButton() {
        buttonNumber = nil
        modifierFlags = nil
        print("🖱️ [MouseRecorder] Mouse button cleared")
    }

    // MARK: - Formatting

    private func formatDisplay(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        let name: String
        switch buttonNumber {
        case 2:  name = "Button 3 (Middle)"
        case 3:  name = "Button 4 (Back)"
        case 4:  name = "Button 5 (Forward)"
        default: name = "Button \(buttonNumber + 1)"
        }
        parts.append(name)
        return parts.joined()
    }
}

// MARK: - Mouse Button Recorder Handler

final class MouseButtonRecorderHandler {
    var buttonNumber: Binding<Int32?>
    var modifierFlags: Binding<UInt?>
    var isRecording: Binding<Bool>
    var stopRecordingCallback: (() -> Void)?

    init(
        buttonNumber: Binding<Int32?>,
        modifierFlags: Binding<UInt?>,
        isRecording: Binding<Bool>,
        stopRecordingCallback: (() -> Void)? = nil
    ) {
        self.buttonNumber = buttonNumber
        self.modifierFlags = modifierFlags
        self.isRecording = isRecording
        self.stopRecordingCallback = stopRecordingCallback
    }

    func handleMouseEvent(event: CGEvent, type: CGEventType) {
        guard isRecording.wrappedValue else { return }

        let btn = event.getIntegerValueField(.mouseEventButtonNumber)
        let cgFlags = event.flags
        var mods: UInt = 0
        if cgFlags.contains(.maskCommand)  { mods |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl)  { mods |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate){ mods |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift)    { mods |= NSEvent.ModifierFlags.shift.rawValue }

        print("🖱️ [MouseRecorder] Captured button \(btn), modifiers: \(mods)")

        DispatchQueue.main.async { [weak self] in
            self?.buttonNumber.wrappedValue = Int32(btn)
            self?.modifierFlags.wrappedValue = mods
            self?.isRecording.wrappedValue = false
            self?.stopRecordingCallback?()
        }
    }
}
