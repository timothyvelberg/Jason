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

    // MARK: - Cached Playback Snapshot

    /// Spotify state is read via AppleScript, which blocks (and can hang for seconds
    /// if Spotify is busy). We never read it on the main thread: provideFunctions()
    /// builds nodes from this cached snapshot and kicks off a background refresh that
    /// posts a provider update only when the snapshot changes.
    private let snapshotLock = NSLock()
    private var cachedState: String = "stopped"
    private var cachedTrack: (name: String, artist: String)?
    private var lastSnapshotRefresh: Date = .distantPast
    private var isRefreshingSnapshot = false
    private let snapshotMinInterval: TimeInterval = 1.0
    private let snapshotQueue = DispatchQueue(label: "com.jason.spotify", qos: .userInitiated)

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
        // Warm the snapshot so the first show has real state without blocking.
        refreshSnapshotAsync(force: true)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - FunctionProvider Protocol

    func provideFunctions() -> [FunctionNode] {
        guard isSpotifyRunning else {
            return [notRunningNode()]
        }

        // Build from the cached snapshot — never block the main thread on AppleScript.
        // Refresh in the background; an update is posted if the snapshot changes.
        refreshSnapshotAsync()
        let (state, track) = currentSnapshot()
        let isPlaying = state == "playing"

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
        refreshSnapshotAsync(force: true)
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

    // MARK: - Snapshot

    private func currentSnapshot() -> (state: String, track: (name: String, artist: String)?) {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return (cachedState, cachedTrack)
    }

    /// Refresh the cached snapshot on a background queue (AppleScript can block).
    /// Posts a provider update only when the snapshot actually changes, which also
    /// terminates the provideFunctions → refresh → update loop once state settles.
    private func refreshSnapshotAsync(force: Bool = false) {
        snapshotLock.lock()
        let due = force || Date().timeIntervalSince(lastSnapshotRefresh) > snapshotMinInterval
        guard due, !isRefreshingSnapshot else {
            snapshotLock.unlock()
            return
        }
        isRefreshingSnapshot = true
        snapshotLock.unlock()

        snapshotQueue.async { [weak self] in
            guard let self = self else { return }
            let running = self.isSpotifyRunning
            let newState = running ? self.playerState : "stopped"
            let newTrack = running ? self.currentTrackInfo : nil

            self.snapshotLock.lock()
            let changed = newState != self.cachedState
                || !self.tracksEqual(self.cachedTrack, newTrack)
            self.cachedState = newState
            self.cachedTrack = newTrack
            self.lastSnapshotRefresh = Date()
            self.isRefreshingSnapshot = false
            self.snapshotLock.unlock()

            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
                }
            }
        }
    }

    private func tracksEqual(_ a: (name: String, artist: String)?, _ b: (name: String, artist: String)?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (l?, r?): return l.name == r.name && l.artist == r.artist
        default: return false
        }
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

    /// Synchronous AppleScript — only ever called from the background snapshot/refresh
    /// queue (or the async action helper below), never on the main thread.
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
        // Spotify changed track/state — refresh the snapshot, which posts a provider
        // update once the new state is read (off the main thread).
        refreshSnapshotAsync(force: true)
    }
}
