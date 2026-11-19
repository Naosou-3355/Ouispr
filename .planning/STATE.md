---
gsd_state_version: 1.0
milestone: v1.7
milestone_name: Stability, Polish & i18n
status: manual-mode
stopped_at: "GSD process paused — milestone continues with manual issue-by-issue workflow on develop. Phase 34/34.1 reverted (fix worsened #118). Phase 35 shipped manually via PRs #116/#117/#128/#129/#130."
last_updated: "2026-04-22"
last_activity: "2026-04-22 — Project check-in: confirmed GSD paused, Phase 35 closed manually, next focus TBD"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 0
  completed_plans: 0
  percent: 17
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-15)

**Core value:** A user can dictate text in French in any iOS app and correct it immediately on the same keyboard -- no subscription, no cloud, no account.
**Current focus:** Milestone v1.7 — Stability, Polish & i18n. GSD process paused; milestone continues manually issue-by-issue on `develop`.

## Process Status: GSD PAUSED (manual mode)

**Why:** GSD process broke more than it shipped on Phase 34 (see Phase 34 revert below) and consumed too many tokens for the result quality. User prefers the phase structure as a mental model but executes issues directly via PRs against `develop`, without PLAN/RESEARCH/VERIFICATION artifacts.

**How work is tracked now:**
- GitHub issues = source of truth for what needs doing
- Phases in ROADMAP.md = coarse grouping only, closed manually when their issues are closed
- No new phase directories under `.planning/phases/` unless the work is genuinely multi-plan

## Current Position

Milestone: v1.7 (in progress, manual mode)

Phases in v1.7:
- ❌ Phase 34 / 34.1 — Silent Insertion Fix — **REVERTED 2026-04-20** (PR #127). Fix made #118 ~20× worse (1/200 → 1/10). Issue #118 remains OPEN and deprioritized; future retry must start diagnostic-only.
- ✅ Phase 35 — Keyboard Geometry Polish — **CLOSED manually 2026-04-22**. Shipped via PRs #117 (align row height/position), #116 (remove KeyboardRootView fallback path, layout glitch fix), #128 (status handler controller gating), #129 (inputView height constraint), #130 (keyboard layout glitch merged).
- ⏳ Phase 36 — Autocorrect v2 (#114) — not started
- ⏳ Phase 37 — Whisper Turbo retest (#104) — not started
- ⏳ Phase 38 — i18n Foundation (#110) — not started
- ⏳ Phase 39 — German Support (#109) — not started

Last activity: 2026-04-22 — Project check-in, GSD state reconciled with reality.

## Performance Metrics

**Velocity:**
- v1.0: 18 plans in 4 days
- v1.1: 29 plans in 5 days
- v1.2: 35 plans in 17 days
- v1.3: 14 plans in 11 days
- v1.4: 15 plans in 7 days
- Total: 111 plans across 5 milestones in 35 days

## Accumulated Context

### Decisions

All prior decisions logged in PROJECT.md Key Decisions table.

**v1.7 roadmap decisions:**
- Phase numbering starts at 34 to avoid collision with v1.5 Ouispr Pro premium worktree (phases 30-33).
- STAB-01 isolated in Phase 34 so the silent insertion bug can ship as a hotfix independent of heavier keyboard/autocorrect/i18n work.
- KBD-01 + KBD-02 bundled in Phase 35 because both target keyboard geometry and the audit (KBD-01) drives the glitch fix (KBD-02).
- AUTO-01 + AUTO-02 + AUTO-03 bundled in Phase 36 — AOSP LatinIME alignment is a single coherent architectural change, splitting would cause rework.
- I18N-01 (Phase 38) scheduled before I18N-02 (Phase 39) — German is the first validation of the i18n process, not an independent feature.

**Phase 34 execution decisions (Plan 34-01):**
- Use `xcodebuild test -scheme OuisprCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` for OuisprCore tests, NOT `swift test --package-path OuisprCore` — the package is iOS-only (UIKit, ActivityKit, iOS 26 SwiftUI APIs) and does not compile for macOS. Plans 34-02/03/04 should use the same command.
- Pre-existing `AccentedCharacterTests` + `FrequencyDictionaryTests` failures on `develop` documented in `.planning/phases/34-silent-insertion-fix/deferred-items.md` and deferred to a future cleanup issue — out of STAB-01 scope.
- `InsertionClassifier` shipped as an `enum` (static-function namespace) — pure policy, no stored state, no allocator churn when called per-insertion-attempt.

**Phase 34 execution decisions (Plan 34-02):**
- HomeView `recoverableTranscription` uses 300s staleness window reusing DictationCoordinator.swift:97-102 cutoff — single-sourced contract for "fresh transcription".
- Scene-active refresh uses `@State Int` bump + `_ = appGroupRefreshTrigger` read pattern to force SwiftUI to re-evaluate the computed property on scene activation without wrapping the App Group read in a full ObservableObject.
- **Contract for Plan 34-03:** the failed-insertion escalation path MUST NOT call `defaults.removeObject(forKey: SharedKeys.lastTranscription)` — current clear at `OuisprKeyboard/KeyboardState.swift:338` is correct for success path only. Preserving the App Group key on failure is what lets HomeView's recovery surface (Plan 34-02) surface the lost text.

**Phase 34 execution decisions (Plan 34-03):**
- `InsertTranscriptionHelper` is the single wrapper for every `textDocumentProxy.insertText` call originating from transcription ready. Validates controller / hasFullAccess / document context; inserts; verifies via `InsertionClassifier` (utf16 delta + `proxy.hasText` transition); retries up to 3× with 50/100/200ms backoff; escalates on terminal failure.
- Failure contract honored: terminal-failure path **re-writes** `SharedKeys.lastTranscription` so HomeView's recovery surface (Plan 34-02) can show the card. Success path still clears (existing duplicate-prevention behavior preserved).
- Loud-fail UX: FR/EN red banner in ToolbarView with 4s auto-clear + `HapticFeedback.insertionFailed()` + `keyboardInsertFailed` log. Banner does not stomp newer messages.
- Privacy-safe telemetry: `keyboardInsertProbe` / `keyboardInsertRetry` / `keyboardInsertFailed` contain only integers (counts, timings), booleans (hasFullAccess, hasText*), and labels (path=warmDarwin|coldStartBridge). Real-device log audit (9 insertions, 892-line log): zero raw transcription text in any probe — **privacy audit PASS**.
- Delta math verified: across 9 real-device insertions, `beforeCount + transcriptionCount = afterCount` exactly on every probe — classifier correctly returns `.success`.

**Phase 34.1 execution decisions (Plan 34.1-01):**
- `InsertionClassifier.classify` rewritten with 7-rule success-first priority per CONTEXT D1. Rule 1 (hasTextBefore=false && hasTextAfter=true → `.emptyFieldSuccess`) is authoritative regardless of nil context; Rule 4 treats negative delta with hasTextAfter=true as `.windowedSuccess` (iOS window truncation); Rule 6 narrows `.silentDrop` to `delta==0 && 0<beforeCount<400 && hasText unchanged`. Default (Rule 7) falls through to `.windowedSuccess` — no more ambiguous `.deltaMismatch`.
- `.proxyDead` and `.deltaMismatch` enum cases retained as dead-but-unreachable (source-compat only) — avoids cascading exhaustive-switch refactor across `InsertTranscriptionHelper` and `LogEvent` that properly belongs to Plan 34.1-02 (retry loop removal). Tests prove classifier never returns them.
- **Verification command change:** OuisprCore scheme at project root no longer has a working `TestAction` (the `Ouispr.xcodeproj/xcshareddata/xcschemes/` directory is currently untracked). Fix: created `OuisprCore/.swiftpm/xcode/xcshareddata/xcschemes/OuisprCore-Package.xcscheme` and run tests via `cd OuisprCore && xcodebuild test -scheme OuisprCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OuisprCoreTests/InsertionClassifierTests`. Plans 34.1-02/03 must use this command.
- Pre-existing 10 failures in `AccentedCharacterTests` + `FrequencyDictionaryTests` remain — deferred per `.planning/phases/34-silent-insertion-fix/deferred-items.md`, out of STAB-01 scope.

**Phase 34.1 execution decisions (Plan 34.1-02):**
- `InsertTranscriptionHelper` rewritten as single-shot: validate → insert → classify → log → route outcome, all synchronous, zero retries. 189 → 155 lines. Exactly one physical `proxy.insertText` call per invocation. `scheduleNextOrFail` + nested `attempt(_ index:)` + `DispatchQueue.main.asyncAfter` backoff loop all deleted.
- `InsertionFailureReason` trimmed from 6 cases to 4 (dropped `.deltaMismatch` + `.proxyDead`). Classifier never emits the corresponding outcomes per Plan 34.1-01, so exposing them in the failure enum was misleading. Helper's outcome switch still pattern-matches `.deltaMismatch, .proxyDead` as a defensive fallback to `.success` (benefit-of-doubt policy — if a future classifier regression reintroduces those outcomes, degradation mode is "missing telemetry" not "false user-visible failure").
- `InsertTranscriptionResult.success` dropped `attempts: Int` (always 1 under single-shot; misleading signal). `keyboardInsertProbe` LogEvent still carries `attempt: 0` hardcoded for log-parser compatibility.
- `KeyboardState.dispatchInsertion` failure branch reduced to telemetry-only: dropped `statusMessage` banner write, dropped `HapticFeedback.insertionFailed()` call, dropped `escalateInsertionFailure` helper entirely (function deleted, not just call site). Plan 34-02 recovery contract preserved: `.failed` still re-writes `SharedKeys.lastTranscription` + timestamp so HomeView recoverableTranscription surfaces lost text.
- No `LiveActivityManager` references found in `KeyboardState.swift`. Plan listed LiveActivity `.failed` transition as one of three side-effects to remove — already satisfied (none existed in this file).
- 100ms App Group propagation retry in `handleTranscriptionReady` kept (distinct concern from insertion retry — polls UserDefaults for transcription value that may lag ~100ms post-synchronize on-device).
- **Git note:** commits `42b8454` (helper) and `9a1a81c` (call site) are semantically inseparable but split for review clarity. Intermediate state between them does not compile because `InsertTranscriptionResult` associated-value signatures changed. Final state builds clean.

**Phase 34.1 execution decisions (Plan 34.1-03):**
- On-device verification session 2026-04-16T12:22:08Z → 12:25:54Z on iPhone iOS 26.3.1 (App 1.6.0 build 10, Parakeet model). 13 `keyboardInsertProbe` probes observed, 0 `keyboardInsertFailed` events. All 3 regression categories exercised: 2x emptyFieldSuccess, 1x long field `beforeCount=658`, 3x nil-context (`beforeCount=-1`) benefit-of-doubt windowedSuccess.
- **Privacy audit PASS** — 7 grep patterns (message=, transcription= non-Count, content=, result=, text= non-Count, keyboardInsertFailed, banner/insertionFailed/showError/redBanner) returned 0 hits across 1277-line session log. Plan 34-03 → 34.1-02 privacy-safe telemetry contract preserved in real-device conditions.
- **Accepted 13 probes as PASS (target was 15).** All 6 explicit Pass Criteria tick at 13, full category coverage achieved, 0/13 failures, user signed off explicitly ("C'est tout bon, j'ai pas eu de soucis particuliers"). Documented as informational shortfall in device-verification.md, not a gap.
- **Cold-start (`path=coldStartBridge`) not exercised this session — not a Phase 34.1 blocker.** All 13 probes `path=warmDarwin`. Classifier is path-agnostic (operates purely on delta/beforeCount/hasText tuple — does not read `path` label), so warmDarwin and coldStartBridge run identical logic. Logged as follow-up coverage gap for production monitoring; cold-start reliability is a separate OPEN issue independent of insertion-detection simplification.
- **Side-observation:** 3/13 probes (23%) had `documentContextBeforeInput == nil` — under Plan 34-03 these would have been `.proxyDead` false-failures (~23% failure rate on this session). The pre-fix regression base rate was measurably frequent, confirming Phase 34.1 was the right corrective path.
- **Classifier outcomes inferred by rule-replay, not probe-instrumented.** Probe payload is counts/bools/labels only (privacy contract) — outcomes were derived by applying the 7 rules from `InsertionClassifier.classify` against each probe's tuple. Deterministic since classifier is pure. Sufficient evidence for STAB-01 verification without widening probe surface.

### Roadmap Evolution

- Phase 34.1 inserted after Phase 34 (2026-04-16): **Simplify insertion detection — telemetry-only, no retries, no UI escalation.** Real-device testing revealed Plan 34-03 introduced 3 observable regressions: (1) false-positive failures from classifier treating nil `documentContextBeforeInput` as `.proxyDead` when `hasText` had transitioned false→true (genuine empty-field success); (2) false-positive failures from negative-delta readings when iOS truncates `documentContextBeforeInput` window on long host fields; (3) retries blindly re-inserting on false failures, causing duplicate text insertion; (4) UX bug: red banner visually truncated in ToolbarView. User reported base rate of real #118 silent failures is ~1-in-hundreds, net UX regression. Simplification path: fix classifier, drop retries, drop banner+haptic+LiveActivity `.failed`, keep probe telemetry (privacy-audited zero-leak) + App Group preservation-on-failure for HomeView recovery surface.

### Known Gaps (non-blocking for Phase 34)

- **LiveActivity state machine — missing `.recording → .failed` edge.** Plan 34-01 added `.standby → .failed` and `.ready → .failed` but not `.recording → .failed`. Real-device logs showed one `liveActivityFailed context=rejectedTransition error=recording->failed` at 07:43:48 on a very short recording (sampleCount=6404 ≈ 0.15s). State machine self-recovered via `recording → standby`. Not blocking STAB-01. Consider adding in a future polish plan.
- **Cold-start insertion path (`path=coldStartBridge`):** not separately observed in Plan 34-03 device session (all probes were `warmDarwin`). Coverage gap for Plan 34-04 manual test matrix to close.
- **Force-fail / #118 reproduction:** bug is intermittent and rare — user could not reproduce during testing. Plan 34-03 ships the capture + recovery infrastructure (probe/retry/failed logs + red banner + App Group preservation + HomeView recovery card). Deferred to long-term monitoring — if bug resurfaces after ship, telemetry + recovery surface are in place.

### Pending Todos

- Adaptive accent key shows apostrophe after "qu" (UI todo from v1.4)

### Known Issues Carried to v1.7

None — BUG-71 fixed via PR #81, BUG-72 fixed via PR #86.

### Parallel Milestone

- **v1.5 Ouispr Pro** in progress on `feature/premium` worktree (Phase 30/33 — 25% done)
- Sync via `sync/develop-to-premium` branch
- v1.7 uses phases 34-39 to avoid collision with premium phases 30-33

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-04-22
Stopped at: GSD paused — manual mode. Phase 35 closed. Next v1.7 target TBD (candidates: Phase 36 Autocorrect v2, Phase 37 Whisper Turbo, Phase 38 i18n).
Resume file: n/a (manual mode — work tracked via GitHub issues)
Next step: User decides next issue to tackle from open list.

---
*State initialized: 2026-03-04*
*v1.0 shipped: 2026-03-07*
*v1.1 shipped: 2026-03-11*
*v1.2 shipped: 2026-03-27*
*v1.3 shipped: 2026-04-07*
*v1.4 shipped: 2026-04-08*
*v1.7 milestone started: 2026-04-15*
*v1.7 roadmap defined: 2026-04-15*
