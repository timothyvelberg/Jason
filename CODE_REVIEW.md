# Jason — Code Review: Remaining Work

**Original review:** 2026-06-23 (full codebase, 164 Swift files, ~30K LOC; 28 ranked items).
**Updated:** 2026-06-25 — completed items removed; this file now tracks only what's left. Original item numbers are kept for traceability (see git history for the implemented fixes).

## Done (no longer listed here)

- **All 🔴 Must-fix (1–7)** and **all 🟠 High (8–14)** — implemented, committed, runtime-verified.
- **🟡/🟢:** #20 (recorder monitor leak), #22 (accessibility prompt), #23 (sort-order `MAX+1`), #26 (git hygiene), #27 (dead code), and the modern-`relaunch()` / filename parts of #28.
- **Two runtime regressions** found during testing were fixed: a multitouch `CFTypeRef` over-release and a Spotify `NSAppleScript` cross-thread race.
- **#19 (GestureManager "swallows clicks")** — assessed and **closed as a non-issue**: the gesture overlay is full-screen so consuming right/middle clicks during it is intended, and the ring hides on focus loss, so other windows aren't reachable underneath.

## Legend

- 🟡 **Medium** — maintainability, correctness smells, performance
- 🟢 **Nice to have** — hygiene, cleanup, polish
- ✅ = verified directly in the source

---

## 🟡 Medium — maintainability, correctness smells, performance

- [ ] **15. 52 `asyncAfter` magic delays used as a synchronization primitive** ✅
  - e.g. the `+1.0`/`+2.0` startup delays in `Jason/Jason/JasonApp.swift` that enforce no real invariant (work is already serialized) but delay launch. Replace timing-based ordering with completion handlers / async-await / explicit readiness flags.
  - Note: many of the 52 sites are load-bearing timing hacks — each needs its underlying race understood, so this is a focused effort, not a blanket find/replace.

- [ ] **16. God objects + large-scale duplication**
  - `CircularUIInstanceManager` (810 lines; mixes lifecycle + input routing + formatting); ~2,000 lines of near-identical node/drag/context-action logic duplicated between `FavoriteFilesProvider` and `FavoriteFolderProvider`; two ~446-line panel render blocks duplicated between `CircularUIView` and `PanelOnlyView`. Extract shared factories/components — high bug-injection risk today.

- [ ] **17. `FunctionManager.ringConfigurations` is a side-effecting getter**
  - A computed property that triggers async `@Published` mutation, called from the 20 Hz mouse timer and view bodies ("modifying state during view update"). Make it pure; recompute in a `didSet`.
  - **Location:** `Jason/Jason/Ring + Function Manager/Function/FunctionManager.swift:72-111`
  - Note: core hot path — verify ring rendering carefully after the change.

- [ ] **18. `String(cString:)` on nullable text columns**
  - Many readers force a non-optional pointer from `sqlite3_column_text` (nil for SQL NULL); some readers already use the safe `.map` idiom. Standardize on the optional form to avoid NULL crashes. Pervasive but mechanical.

- [ ] **21. Accessibility (AX) robustness**
  - Force-casts (`as!`) of AX results that crash on misbehaving apps (`WindowManager`, `MenuItemExecutor`) → use `as?`/guards; reliance on the private `_AXUIElementGetWindow` SPI; suspected multi-display coordinate-flip offset (needs a 2-monitor runtime check).

---

## 🟢 Nice to have — hygiene, cleanup, polish

- [ ] **24. Logging → `os.Logger`:** ~1,554 `print()` statements ✅ ship in release builds, some logging user content (clipboard text, provider values) and running on hot paths. Move to `os.Logger` with levels gated by a debug flag; stop logging sensitive values.

- [ ] **25. Automated tests:** there are **zero automated tests** ✅ for ~30K LOC — the root cause that let the criticals accumulate. Even a thin suite around the DB layer (binds, migrations) and gesture math would catch the highest-risk regressions. Net-new test target.

- [ ] **28. Misc polish (remaining):** paste actions don't restore the user's prior clipboard; document the security trade-off of the disabled sandbox + library validation (necessary for the private `MultitouchSupport` framework, but it precludes Mac App Store distribution).

- [ ] **A1. AppleScript hardening (follow-up from the Spotify crash fix):** `NSAppleScript` is not thread-safe. Spotify's scripts are now serialized on one queue, but `FavoriteFilesProvider.showInfo` still runs `NSAppleScript` on the main thread — so it could race a Spotify refresh if music is playing while you trigger "Get Info" on a file. Route **all** app `NSAppleScript` through one shared serial queue to fully close the hazard.
