# Tasks: Manage Claude Logins

## Review Workload Forecast

| Field | Value |
|---|---|
| Initial whole-change estimate (superseded) | 1,430–1,845; use the current per-unit forecasts below. |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | Units 1 → 2 → 3A → 3B1 → 3B2 → 3B3 → 4 → 5 |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Tasks / likely PR | Exact edit roots | Start → finish; test / harness / rollback |
|---|---|---|---|
| 1 | 1.1–1.4 / PR 1 → main | `Sources/AIControlCore/ScopedJSON.swift`, `Sources/AIControlCore/ClaudeLoginManager.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Nothing → snapshot API; `./scripts/test --filter ClaudeLoginManagerTests` RED fails then GREEN passes; N/A pure; revert these files. |
| 2 | 2.1–2.3 / PR 2 → main | `Sources/AIControl/AIControlMain.swift`, `Sources/AIControlCore/ClaudeLoginManager.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | GUI → doubled save/list; `./scripts/test --filter ClaudeLoginManagerTests` passes; synthetic argv; revert dispatcher/enrollment. |
| 3A | 3.1–3.3 / PR 3A → main | `Sources/AIControlCore/ClaudeLoginIO.swift` (new adapter only), `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | U2 unavailable backend → isolated testable adapter, production still unavailable; focused RED→GREEN/pure suite plus explicitly opt-in synthetic G2; remove adapter/new tests without touching real Keychain. |
| 3B1 | 3.4–3.6 / PR 3B1 → main | `Sources/AIControlCore/ClaudeLoginIO.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | U3A adapter → bounded/scoped file persistence, unused by production; focused RED→GREEN plus disposable-file preservation/failure/cleanup harness; remove new file boundary/tests only. |
| 3B2 | 3.7–3.9 / PR 3B2 → main | `Sources/AIControlCore/ClaudeLoginIO.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | U3B1 file boundary → manager lock/routing/process guards, production unavailable; focused RED→GREEN plus isolated lock/injected process fixtures; revert guards/tests only, retain U3A/U3B1. |
| 3B3 | 3.10–3.12 / PR 3B3 → main | `Sources/AIControlCore/ClaudeLoginIO.swift`, `Sources/AIControlCore/ClaudeLoginManager.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | U3B1/B2 guards + U3A adapter → validated envelope custody/guarded backend composition; focused RED→GREEN plus synthetic enrollment/readback integration; revert codec/custody/composition/tests, retain primitives and unavailable default. |
| 4 | 4.1–4.2 / PR 4 → main | `Sources/AIControlCore/ClaudeLoginManager.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | A/B → A2 selection/pending journal; `./scripts/test --filter ClaudeLoginManagerTests` passes; synthetic A2 → B → A; revert selection only. |
| 5 | 4.3–4.6 / PR 5 → main | `Sources/AIControlCore/ClaudeLoginManager.swift`, `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Pending journal → recovery/gates; `./scripts/test` passes; synthetic relaunch/G5 deferred; revert recovery only. |

## Phase 1: Typed Storage Foundation

- [x] 1.1 [U1] RED: add duplicate-key, large-integer, presence, sentinel, and dead-marker cases in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`; expect `./scripts/test --filter ClaudeLoginManagerTests` to fail.
- [x] 1.2 [U1] GREEN: create narrow raw-span `Sources/AIControlCore/ScopedJSON.swift`, not a general parser; reject malformed/duplicate input and preserve owned boundaries.
- [x] 1.3 [U1] RED: add presence-tagged snapshot/envelope cases in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`; expect the focused command to fail.
- [x] 1.4 [U1] GREEN: create `Sources/AIControlCore/ClaudeLoginManager.swift` snapshot models preserving opaque subtrees, identity agreement, and re-login-needed; expect the focused command to pass.

## Phase 2: Terminal Enrollment

- [x] 2.1 [U2] RED: prove malformed/no-argument zero IO plus two aliases, collision, manual-B, and secret-free status in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`.
- [x] 2.2 [U2] GREEN: add CLI/doubled enrollment in `Sources/AIControlCore/ClaudeLoginManager.swift`; route it in `Sources/AIControl/AIControlMain.swift` without GUI change.
- [x] 2.3 [U2] REFACTOR: follow `strict-tdd.md` (read-only); retain safe CLI diagnostics in `Sources/AIControlCore/ClaudeLoginManager.swift`.

## Phase 3: Isolated Adapter, Then Guarded Integration

Historical revision 6 scope: “Dividir en dos” replaced the earlier U3 800-line exception with two ≤400-line units, not automatic partition iteration; remaining U3B is superseded below. U3A excluded Manager/Main/ScopedJSON edits; task checkboxes and apply-progress evidence change only during implementation. No live production activation until all protections are complete; G5 remains separately authorized.

Historical revision 6 forecast (not measured): original U3 488–768 lines; U3A adapter 110–160, tests/harness ~90–140, total ~240–360 including bounded metadata/progress. That revision's planning edits counted toward U3A's 400-line budget. Unsplit U3B's ≤400 estimate was not defensible; the supplied current assessment below replaces it without reviving an exception.

Revision 7 human checkpoint: “Replantear con 400 líneas” authorizes this single new bounded planning pass before any future acquire, not repeated automatic slicing. Accept U3B1 → U3B2 → U3B3 as cohesive ≤400-line scopes, tests with owning code; no code compression or new features. Source inspection/research is not expanded. If a scope's upper estimate ceases to be defensible, stop and flag the required human decision rather than iterate or assume 800 lines.

| Remaining scope | Changed-line forecast (estimates, not measurements) |
|---|---|
| Unsplit U3B | 525–795 (~530–800), from the supplied verified assessment; not a permitted unit. |
| U3B1 | 180–260 file code/tests + 25–45 bounded input admission/tests + 10–15 evidence = 215–320 before this planning diff; reserve ≤60 metadata lines, ceiling 380/400. All this pass's metadata is charged here. |
| U3B2 | 130–205 source + 90–135 tests + ~15 evidence = 235–355/400. |
| U3B3 | 70–105 source + 50–75 tests + 80–150 explicit codec/ACL-composition gap allowance (including tests) + 10–15 evidence = 210–345/400; native permission compatibility remains unverified. |

Recorded U3A evidence, not a new run: 371 authored lines, 38/38 full pure tests and 1/1 opt-in native test passed (`apply-progress.md`). Parent-confirmed review disposition: U1 approved; U2/U3A explicitly omitted, not approved. Earlier lifecycle snapshots are historical, not current runtime authority.
Verification for each new unit: focused `./scripts/test --filter ClaudeLoginManagerTests` RED before GREEN, then `./scripts/test`; record exact results and the unit's synthetic harness/cleanup during implementation. Ordinary suites never implicitly create a Keychain; no real Claude credentials/configuration or live G5 are authorized. U3B1/B2 keep the default backend unavailable; final composition cannot activate production before every protection is complete and verified.
U3B1 and U3B2 only: the maintainer accepted a local `size:exception` of 450 total authored lines; all other unit budgets remain 400.

- [x] 3.1 [U3A] RED: in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`, prove exact generic-password service/account + explicit isolated-Keychain queries, unique persistent-reference selection, create/read/data-only update/delete, and missing/duplicate/ambiguous/denied/cancelled/locked/corrupt error handling; fail before GREEN, with no default-Keychain fallback or Claude-service reads.
- [x] 3.2 [U3A] GREEN: create only the injected native adapter in `Sources/AIControlCore/ClaudeLoginIO.swift`; update exact persistent references without delete/re-add, preserving attributes/ACL and opaque data. Delete only synthetic items for CRUD/cleanup; leave the current production backend unavailable.
- [x] 3.3 [U3A] Verify RED→GREEN and exact CRUD readback/cleanup under an explicitly opt-in synthetic G2 run using a temporary isolated Keychain and fictitious `AIControl-claude-logins.v1.test-*` items; document the already-approved phase-only side effects, command/results, and cleanup even on failure. Normal focused/full pure suites must not implicitly create a Keychain. Distinguish native ACL/denied evidence from fake errors; passing CRUD alone does not satisfy all G2.
- [x] 3.4 [U3B1] RED: add bounded size/depth admission, raw-span/large-number/duplicate preservation, owner/mode/ACL, symlink/content/identity/protection change, and write-failure/cleanup cases in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` before file implementation.
- [x] 3.5 [U3B1] GREEN: add only the unused file boundary in `Sources/AIControlCore/ClaudeLoginIO.swift`; bound bytes/depth before invoking existing `ScopedJSON`, patch latest owned spans, use protected same-directory temp/fsync/rename/fsync, recheck identity/content/protections, and verify preservation/cleanup. No Manager/Main/ScopedJSON source edits, process/flock, or production integration.
- [x] 3.6 [U3B1] Verify disposable-file preservation, permission refusals and injected failure boundaries/cleanup with focused/full tests; distinguish native filesystem/ACL evidence from doubles. Keep production unavailable; rollback removes only the unused file boundary and its tests.
- [x] 3.7 [U3B2] RED: add contention, symlink/permission, W5 routing/hash/default-resolver rejection, and UID/executable/ancestry active-or-uncertain process fixtures proving fail-closed zero-write preflight in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`.
- [x] 3.8 [U3B2] GREEN: add descriptor-held per-user flock (0700 directory/0600 file), W5 routing validation and injected native process probe in `Sources/AIControlCore/ClaudeLoginIO.swift`; retain every design rejection rule and before-write/after-verification guard contract. Reuse U3B1 without activating production; no Manager/Main/ScopedJSON source edits.
- [x] 3.9 [U3B2] Verify isolated lock lifecycle/cleanup and injected terminal/editor/SDK/daemon/Remote Control ancestry/uncertainty cases with focused/full tests; retain operator launch prevention and non-cooperating startup/check-write race limitations, never claim guaranteed exclusion. Rollback guards/tests only.
- [ ] 3.10 [U3B3] RED: test bounded serialized envelope v1 validation, presence/opaque data, identity-safe two-alias enrollment, custody/readback failures, safe diagnostics, and guard composition before integration in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`; preserve all existing CLI/enrollment behavior.
- [ ] 3.11 [U3B3] GREEN: compose envelope codec/custody, exact Keychain persistent-reference data-only updates and local nonsynchronizing UID/approved-binary ACL policy in `Sources/AIControlCore/ClaudeLoginIO.swift`; integrate the guarded backend in `Sources/AIControlCore/ClaudeLoginManager.swift` only after U3B1/B2 exist. List reads manager state only; absent state lists empty, only save creates it; retain identity/usability and unresolved-journal refusal rules. U4 selection/U5 recovery stay excluded.
- [ ] 3.12 [U3B3] Verify synthetic enrollment/readback and every guard's zero-write refusal with focused/full tests; distinguish codec/fake-denial coverage from unverified native ACL/signing/denied compatibility. Use Keychain fixtures only with explicit bounded synthetic authorization; CRUD alone never completes G2. Keep the default unavailable while any protection is incomplete/unverified; no actual Claude credential access or live G5. Rollback composition/tests, retaining safe unused primitives.

## Phase 4: Selection, Recovery, and Gates

- [ ] 4.1 [U4] RED: add A2 → B → A, cache removal, preservation, and interruption cases in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`.
- [ ] 4.2 [U4] GREEN: implement journal-first selection, latest checkpoint, verification, alias-last commit, and pending-journal retention in `Sources/AIControlCore/ClaudeLoginManager.swift`; recovery is U5.
- [ ] 4.3 [U5] RED: add restart recovery, third-value refusal, unresolved-journal blocking, and recovery-only writes in `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`.
- [ ] 4.4 [U5] GREEN: implement latest-root owned-field recovery and verified cleanup in `Sources/AIControlCore/ClaudeLoginManager.swift`; retain recovery-required on uncertainty.
- [ ] 4.5 [U5] Record G1/G3/G4 from `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` using `./scripts/test`; leave G2 pending without native authorization.
- [ ] 4.6 [U5] Keep G5 deferred until explicit live authorization; then prove fresh-session A → B → A, checkpoint, re-login-needed, and rollback before any live claim.
