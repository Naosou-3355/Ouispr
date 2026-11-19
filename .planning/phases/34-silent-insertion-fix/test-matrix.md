---
phase: 34-silent-insertion-fix
artifact: manual-verification
requirement: STAB-01
status: in-progress
created: 2026-04-15
---

# Phase 34 — Manual Verification Test Matrix

> Artifact that formally closes STAB-01. Referenced from the fix PR description
> and from issue #118 when we mark it resolved.
>
> **Evidence discipline:** every PASS/FAIL entry cites a `keyboardInsertProbe`
> / `keyboardInsertRetry` / `keyboardInsertFailed` log line. No raw
> transcription text is ever pasted — logs contain counts/booleans/timings only
> (enforced in Plan 01, verified in LogPrivacyTests).
>
> **Device:** real iPhone running the build that ships plans 01 + 02 + 03.
> Simulator does NOT count — `textDocumentProxy` behaves differently and the
> bug is real-device-only per issue #118.

---

## 50-Run Protocol

**Goal:** 50 consecutive real-device dictations with zero silent drops
(STAB-01 success criterion #1).

**Target apps (rotate across the 50 runs):**
- Notes — long existing document (non-empty field)
- Notes — new empty note (empty field edge case)
- Messages — chat input (multi-line, autocorrect active)
- Safari — address bar (short field, autocomplete active)

**Scenario distribution across the 50 runs:**
- Runs 01-30: **warm path** — keyboard already up, dictate, wait for insert
- Runs 31-40: **cold start** — force-kill OuisprApp via app switcher before each run
- Runs 41-50: **rapid chained** — 2-3 dictations back-to-back in same app

**Per-run procedure:**
1. Note the `sessionID` (emitted in probe log).
2. Dictate a phrase (≥ 5 words so `transcriptionCount` is non-trivial).
3. Wait for insertion OR failure banner.
4. Export logs via the existing log-dump UX.
5. Record: `PASS` if text landed AND exactly one `keyboardInsertProbe` with
   zero `keyboardInsertRetry`/`keyboardInsertFailed` for that sessionID.
   `FAIL` otherwise.
6. Privacy check (spot-check every 10 runs): grep the exported log for a
   distinctive dictated word. Expected: ZERO hits.

**Pass bar:** 50/50 PASS. Any FAIL is a blocker — diagnose, fix, rerun
the entire 50-run protocol. Partial success does not close STAB-01.

---

## #118 Repro Matrix

**Goal:** every scenario originally reported in issue #118 now produces a
visible outcome (success OR loud-fail UX) — no silent drops (STAB-01 success
criterion #2).

| # | Scenario | Steps | Expected | Result | Log Evidence |
|---|----------|-------|----------|--------|--------------|
| 1 | Warm same-app dictation | Keyboard already up in Notes, dictate short phrase | Text lands, 1× probe `path=warmDarwin attempt=0` | ⬜ pending | — |
| 2 | Cold start | Force-kill OuisprApp, open Messages, tap mic, dictate | Text lands, 1× probe `path=coldStartBridge attempt=0` | ⬜ pending | — |
| 3 | Backgrounded keyboard | Switch app while dictation in flight, return | Either text lands OR banner+DI failure + home card updated | ⬜ pending | — |
| 4 | Rapid chained recordings | Three back-to-back dictations in Notes | 3× text landed, 3× probe entries with distinct sessionIDs | ⬜ pending | — |

---

## 3-Path Regression Checklist

**Goal:** confirm each of the three insertion code paths is exercised by the
new helper and observed in logs (STAB-01 success criterion #3).

| Path | How exercised | Expected log signature | Result | Notes |
|------|---------------|------------------------|--------|-------|
| warm Darwin | Keyboard up when Darwin notification arrives | `keyboardInsertProbe path=warmDarwin` | ⬜ pending | — |
| cold start Audio Bridge | OuisprApp killed, keyboard bridges via URL scheme, Darwin arrives post-wake | `keyboardInsertProbe path=coldStartBridge` | ⬜ pending | — |
| chained recording | Second dictation starts before first state fully resets | `keyboardInsertProbe` with two distinct `sessionID` values in quick succession | ⬜ pending | — |

---

## Results Log

**Device:** <fill in: iPhone model + iOS version>
**Build:** <fill in: version + build number from Info.plist>
**Tester:** <fill in: name>
**Date window:** <fill in: start — end>

| Run | App | Scenario | sessionID | transcriptionCount | darwinToInsertMs | Result | Evidence |
|-----|-----|----------|-----------|--------------------|------------------|--------|----------|
| 01 | — | warm | — | — | — | ⬜ pending | — |
| 02 | — | warm | — | — | — | ⬜ pending | — |
| 03 | — | warm | — | — | — | ⬜ pending | — |
| 04 | — | warm | — | — | — | ⬜ pending | — |
| 05 | — | warm | — | — | — | ⬜ pending | — |
| 06 | — | warm | — | — | — | ⬜ pending | — |
| 07 | — | warm | — | — | — | ⬜ pending | — |
| 08 | — | warm | — | — | — | ⬜ pending | — |
| 09 | — | warm | — | — | — | ⬜ pending | — |
| 10 | — | warm | — | — | — | ⬜ pending | — |
| 11 | — | warm | — | — | — | ⬜ pending | — |
| 12 | — | warm | — | — | — | ⬜ pending | — |
| 13 | — | warm | — | — | — | ⬜ pending | — |
| 14 | — | warm | — | — | — | ⬜ pending | — |
| 15 | — | warm | — | — | — | ⬜ pending | — |
| 16 | — | warm | — | — | — | ⬜ pending | — |
| 17 | — | warm | — | — | — | ⬜ pending | — |
| 18 | — | warm | — | — | — | ⬜ pending | — |
| 19 | — | warm | — | — | — | ⬜ pending | — |
| 20 | — | warm | — | — | — | ⬜ pending | — |
| 21 | — | warm | — | — | — | ⬜ pending | — |
| 22 | — | warm | — | — | — | ⬜ pending | — |
| 23 | — | warm | — | — | — | ⬜ pending | — |
| 24 | — | warm | — | — | — | ⬜ pending | — |
| 25 | — | warm | — | — | — | ⬜ pending | — |
| 26 | — | warm | — | — | — | ⬜ pending | — |
| 27 | — | warm | — | — | — | ⬜ pending | — |
| 28 | — | warm | — | — | — | ⬜ pending | — |
| 29 | — | warm | — | — | — | ⬜ pending | — |
| 30 | — | warm | — | — | — | ⬜ pending | — |
| 31 | — | cold start | — | — | — | ⬜ pending | — |
| 32 | — | cold start | — | — | — | ⬜ pending | — |
| 33 | — | cold start | — | — | — | ⬜ pending | — |
| 34 | — | cold start | — | — | — | ⬜ pending | — |
| 35 | — | cold start | — | — | — | ⬜ pending | — |
| 36 | — | cold start | — | — | — | ⬜ pending | — |
| 37 | — | cold start | — | — | — | ⬜ pending | — |
| 38 | — | cold start | — | — | — | ⬜ pending | — |
| 39 | — | cold start | — | — | — | ⬜ pending | — |
| 40 | — | cold start | — | — | — | ⬜ pending | — |
| 41 | — | chained | — | — | — | ⬜ pending | — |
| 42 | — | chained | — | — | — | ⬜ pending | — |
| 43 | — | chained | — | — | — | ⬜ pending | — |
| 44 | — | chained | — | — | — | ⬜ pending | — |
| 45 | — | chained | — | — | — | ⬜ pending | — |
| 46 | — | chained | — | — | — | ⬜ pending | — |
| 47 | — | chained | — | — | — | ⬜ pending | — |
| 48 | — | chained | — | — | — | ⬜ pending | — |
| 49 | — | chained | — | — | — | ⬜ pending | — |
| 50 | — | chained | — | — | — | ⬜ pending | — |

---

## Summary

**50-Run result:** <fill in: X/50 PASS>
**#118 Repro Matrix:** <fill in: X/4 PASS>
**3-Path Regression:** <fill in: X/3 PASS>
**Privacy audit:** <fill in: PASS/FAIL — zero raw-text leaks in logs>

**STAB-01 status:** <fill in: resolved | blocked | partial — reason>
