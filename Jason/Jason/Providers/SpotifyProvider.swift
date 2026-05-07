//
//  SpotifyProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 07/05/2026.
//  Provides Spotify playback controls as FunctionNodes.
//  Uses AppleScript to target Spotify directly regardless of frontmost app.
//  Refreshes automatically when Spotify posts PlaybackStateChanged notifications.
//

import Foundation
import AppKit

class SpotifyProvider: ObservableObject, FunctionProvider {

    // MARK: - FunctionProvider Protocol

    var providerId: String { "spotify" }
    var providerName: String { "Spotify" }
    var providerIcon: NSImage {
        NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Initialization

    init() {
        // Spotify posts this distributed notification on every track/state change
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(spotifyStateChanged),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        print("🎵 [SpotifyProvider] Initialized")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - FunctionProvider Protocol

    func provideFunctions() -> [FunctionNode] {
        guard isSpotifyRunning else {
            return [notRunningNode()]
        }

        let state  = playerState
        let isPlaying = state == "playing"
        let track  = currentTrackInfo

        let children: [FunctionNode] = [
            playPauseNode(isPlaying: isPlaying),
            nextNode(),
            trackInfoNode(track: track),
            previousNode()
        ]

        return [
            FunctionNode(
                id: "spotify-category",
                name: "Spotify",
                type: .category,
                icon: providerIcon,
                children: children,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }

    func refresh() {
        print("🎵 [SpotifyProvider] refresh() called")
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }

    func teardown() {
        print("🎵 [SpotifyProvider] teardown()")
        DistributedNotificationCenter.default().removeObserver(self)
        print("🎵 [SpotifyProvider] teardown complete")
    }

    // MARK: - Spotify State

    private var isSpotifyRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false
    }

    private var playerState: String {
        runAppleScript("tell application \"Spotify\" to player state as string") ?? "stopped"
    }

    private var currentTrackInfo: (name: String, artist: String)? {
        guard let name = runAppleScript("tell application \"Spotify\" to name of current track"),
              let artist = runAppleScript("tell application \"Spotify\" to artist of current track"),
              !name.isEmpty else {
            return nil
        }
        return (name, artist)
    }

    // MARK: - Node Builders

    private func trackInfoNode(track: (name: String, artist: String)?) -> FunctionNode {
        let label = track.map { "\($0.artist) — \($0.name)" } ?? "Nothing playing"
        return FunctionNode(
            id: "spotify-track-info",
            name: label,
            type: .action,
            icon: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.open(URL(string: "spotify:")!)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    private func previousNode() -> FunctionNode {
        FunctionNode(
            id: "spotify-previous",
            name: "Previous",
            type: .action,
            icon: NSImage(systemSymbolName: "backward.fill", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to previous track")
                },
                command: .executeKeepOpen { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to previous track")
                }
            ),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    private func playPauseNode(isPlaying: Bool) -> FunctionNode {
        let icon = isPlaying ? "pause.fill" : "play.fill"
        let label = isPlaying ? "Pause" : "Play"
        return FunctionNode(
            id: "spotify-playpause",
            name: label,
            type: .action,
            icon: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to playpause")
                },
                command: .executeKeepOpen { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to playpause")
                }
            ),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    private func nextNode() -> FunctionNode {
        FunctionNode(
            id: "spotify-next",
            name: "Next",
            type: .action,
            icon: NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to next track")
                },
                command: .executeKeepOpen { [weak self] in
                    self?.runAppleScriptAsync("tell application \"Spotify\" to next track")
                }
            ),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    private func notRunningNode() -> FunctionNode {
        FunctionNode(
            id: "spotify-not-running",
            name: "Spotify not running",
            type: .action,
            icon: NSImage(systemSymbolName: "slash.circle", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.open(URL(string: "spotify:")!)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    // MARK: - AppleScript

    /// Synchronous — used for reading state in provideFunctions().
    /// Always called from a non-main context via provideFunctions.
    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error = error {
            print("❌ [SpotifyProvider] AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }

    /// Async fire-and-forget — used for playback control actions.
    private func runAppleScriptAsync(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runAppleScript(source)
        }
    }

    // MARK: - Notifications

    @objc private func spotifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
        }
    }
}
