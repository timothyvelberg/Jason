# Jason — Code Review

**Date:** 2026-06-23
**Scope:** Full codebase — 164 Swift files, ~30,000 LOC (macOS menu-bar launcher; SwiftUI + AppKit, raw SQLite3 C API, private `MultitouchSupport` framework, CGEvent taps, Accessibility API).
**Method:** Six parallel subsystem deep-reviews (Database, Providers ×2, Input/Multitouch, UI, Core/Utils), with the highest-impact findings verified directly against the source.

## Legend

- 🔴 **Must fix** — memory corruption, crashes, data loss, security
- 🟠 **High** — broken features, leaks, UI hangs, data integrity
- 🟡 **Medium** — maintainability, correctness smells, performance
- 🟢 **Nice to have** — hygiene, cleanup, polish
- ✅ = verified directly in the source during review

## Overall assessment

An ambitious app with real engineering strengths — thoughtful `teardown()` discipline, consistent `[weak self]`, FSEvents debouncing/coalescing, clean EventKit authorization, and near-perfect `sqlite3_finalize` hygiene. The core weaknesses are **systemic concurrency discipline** and the **absence of any test safety net**, which together have allowed a cluster of latent crashes, data races, and a memory-corruption pattern to accumulate. Most criticals share a few root causes, so a handful of focused fixes clears most of the list.

**Suggested attack order:** #1, #2, #4 (one concurrency/SQLite pass) → #5 + #6 (DB migrations + clipboard safety) → #3 (multitouch lifecycle) → #7 (crash guards) → then the High tier.

---

## 🔴 Must fix — memory corruption, crashes, data loss, security

- [ ] **1. `SQLITE_STATIC` bound to temporary `NSString.utf8String` — use-after-free across the whole DB layer** ✅
  - **What:** The dominant bind idiom is `sqlite3_bind_text(stmt, n, (x as NSString).utf8String, -1, nil)`. The `nil` (= `SQLITE_STATIC`) promises SQLite the pointer stays valid, but `utf8String` is a temporary, autoreleased buffer. Pervasive (~150+ sites across Favorites/Folders/Cache/Ring/Preference). `DatabaseManager+Clipboard.swift`, `+Snippets.swift`, and `+ContextShortcuts.swift` already do it correctly with `SQLITE_TRANSIENT`.
  - **Why:** Textbook use-after-free — SQLite can read freed memory at `sqlite3_step`, causing corrupted/garbled writes or crashes. "Works by luck" today (autorelease pool hasn't drained), so it's intermittent and brutal to diagnose.
  - **Fix:** Pass `SQLITE_TRANSIENT` everywhere (or bind the Swift `String` directly).
  - **Example:** `Jason/Jason/Database/Favorites/DatabaseManager+FavoriteApps.swift:68`

- [ ] **2. `IconProvider` caches mutated from multiple threads with no locking** ✅ *(flagged independently by 3 reviewers)*
  - **What:** `IconProvider.shared` holds plain `[String: NSImage]` dictionaries + an access-order array, no lock/queue. Read/written from the main thread *and* from background `Task.detached` / `OperationQueue` paths (folder loading, 2 concurrent `RefreshOperation`s). `iconCache` is also never evicted.
  - **Why:** Concurrent mutation of Swift `Dictionary`/`Array` is undefined behavior → heap corruption / random crashes. Unbounded `iconCache` is also a memory leak.
  - **Fix:** Back caches with `NSCache` (thread-safe + eviction) or a serial queue/actor.
  - **Location:** `Jason/Jason/Utils/IconProvider.swift:17-25`

- [ ] **3. Multitouch device lifecycle + recognizer threading (riskiest area in the app)**
  - **What:** In `PrivateFrameworkSource.swift`: (a) `MTDeviceRelease` is *never called* → native device leak every start/stop and sleep/wake cycle; (b) the live wake path calls `MTUnregisterContactFrameCallback` on **stale post-sleep device pointers** (use-after-invalidation crash); (c) `MTDeviceStart` can double-start reused handles. Separately, recognizer state (`currentPath`, `phase`, …) is mutated on the framework callback thread while the main thread calls `reset()` — `Array` exclusivity crash during the reset that runs on every hide/wake.
  - **Why:** Non-deterministic crashes in `MultitouchSupport`, especially on sleep/wake — the near-impossible-to-reproduce kind.
  - **Fix:** Pair `MTDeviceStart`/`Stop`/`Release`; after wake, drop stale handles without calling MT functions on them; route all `processTouchFrame`/`reset` through one serial queue.
  - **Note:** `restartAfterWake()` / `prepareForSleep()` are **dead code** — their careful "don't touch stale devices" logic never runs (live wake path is `LiveDataCoordinator` → `MultitouchCoordinator.restartMonitoring()`).
  - **Location:** `Jason/Jason/Multitouch/PrivateFrameworkSource.swift:73-121`

- [ ] **4. SQLite connection used off its serial queue + a re-entrant `queue.sync` deadlock** ✅
  - **What:** Most DB access is serialized through `queue`, but several methods bypass it (EnhancedCache create/stats, the HeavyFolderManagement trio) and run `prepare/step` directly from background/main threads; startup issues `CREATE TABLE` from two threads at once. Worse: `updateFavoriteFolderSortOrder` calls `invalidateEnhancedCache` **inside** its own `queue.sync`, and that function *also* does `queue.sync` → guaranteed deadlock (freezes the thread, often the UI).
  - **Why:** One SQLite connection (default threading) used concurrently = `SQLITE_MISUSE`, "database is locked", or malformed-DB corruption.
  - **Fix:** Wrap the stragglers in `queue`; move cache-invalidation outside the `sync` block (or add an `_unsafe` variant).
  - **Locations:** `Jason/Jason/Database/Preference/DatabaseManager+SortOrder.swift:19,35`; `Jason/Jason/Database/Cache/DatabaseManager+EnhancedCache.swift`; `Jason/Jason/Database/Folders/DatabaseManager+HeavyFolderManagement.swift`; `Jason/Jason/JasonApp.swift:42-47`

- [ ] **5. No database migration system — every future schema change breaks existing users** ✅
  - **What:** Schema is built only with `CREATE TABLE IF NOT EXISTS`; there is **no `PRAGMA user_version` and no `ALTER TABLE` anywhere** in the app.
  - **Why:** For anyone who already has `Jason_01.db`, `IF NOT EXISTS` is a no-op, so any column added in a later release never gets added → runtime `no such column` errors → features silently break or data silently fails to save on upgrade. Shipping-blocker for any schema change.
  - **Fix:** Add `user_version`-based migrations run at open (ordered `ALTER TABLE ... ADD COLUMN` steps in a transaction, then bump the version).
  - **Location:** `Jason/Jason/Database/DatabaseManager.swift:75-361`

- [ ] **6. Clipboard history stores secrets in plaintext** *(privacy/security)*
  - **What:** `ClipboardManager.checkForChanges()` captures every pasteboard change and persists it unencrypted to SQLite, with **no check for `org.nspasteboard.ConcealedType`/transient types** (verified: no such string anywhere in the codebase).
  - **Why:** Password managers mark copied secrets `ConcealedType` so clipboard tools skip them. Jason captures and stores passwords/TOTP codes in an unencrypted DB in an **un-sandboxed** app (readable by any process running as the user), capped at 200 entries so they linger.
  - **Fix:** Skip concealed/transient pasteboards; consider encryption + a retention setting.
  - **Location:** `Jason/Jason/Providers/Clipboard/ClipboardManager.swift:165-201`

- [ ] **7. Crash-prone force-subscripts / force-unwraps on live-updating state**
  - **What:**
    - `Jason/Jason/UI/Circular View/RingView.swift:256` — `nodes[selectedIndex]` with no bounds check ✅ (the file itself logs "OUT OF BOUNDS" for this same index elsewhere)
    - `Jason/Jason/Providers/RemindersProvider.swift` — `findOrDefaultList` → `.first!` when the user has no reminder lists
    - `Jason/Jason/Providers/WindowManagement/WindowManager+Screen..swift` — `NSScreen.screens[0]` / `NSScreen.main` (nil for a menu-bar agent app / sleeping displays)
    - `Jason/Jason/Providers/Apps/AppSwitcherManager.swift` — `runningApps[selectedAppIndex]` while the array mutates on a timer
    - several `reorder*` functions calling `insert(at:)`/`remove(at:)` with caller-supplied indices, no bounds guard
  - **Why:** Each is a hard `Index out of range` / nil-unwrap crash on a reachable path.
  - **Fix:** `guard` the index/optional in each.

---

## 🟠 High — broken features, leaks, UI hangs, data integrity

- [ ] **8. The ring-show path runs heavy work synchronously on the main thread → visible hangs on open**
  - **What:** Opening the launcher synchronously triggers, on main: up to **3 blocking AppleScripts** to Spotify per render (`SpotifyProvider`), Accessibility window enumeration (`FocusedWindowSwitcherProvider`), a full AX tree-walk of *all* running apps (`UI/Logic/DockBadgeReader`), directory enumeration + serial-queue DB reads, and per-file icon rasterization (`lockFocus`).
  - **Why:** Every open can beachball — on the app's most latency-sensitive interaction.
  - **Fix:** Providers return cached state instantly and refresh asynchronously (`FavoriteFolderProvider.loadChildren` already models this well).

- [ ] **9. `MouseTracker` repeating timer retains `self` strongly**
  - **What:** A 20 Hz `Timer` whose closure captures `self` (no `[weak self]`).
  - **Why:** Leaks the tracker (and its object graph) and keeps firing 20×/sec after teardown, mutating ring state invisibly.
  - **Fix:** `[weak self]` + invalidate in teardown.
  - **Location:** `Jason/Jason/Utils/MouseTracker.swift:47-60`

- [ ] **10. Global event taps don't recover when Accessibility is granted after launch**
  - **What:** `HotkeyManager.startMonitoring` checks accessibility *once*; if denied it skips tap creation with no prompt, no observer, no retry. Also the **mouse tap never re-enables** after `kCGEventTapDisabledByTimeout` (the keyboard tap correctly does).
  - **Why:** First-run users grant permission, return, and shortcuts are silently dead until relaunch; mouse shortcuts also die permanently after any system tap-timeout.
  - **Fix:** Use the prompting API, observe the trust change, handle the disable events on both taps.
  - **Locations:** `Jason/Jason/HotkeyManager/HotkeyManager.swift:101-118`; `Jason/Jason/HotkeyManager/HotkeyManager+MouseButtons.swift:74-89`

- [ ] **11. FSEvents watcher uses `passUnretained` → use-after-free window; refresh ops not cancelled on stop/sleep**
  - **What:** `FolderWatcherManager` passes `Unmanaged.passUnretained(self)` as the FSEvents context; teardown can free the `FolderWatcher` while a callback is in flight on the stream's queue. `stopAll` also never calls `refreshQueue.cancelAllOperations()`.
  - **Why:** UAF crash on watcher teardown (widened by the 1s FSEvents latency); orphaned refresh operations keep running against removed folders after sleep/wake.
  - **Fix:** `passRetained` + balanced `release:`; cancel the refresh queue on stop.
  - **Location:** `Jason/Jason/Folder/FolderWatcherManager.swift:366-405,436-449`

- [ ] **12. `@Published` properties mutated off the main thread**
  - **What:** `AppSwitcherManager` assigns `@Published runningApps` and mutates `appUsageHistory` from a timer/notification thread (only the notification *post* is marshalled to main). `RemindersProvider.storeChanged` processes EventKit change notifications without hopping to main.
  - **Why:** SwiftUI requires main-thread publishing; this is a data race that corrupts view state.
  - **Fix:** Marshal all published-property and shared-array mutations to the main actor.

- [ ] **13. Data-integrity bugs**
  - **What:**
    - `auto_execute_on_release` and `created_at` read from the **wrong columns** — both `isModifierHoldMode` and `autoExecuteOnRelease` read column 9 ✅ (`Jason/Jason/Database/Ring Configuration/DatabaseManager+RingTriggers..swift:349-351`).
    - `favorite_folders.sort_order` is an `INTEGER` column but `DatabaseManager+SortOrder.swift:28` writes a **String enum** into it ✅ — corrupts favorites ordering; there's a dedicated `content_sort_order` column it should use.
    - `RingConfigurationManager` calls `updateRingConfiguration` **twice** per edit (first call omits `presentationMode`).
    - Settings rows load icons in a background closure that writes `@State` through a captured **struct** `self` (`FavoriteFilesSettingsView`, `FavoriteAppsSettingsView`) → icons/names silently never appear on recycled rows.
  - **Why:** Triggers misbehave, favorites sort randomly, wasted writes, and a visible "icons don't load" bug.
  - **Fix:** Correct the column indices and target column; remove the duplicate write; move row loading into a reference-type view-model.

- [ ] **14. Transactions left open / not rolled back on error paths**
  - **What:** `SmartCache.saveFolderContents` does `BEGIN`…`COMMIT` with no `ROLLBACK` on the failure path; several `reorder*` functions do multi-row updates with no transaction.
  - **Why:** A failure mid-write leaves a transaction open on the shared serial connection (wedging later writes), or leaves ordering half-rewritten.
  - **Fix:** `ROLLBACK` on every error path; wrap reorders in one transaction.
  - **Location:** `Jason/Jason/Database/Cache/DatabaseManager+SmartCache.swift:203-247`

---

## 🟡 Medium — maintainability, correctness smells, performance

- [ ] **15. 52 `asyncAfter` magic delays used as a synchronization primitive** ✅
  - e.g. the `+1.0`/`+2.0` startup delays in `Jason/Jason/JasonApp.swift` that enforce no real invariant (work is already serialized) but delay launch. Replace timing-based ordering with completion handlers / async-await / explicit readiness flags.

- [ ] **16. God objects + large-scale duplication**
  - `CircularUIInstanceManager` (810 lines; mixes lifecycle + input routing + formatting); ~2,000 lines of near-identical node/drag/context-action logic duplicated between `FavoriteFilesProvider` and `FavoriteFolderProvider`; two ~446-line panel render blocks duplicated between `CircularUIView` and `PanelOnlyView`. Extract shared factories/components — high bug-injection risk today.

- [ ] **17. `FunctionManager.ringConfigurations` is a side-effecting getter**
  - A computed property that triggers async `@Published` mutation, called from the 20 Hz mouse timer and view bodies ("modifying state during view update"). Make it pure; recompute in a `didSet`.
  - **Location:** `Jason/Jason/Ring + Function Manager/Function/FunctionManager.swift:72-111`

- [ ] **18. `String(cString:)` on nullable text columns**
  - Many readers force a non-optional pointer from `sqlite3_column_text` (nil for SQL NULL); some readers already use the safe `.map` idiom. Standardize on the optional form to avoid NULL crashes.

- [ ] **19. `GestureManager` swallows all right/middle clicks app-wide while monitoring**
  - Breaks native context menus / fields inside the app's own windows. Only consume events targeting the overlay window.
  - **Location:** `Jason/Jason/Utils/GestureManager.swift:213-229`

- [ ] **20. `KeyboardShortcutRecorder` leaks its local monitor if the view disappears mid-recording**
  - The monitor then swallows keystrokes app-wide. Add `.onDisappear { stopRecording() }`.
  - **Location:** `Jason/Jason/Utils/KeyboardShortcutRecorder.swift:78-123`

- [ ] **21. Accessibility (AX) robustness**
  - Force-casts (`as!`) of AX results that crash on misbehaving apps (`WindowManager`, `MenuItemExecutor`); reliance on the private `_AXUIElementGetWindow` SPI; suspected multi-display coordinate-flip offset (needs a 2-monitor runtime check). Use `as?`/guards.

- [ ] **22. `PermissionManager` has no prompt or change-detection for Accessibility**
  - Uses `AXIsProcessTrusted()` and just opens System Settings; never prompts or re-checks. Reinforces #10.
  - **Location:** `Jason/Jason/Utils/PermissionManager.swift:294-313`

- [ ] **23. `COUNT(*)`-derived sort orders produce duplicates after deletions**
  - FavoriteApps/Files/DynamicFiles. Use `COALESCE(MAX(sort_order)+1, 0)` as Snippets already does.

---

## 🟢 Nice to have — hygiene, cleanup, polish

- [ ] **24. Logging:** 1,554 `print()` statements ✅ ship in release builds, some logging user content (clipboard text, provider values) and running on hot paths. Move to `os.Logger` with levels gated by a debug flag; stop logging sensitive values.

- [ ] **25. Tests:** there are **zero automated tests** ✅ for 30K LOC — the root cause that let the criticals accumulate. Even a thin suite around the DB layer (binds, migrations) and gesture math would catch the highest-risk regressions. Foundational rather than optional.

- [ ] **26. Git hygiene:** 12 `.DS_Store` files are committed ✅, and `.gitignore` is an **AL / Dynamics-365 Business Central** template ✅ — wrong ecosystem. Replace with a Swift/macOS `.gitignore` and `git rm --cached` the `.DS_Store` files.

- [ ] **27. Dead code:** `CircleGestureExplorer` (a second live multitouch client — a foot-gun if instantiated), the dead `restartAfterWake`/`prepareForSleep` methods, the non-functional swipe handler (`HotkeyManager+Swipes.swift`), a stray `1` after a `case` label in `FunctionModels/FunctionModels.swift:365`, dead branches in `DraggableOverlayView`, duplicated hold-mode clearing, and unused hover callbacks. Remove or `#if DEBUG`-gate.

- [ ] **28. Misc polish:** `NSApplication.relaunch()` uses deprecated `launch()`/`launchPath` and races termination (`JasonApp.swift:191`); filename `WindowManager+Screen..swift` has a double dot; paste actions don't restore the user's prior clipboard; document the security trade-off of the disabled sandbox + library validation (necessary for the private framework, but it precludes Mac App Store distribution).

---

## Strengths (keep doing these)

- **Thorough `teardown()`** in the UI managers — deliberately breaks `NSHostingView → View → @ObservedObject self` retain cycles, removes monitors/observers rather than relying on `deinit`.
- **Consistent `[weak self]`** across stored/escaping closures (162 occurrences).
- **`sqlite3_finalize` discipline** — every prepared statement is finalized on all paths, including error/early-return branches (hard to get right with the raw C API).
- **`FavoriteFolderProvider.loadChildren`** — well-engineered concurrency with `Task.detached` + `Task.checkCancellation()` at every expensive stage; the model the synchronous providers should follow.
- **FSEvents debouncing/coalescing** and `RefreshOperation` cancellation checks + mtime-based thumbnail reuse.
- **EventKit authorization** handled correctly (macOS 14+ APIs with availability checks, completion on main, shared `EKEventStore`).
- **CGEvent tap context passing** done correctly (`Unmanaged.passUnretained` + matching recovery), and the keyboard tap handles `tapDisabledByTimeout`.

---

*Findings marked ✅ were verified directly in the source. A few items (multi-display coordinate flip, exact EventKit notification thread, `MTTouch` struct layout) were flagged by reviewers as needing a runtime check before acting.*
