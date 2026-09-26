# Apply Progress: Manage Claude Logins

## Cumulative State

Current state: whole G/F/L/A/V/O/U5 synthetic proof is complete; supplied parent authority confirms U5 settlement and burned review `review-ab0ffef2900cdee1`. U5-P 205/400, U5-K 394/400, joint 599/800 remain separate from UI. Counts stay 49/54 complete, 5 pending. UI-A adapter proof is complete (see UI-A Correction below); UI-B → FINAL remain; native G2/G5/open-client acceptance and production availability remain unproved.

- Unit 1 (`unit-1-pure-foundation`): tasks 1.1–1.4 complete.
- Unit 2 (`unit-2-terminal-enrollment`): tasks 2.1–2.3 complete; review explicitly declined after the provider issue.
- Mode: Strict TDD. Delivery: auto-chain, stacked-to-main; production credential persistence remains unavailable pending parent verification and the separately authorized native gates.
- U3B1 delivery exception: maintainer-approved `size:exception`, maximum 450 total authored lines; other unit budgets remain 400.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 1.1 | `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Unit | N/A (new files; baseline filter ran 0 tests) | Missing `ScopedJSON` compile failure observed | 5 scoped JSON tests passed | Replacement/removal and missing/null/value paths | Normalized; 9/9 passed |
| 1.2 | same | Unit | N/A (new) | 1.1 tests written first | Raw-span implementation passed | Nested duplicate and unrelated-byte cases | Force unwraps removed; 9/9 passed |
| 1.3 | same | Unit | N/A (new) | Missing snapshot types compile failure observed | 4 snapshot tests passed | Usable, optional, mismatch, and dead paths | Normalized; 9/9 passed |
| 1.4 | same | Unit | N/A (new) | 1.3 tests written first | Snapshot implementation passed | Opaque/presence/identity/usability cases | 9/9 focused and 22/22 full passed |
| 2.1 | same | Unit | 9/9 focused passed | Missing CLI/backend symbols compile-failed | 18/18 passed | Capacity, stale-marker, no-IO, and safe-output paths | 20/20 passed |
| 2.2 | same | Unit + inert executable | 9/9 focused passed | 2.1 tests written first | Array-pattern binding compile failure corrected; injected enrollment/dispatch then passed | First/second/dead/third-alias paths | 20/20 passed |
| 2.3 | same | Unit | 20/20 passed | Approval baseline established by 2.2 | Behavior preserved | Missing/null/nonstring/empty tokens become unusable; `0.0`/`-0`/`0e0` are zero without token reconstruction | 20/20 focused; 33/33 full passed |
| 3.1 | same | Unit | 20/20 focused passed | Missing adapter symbols compile-failed; a test-only ternary type error was corrected before the valid RED rerun | Exact query/error tests passed | Missing, duplicate, ambiguous, corrupt, denied, cancelled, locked, and unknown status paths | 25/25 focused pure suite passed; native test skipped by default |
| 3.2 | same | Unit + native boundary | 3.1 RED established | Exact persistent-reference and data-only behavior tests preceded the adapter | Injected Security adapter passed | Triangulation RED caught `kSecMatchSearchList` on `SecItemAdd`; creation was fixed to use `kSecUseKeychain` | Normalized; 25/25 focused and 38/38 full pure suites passed |
| 3.3 | same | Opt-in native | Pure suites passed with native test skipped | The opt-in harness preceded adapter implementation and remained disabled in pure suites | Explicit isolated harness passed after adapter GREEN | Synthetic CRUD, attribute/search-list preservation, and cleanup were exercised | Cleanup remained deferred and bounded; 1/1 native test passed |
| 3.4 | same | Filesystem integration | 25/25 focused passed; native Keychain skipped | Missing protected-file symbols compile-failed | Five protected-file behaviors passed | Input/output size-depth, UTF-8/duplicate JSON, sentinel, symlink/owner, and race/failure paths | Final 30/30 focused and 43/43 full passed |
| 3.5 | same | Filesystem integration | 3.4 RED established | File-boundary tests preceded implementation | Scoped latest-byte patch and protected atomic replacement passed | Content/identity/protection races plus pre/post-commit failures defeated trivial logic | No further source/test edits after final GREEN |
| 3.6 | same | Disposable native filesystem | 3.4–3.5 GREEN passed | Preservation/refusal/cleanup cases were behavior-first | Disposable-file harness passed | Real owner/mode/symlink/fsync/rename paths; injected timing hooks only for deterministic races | Final rerun preserved source/test SHA-256 bytes |
| 3.7 | same | Native lock + unit | 30/30 focused passed | Missing guard symbols compile-failed | Lock/routing/process fixtures passed | Protection, conflict, role, UID, and uncertainty matrix | Retained focused matrix |
| 3.8 | same | Native read-only process probe | 37 passed/1 skipped | Concrete-enumerator RED compile-failed on missing `NativeProcessProbe.system` | Self-only native PID and unavailable-PID tests passed | Injected PID lists prove populated-record and fail-closed disappearance paths | No refactor needed; 39 passed/1 skipped |
| 3.9 | same | Disposable native filesystem | Lock/routing/classifier subset GREEN | Lifecycle evidence preceded closure | Focused/full suites passed | Cleanup and all five host roles exercised | No source/test edits after final GREEN |
| U3B3-E partial | same | Pure codec | Actor transcript summary: exact focused command, exit 0, 55 tests; raw output unavailable after compaction | Exact command exited 1; summary reports 69 tests/8 issues but retains only seven named diagnostics | Actor-only 59 focused/72 full reported; no parent rerun | Static inspection now identifies presence-normalization and encode-depth questions | FAILED gate: budget/evidence incomplete |
| 3.19 | same | Unit | 61/61 focused passed | 65 tests failed with 9 behavioral issues | 65/65 focused passed | Invalid/journal state, five initial errors, update/readback missing, throw and mismatch | Fixture normalized before final GREEN |
| 3.20 | same | Unit | 3.19 RED established | Tests preceded custody correction | 65/65 focused passed | Initial absence creates once; observed existence only updates after E validation | Extracted shared readback verification |
| 3.21 | same | In-memory integration | 65/65 focused passed | 3.19 RED retained | 78/78 full passed | Pre-write preimages and post-write attempted mutations distinguished | No source/test edits after final GREEN |
| 3.13 | same | Injected native boundary | 65/65 focused passed; seam characterization also passed 65/65 | 68 tests failed with 8 behavioral issues | 68/68 focused passed | Native status failure and success-with-nil at both policy calls | Test warning normalized; final focused remained green |
| 3.14 | same | Unit + injected adapter path | 3.13 RED established | Tests preceded policy composition | 68/68 focused passed | Exact path/order/access/UID/service/local/nonsync attributes and data-only update | No source/test edits after final focused GREEN |
| 3.15 | same | Synthetic boundary integration | 68/68 focused passed | 3.13 RED retained | 81/81 full passed | Zero-add failure oracles plus persistent-ref update/no-delete coverage | No further source/test refactor required |
| 3.16–3.18 partial | same | Command integration + native lock | 68/68 focused passed; instrumentation seam also passed | 73 tests failed with 4 ordering/guard issues | 73/73 focused passed | Contention, malformed list state, create/update mutation checks, and post-verification refusal | FAILED gate: final 75/75 focused is subset proof; G requirements remain incomplete |

## Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0; 9 tests, 1 suite passed. |
| Runtime harness | N/A: Unit 1 is pure in-memory JSON/snapshot logic with no runtime or native boundary. |
| Broader test | `./scripts/test`: exit 0; 22 tests, 2 suites passed. |
| Rollback boundary | Remove the two new core files and their new test file; no unrelated behavior or state is involved. |

### Unit 2 Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0; 20 tests, 1 suite passed. |
| Runtime harness | Reused: `swift run AIControl claude-login invalid`; inert malformed argv emitted usage and exited 2 without GUI/backend access. Initial wrapper used reserved zsh variable `status` and exited 1 after the app output; one corrected wrapper used `code` and passed. |
| Broader test | `./scripts/test`: exit 0; 33 tests, 2 suites passed. |
| Rollback boundary | Revert Unit 2 additions in `AIControlMain.swift`, `ClaudeLoginManager.swift`, and `ClaudeLoginManagerTests.swift`; retain all Unit 1 snapshot/scoped-JSON behavior. |
| Review budget | Unit 2 implementation evidence was 380/400 changed lines; this 13-line artifact-only correction revises the cumulative Unit 2 authored total to 393/400. |

### Unit 3A Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0; 25 tests, 1 suite passed; opt-in native test skipped. |
| Broader test | `./scripts/test`: exit 0; 38 tests, 2 suites passed; opt-in native test skipped. |
| Runtime harness | One 90-second process-group-bounded invocation set `AI_CONTROL_KEYCHAIN_TEST_ROOT` to the approved disposable root and ran `./scripts/test --filter optInIsolatedNativeKeychainCRUD`: exit 0; 1 test, 1 suite passed in 0.046 seconds. |
| Cleanup | Temporary Keychain was detached without resetting the search list, deleted in `defer`, and its owner directory removed; post-run resource glob and harness-process checks both passed. |
| Rollback boundary | Remove `ClaudeLoginIO.swift` and the U3A tests only; retain U1/U2 manager behavior and leave U3B pending. |
| Review budget | 134 source additions + 167 test additions + 6 checkbox changes + 19 apply-progress changes + 38 pre-existing U3A scope-metadata changes + 7 reporting-correction changes = 371/400 authored changed lines. |

### Unit 3B1 Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused / broader tests | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 30 tests/1 suite; `./scripts/test`: exit 0, 43 tests/2 suites; opt-in native Keychain test skipped in both. |
| Runtime harness | Same focused suite exercised real disposable files: owned-span update, raw sentinel and mode preservation, symlink/owner refusal, input/output bounds, races, fsync/rename, readback, and failure boundaries. Standard-file ACL copying ran; nontrivial native ACL compatibility remains unverified. |
| Cleanup / process proof | Test cleanup assertions passed and post-run `.aicontrol-*` glob was empty. No child process harness or process enumeration ran; both test commands exited normally. |
| Rollback boundary | Revert only the U3B1 protected-file types in `ClaudeLoginIO.swift`, their tests/fixtures, tasks 3.4–3.6, and this section; retain U1–U3A. |
| Review budget | 406 lines before closure + 25 task/evidence changed lines = 431/450 under the U3B1-only exception. |

### Unit 3B2 Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused / broader tests | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 39 passed/1 skipped; `./scripts/test`: exit 0, 52 passed/1 skipped. |
| Runtime harness / cleanup | The focused run used only injected `getpid()` and `Int32.max` PID lists: real read-only `proc_pidinfo`/`proc_pidpath` self observation and fail-closed unavailable-PID handling passed; no full-host enumeration, credentials, Keychain, network, signals, or fixture directories occurred. |
| Rollback / budget | Revert U3B2 guards/tests/task evidence only; 438/450 lines: 370 prior + 50 source/test + 18 task/progress changes. NUL-framed source/test/tasks SHA-256: `c2732bc17a2dd364fd709170267349fbf6f2428626bd73a0380f94edf0fa015e`. |

## Security and Attempt Evidence

- Synthetic `.invalid` identities and placeholder tokens only; no home-directory, Keychain, environment-secret, network, process, installed-Claude, or live-auth access occurred.
- Auth classification: local CLI/device, human principal, first-party confidential storage boundary, single-user scope; Unit 1 only validates opaque local snapshot contracts and fails closed on malformed, duplicate, ambiguous, or disagreeing identity data.
- Native attempt token was supplied by the parent and not reacquired or reset. Evidence revision: `sha256:ed98c053357f890a897d24169b3d0c84a216b11a552d3f32c192941843df9a98`, binding NUL-framed ordered paths and bytes for both Unit 1 sources, its test, and current `tasks.md`.
- Unit 2 used only synthetic injected state and inert malformed argv; no filesystem, Keychain, environment-secret, network, Claude process, or live-auth access occurred. Attempt `sha256:750abee573539a8df9478e3b71605d0c18c8624eb011cc9000b2b39489804cb5` is settled complete; source/test/task evidence remains `sha256:c95c9e1743670ae6f9a1bac83e4316cb942c398045ba29cca08b61857a50a823`. U2 review preflight is done, but review START has not run.
- Unit 3A used one explicitly authorized temporary Keychain and fictitious `AIControl-claude-logins.v1.test-*` item. It did not read or write the default Keychain, Claude service, real credentials/configuration/identity, network, auth status, or Claude processes.
- Native CRUD and attribute/search-list preservation passed. Actual Claude-item ACL/signing compatibility and native denied/cancelled/locked behavior remain unverified; those errors are covered only by injected status mapping, and CRUD alone does not complete G2.
- Unit 3A evidence revision is `sha256:e9bbc7470d3529e84515b6e6507fc74e0d15403e8e0ca39d353f2bfdd3e43f84`, hashing NUL-framed ordered path names and current bytes for `ClaudeLoginIO.swift`, `ClaudeLoginManagerTests.swift`, and `tasks.md`.
- Lifecycle snapshot: U1 review approved and acknowledged/burned; U2 review explicitly declined; U3A native attempt settled complete and its review had not started at this entry.
- U3B1 used synthetic JSON and disposable owned files only: no live Claude config, credential, identity, network, auth, Keychain, or process access; production still uses `UnavailableClaudeLoginBackend`.
- U3B1 evidence is `sha256:f6d0bdb1837df95b9fe0d806a3bbfcfb59f3b74a4ee2251a4126202f4cddb9ab`: SHA-256 over ordered `path UTF-8 || NUL || file bytes || NUL` frames for source, test, then tasks. Attempt `sha256:1eb410aeb3a644dd707bd857c12d218dad9d515fd2f49cc8fc4f97fc130bf962` awaits parent settlement; U3B1 review has not started.
- U3B2 verified descriptor locking, pinned fixture routing, and injected process uncertainty; non-cooperating writers can still race the final process check and rename.
- Concrete native process enumeration is IMPLEMENTED via bounded `proc_listpids` plus per-PID UID, executable-path, and ancestry reads; production remains unavailable, so real credential integration and operator launch prevention remain unverified and block U3B3 activation.
- U3B2 attempt 8 settled `passed` under objective generation 8 at 68 changed lines against baseline `6e315effad7f9d0f84a47a4d125ff5730563b619`, remediating failed verification `sha256:d9daaa02194228dcea6d92a4605b828cfa0c2137b055e3b4e414ec3bdd440edb`. Its ledger evidence revision is `sha256:46d56dd31660affc72d291a559193dcd2fc96865bf2183c9287574e0bc0d23e9`, an ordered plain concatenation of `ClaudeLoginIO.swift`, `ClaudeLoginManagerTests.swift`, `tasks.md`, and this file; it differs from the NUL-framed `c2732bc1…` figure above only because the two use different framing conventions.
- Ledger defect, orchestrator-caused and disclosed rather than hidden: attempt 8's `diagnosis`, `cleanup_evidence`, and `process_evidence` fields hold the placeholder string `probe` because a diagnostic settle invocation reused the settle request ID and committed instead of replaying. The enforced fields (`outcome`, `changed_lines`, `evidence_revision`, `remediates_evidence_revision`, candidate trees) are all correct, no amendment operation exists for a completed objective, and `reset` would discard a legitimately complete scope; this file is therefore the authoritative U3B2 narrative.
- Open integration risk for U3B3, not a task 3.8 defect: `requireQuiescent` maps any `snapshot()` throw to `uncertain`, and `NativeProcessProbe.system` throws when any enumerated PID fails `proc_pidinfo` or `proc_pidpath`. On a real host, other-user and root processes routinely deny `proc_pidpath`, so the default full-host closure will likely report `uncertain` every time and refuse every write. Only injected self-PID and unavailable-PID paths are proven. Before activating production, U3B3 must decide how to skip undeniable-but-irrelevant PIDs without weakening fail-closed behavior.

## Supplemental Preparatory Process-Guard Correction

- The separately approved `preparatory-process-guard-correction` is complete without changing numbered task status; 16/25 tasks remain complete and U3B3 remains pending.
- This supersedes only the unproven root/foreign-path conclusion in the preceding risk note: short BSD metadata now identifies exact zombies, while every non-zombie still requires a valid path and any metadata/path denial remains uncertain.
- Production continues to use `UnavailableClaudeLoginBackend`; trusted-path classifier limitations, U3B3, native ACL/signing evidence, and G5 remain unresolved.
- Approval trace: metadata uses `PROC_PIDT_SHORTBSDINFO` argument 1 with exact returned size/PID; only exact `SZOMB` skips path while retaining PID/parent/UID and ancestry; root, foreign, stopped, `INEXIT`, and every other live record require a bounded nonempty valid path.
- Inventory trace: full-host `PROC_ALL_PIDS` remains capped at 1 MiB; nonpositive/misaligned/over-cap sizing, nonpositive/misaligned/over-capacity/full-capacity copies, negative PIDs, and duplicate positive PIDs refuse before writes; kernel PID 0 alone is ignored.

### Supplemental TDD Cycle Evidence

| Work unit | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| Process guard correction | `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Unit + injected native boundary | Baseline `./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 39 tests; post-seam same command: exit 0, 39 tests | Same command exit 1: behavioral failures listed below | Same command exit 0: 48 tests | Inventory, metadata, path, lifecycle, UID, stopped, and in-exit branches | No source/test edits after final focused GREEN; full suite passed |

### Supplemental Raw Tool Evidence

- Baseline log reference: current conversation raw Bash output for `./scripts/test --filter ClaudeLoginManagerTests`, before edits, ending `39 tests in 1 suite passed` and `__COMMAND_EXIT__=0`.
- Seam-regression log reference: current conversation raw Bash output for the same command immediately after adding `ProcessNativeCalls`, ending `39 tests in 1 suite passed` and `__COMMAND_EXIT__=0`.
- Behavioral RED log reference: current conversation raw Bash output ending `44 tests in 1 suite failed`, 14 issues, and `__COMMAND_EXIT__=1`: `Native process probe requests short BSD metadata and skips zombie paths` reported flavor `3` instead of `13`, path calls `1` instead of `0`, and path `/synthetic/live` instead of nil; `Native process inventory rejects uncertain native results` accepted misaligned sizing/copying, over/full capacity, negative PID, and duplicate PID; `Every non-zombie process requires a valid executable path` accepted empty, unterminated `/x`, oversized, and replacement-decoded invalid UTF-8 paths; `Native process metadata rejects incomplete or mismatched results` accepted metadata PID `43` for requested PID `42`.
- Final-focused log reference: current conversation raw Bash output for `./scripts/test --filter ClaudeLoginManagerTests`, ending `48 tests in 1 suite passed` and `__COMMAND_EXIT__=0`.
- Full-suite log reference: current conversation raw Bash output for `./scripts/test`, ending `61 tests in 2 suites passed` and `__COMMAND_EXIT__=0`; no project log files were generated.

### Supplemental Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `./scripts/test --filter ClaudeLoginManagerTests`: exit 0; 48 tests, 1 suite passed; opt-in Keychain test skipped. |
| Broader test | `./scripts/test`: exit 0; 61 tests, 2 suites passed; opt-in Keychain test skipped. |
| Runtime harness | Synthetic injected `proc_listpids`, `PROC_PIDT_SHORTBSDINFO`, and `proc_pidpath` calls plus the pre-existing self-PID-only native case; no full-host inventory rerun and no Keychain or Claude-state access. |
| Refusal evidence | Inventory/metadata/path uncertainty matrices execute `performGuarded` and each asserts a zero write counter before refusal; post-check behavior is unchanged and is not claimed as zero-write. |
| Rollback boundary | Revert this supplemental behavior in `ClaudeLoginIO.swift`, its fixtures/tests in `ClaudeLoginManagerTests.swift`, and this appended section only; retain historical U3B2 and all numbered task states. |
| Review budget | 93 source additions + 20 source deletions + 240 test additions + 38 progress additions = 391/400 authored lines. |

- Historical negative evidence, not correction RED: the prior metadata-only observation covered 884 PIDs/1,768 pass-pairs; full metadata produced 532 `EPERM` + 36 `ESRCH`, short argument 0 produced only 36 `ESRCH`, and short argument 1 diagnosed all 36 as zombies with zero unresolved live-short cases. The hypothesis failed; evidence revision `sha256:717696c7cfc65494a6ebfc14780b461aa28e44d6bead8fb67c79c0026806a8d5`.
- Parent verification independently reran both commands with `AI_CONTROL_KEYCHAIN_TEST_ROOT` unset: focused 48 tests/exit 0 and full 61 tests/exit 0, native Keychain skipped; source/test content hashes were unchanged before and after both runs.
- Parent tooling note: initial evidence serialization failed with Python `NameError` (`true` instead of `True`), after both test suites passed; this was settled as failed evidence `sha256:c568c9cf230d172ed0e88cb563ef4482a638497e7bce23171d13e71c6050e38f`, not an application failure. Evidence-only recovery leaves source and test bytes unchanged.
- At the apply actor's handoff, native settlement was pending and parent-owned; the actor did not acquire, settle, reset, or start review lifecycle operations.
### U3B3 Partial Apply Record — Tasks 3.10–3.12 Pending
- Status: PARTIAL/FAILED gate; no U3B3 task is complete and whole-change verification is not ready.
- Implemented but unaccepted: bounded envelope, two-alias custody/readback, synthetic Keychain attributes, and process-only guarded backend; public default remains `UnavailableClaudeLoginBackend`.
- Missing 3.11/3.12: native `ManagerFileLock` lifetime and `ClaudeRoutingValidator` composition, plus every guard's zero-write integration evidence.
- Custody defect: `save` catches `.missing` across initial read and update, so an existing item disappearing/failing during update can fall through to create instead of refusing.
- Missing 3.10 evidence: serialized custody invalid-alias, duplicate-identity, mismatched-identity, update-throw/readback-throw, full safe-diagnostic, and all-guard cases.
- Parent independently checked `./scripts/test --filter ClaudeLoginManagerTests` (55 tests, exit 0) and `./scripts/test` (68 tests, exit 0), both with `AI_CONTROL_KEYCHAIN_TEST_ROOT` unset; native Keychain skipped and source/test hashes unchanged.
- Baseline `6a2b25da1fa22887b6238c2253d50d0c67a09e98`: focused exit 0/48 tests/1 skipped; U3B3 RED focused exit 1 for `envelopeRoundTripsOpaqueSnapshots`, `envelopeRejectsUnsafeSerializedState`, `managerCustodyCreatesUpdatesAndReadsBack`, `managerCustodyRefusesUnsafeReadback`, `guardedBackendEnrollsAndReadsBack`, `guardedBackendRefusesUnsafePreflightWithoutWrites`, and `managerKeychainPolicyBuildsExactAttributes`.
- Assertions proven only by doubles: create/update counts, encoded readback, active/uncertain process refusal, and injected ACL object identity; this does not prove approved-binary ACL creation or native denial behavior.
- Baseline and RED provenance is actor-reported; exact RED assertion diagnostics were not retained in its compacted transcript. The parent verified current GREEN only; the actor also disclosed an intermediate non-RED `Hashable` compiler correction.
- Runtime/exclusions: injected storage/guard fixtures and existing supplied-self/unavailable-PID tests only; native Keychain skipped, no real credentials/default Keychain/Claude configuration/auth/full-host scan. Source/test files were unchanged during gate correction; native settlement is parent-owned.
- Incremental budget: 190+2 IO, 32+1 Manager, 162 tests, 13 progress = 400 changed lines; preserve prior 391-line preparatory history and partial code uncommitted.
- Next: a new human-resolved forecast is required before corrective implementation; no automatic partition or size exception is authorized.

### U3B3 Planning-Only Scope Amendment
- User authorized this single tasks/design revision only; parent reports one reset at baseline `17cab318c32fe6871037e54155a27c5c0e628964`, revision `sha256:6624576eb20be3ea5c3dd6f9cbd78ce4e45f17fad07d6b18b8d06f34a36ce820`, with the objective cleared. No further reset, objective creation, acquire, settle, probe, review, delivery, or implementation occurred here.
- Failed evidence `sha256:05cb9546bc93544fc1f441b3b8b7f704093be4c7aa48c9ab59d8729978d71f07` remains authoritative; any future passed acquire/settle remains bound to its remediation. This human planning allocation is not a native ledger or token/counter store.
- `tasks.md` Review Workload Forecast allocates all retained 400 lines once (P 266, A 49, G 85), preserves the separate reviewed 391-line preparation, and charges this entire planning diff to P. P completion exceeds 400 even without planning, so readiness remains blocked after one honest pass; no scope reduction or size exception is accepted.
- `design.md` clarifies complete custody, creation-policy and whole-command lock/routing/process contracts. Pending tasks are refined from three to nine: 16/31 complete, not newly completed work; original 4.1–4.6 and all completed task text remain unchanged.
- Changes are documentation only in these three files. No source/tests, untracked documents, package/scripts/state, credentials, Keychain, process probes, tests or builds changed/ran; historical 55/68 GREEN is not fresh verification. Structural readback: 102 authored lines against reset baseline (tasks 65+7, design 21+1, progress 8+0); `git diff --check` passed and all three supplied source/test Git blob hashes matched.
- Next permitted handoff: parent structural readback and user-owned budget/planning decision; no implementation or future work launched. OpenSpec remains authoritative; any Engram mirror is recovery context only, not byte parity or phase advancement.

### U3B3 Additional Planning-Only E/C Refinement
- User authorized exactly one further planning-only pass: separate envelope validation from custody under unchanged hard 400. Proposed order E → C → A → G; only prior combined-P allocation is superseded. Retained ownership is E 159 + C 107 + A 49 + G 85 = 400; reviewed preparation remains a separate 391-line prior unit.
- Previous planning measurement was 102 authored lines. Final cumulative planning against reset baseline `17cab318c32fe6871037e54155a27c5c0e628964` is 125 (tasks 81+7, design 21+1, progress 15+0), including both passes; never add 102 again. Allocation E 10/C 93/A 11/G 11 yields totals E 257–325/C 258–306/A 153–226/G 286–404. G remains four lines above the ceiling at its upper forecast; no compliant four-unit readiness claim. Structural readback passed `git diff --check` and all three supplied source/test hashes matched.
- Existing completed tasks and 4.1–4.6 remain unchanged. E keeps 3.10–3.12; C adds 3.19–3.21 before unchanged A/G IDs 3.13–3.18 in dependency order. Count is 16/34 complete, 18 pending: refinement only, no new completion. Full original validation/custody/policy/guard contracts remain required.
- No source/test changes, tests/builds, probes, Keychain/credentials, new reset/acquire/objective/settle/review or Git delivery occurred. Default remains unavailable and native G2 approval remains unproved. Failed runtime evidence `sha256:05cb9546bc93544fc1f441b3b8b7f704093be4c7aa48c9ab59d8729978d71f07` still binds future passing remediation; this plan is not that remediation.
- Handoff stops after structural readback; the parent owns the resulting user decision and any later implementation consent. No fifth unit, size exception, further partition iteration, phase advance, or byte-parity claim is introduced.

### Unit 3B3-E Partial / Failed Gate
- Status: tasks 3.10–3.12 pending; budget/evidence failure, not a functional-test failure. Production remains unavailable; no whole-change verification recommendation.
- Actor-reported TDD provenance: baseline `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` exit 0/55 tests; RED summary reports the same command exit 1 with 69 tests/8 issues, but raw output is unavailable after compaction and its full assertion provenance remains unverified.
- Retained RED diagnostics: nested outer/embedded duplicates, identity/usability mismatch, more than two snapshots, invalid marker, and excessive embedded depth were named; the eighth exact assertion is unavailable and is not inferred.
- Parent independently reran focused (59 tests, exit 0) and full (72 tests, exit 0) commands with `AI_CONTROL_KEYCHAIN_TEST_ROOT` unset; native Keychain skipped and source/test hashes unchanged. E itself is pure in-memory; existing suite self/unavailable-PID cases are not a full-host scan. Rollback covers E changes only.
- Budget and static findings: IO 79+17=96, tests 124+1=125, progress 9+1=10, tasks 0; total 231/231 after correction, plus retained/planning 169 = 400/400. `kind=value` with raw `null` may normalize presence, and encode may emit beyond configured outer depth; no new RED was run and no fix is authorized.

### Unit 3B3-E Corrective Completion
- Status: tasks 3.10–3.12 complete (19/34); user authorized E-only `size:exception` 450 total: 400 retained plus at most 50 new additions+deletions after the reset baseline below. This supersedes E's planning-only block only; C/A/G/U4/U5 and production remain unauthorized.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` exit 0, 59 tests/1 suite.
- RED: actor ran the exact focused command in the safety-net row: exit 1, 61 tests/2 issues. Parent raw Bash entry for `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter 'envelopePreservesNullPresenceSemantics|envelopeEncodeEnforcesOuterDepth'` ends `EXPECTED_RED_EXIT=1`, 2 tests/2 issues: line 334 returned decoded credentials `.null`, and line 348 returned 359 bytes, each instead of expected `.invalid`.
- GREEN: parent independently reran that targeted command (2 tests, exit 0), focused `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` (61 tests/1 suite, exit 0), and full `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` (74 tests/2 suites, exit 0); source/test Git blob hashes were unchanged across all three checks.
- Two test methods preceded production changes and remained unchanged after RED: explicit-null and depth-4 roundtrips passed while value-tagged raw null and depth-3 encode failed. The two codec guards now reject those inputs. This is fresh corrective RED plus existing regression coverage, not recovery of the unavailable historical eight-issue RED.
- Harness/cleanup: pure in-memory codec; no E fixtures or runtime cleanup, Keychain opt-in unset, no credentials/config/full-host scan; suites retained only existing self/unavailable-PID native tests.
- Rollback: revert only the two codec guards, two corrective tests, these three checkboxes, and this completion record; retain prior failed/history records and all C/A/G work.
- Budget/handoff: against reset baseline `d9b46fd9519ea105f9a0a29950306cb3d5019139`, source 4+0, tests 27+0, progress 11+1, checkboxes 3+3 = 49/50 new additions+deletions; human E total 400+49 = 449/450. Native settlement is parent-owned; whole-change verification is not ready.

### Unit 3B3-C Completion
- Status: tasks 3.19–3.21 complete (22/34); C-only strict TDD under auto-chain/stacked-to-main. A/G/U4/U5 remain pending and production stays unavailable.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` exit 0, 61 tests/1 suite.
- Behavioral RED: the same focused command exited 1 with 65 tests/1 suite and 9 issues. Existing invalid bytes were overwritten (update count 1; 359 versus 13 bytes), a pending journal was overwritten (update count 1), and update-time missing returned success after a second read/create (read count 2, create count 1, 356 versus 406-byte preimage). Raw output: `$TMPDIR/opencode/manage-claude-logins-u3b3-c-red.log`.
- GREEN: focused command exit 0, 65 tests/1 suite; full `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` exit 0, 78 tests/2 suites. The opt-in native Keychain test skipped in all runs.
- Harness/cleanup: injected in-memory store only; fixture state is released with each test. No Keychain, credentials, Claude configuration, auth, network, full-host enumeration, or external cleanup exists.
- Rollback: revert only C custody/verification changes in `ClaudeLoginIO.swift`, four C tests and fixture extensions in `ClaudeLoginManagerTests.swift`, C checkboxes, and this C evidence; retain E/U3A and all earlier history.
- Budget against pre-C tree `cc70a291e2006ed241093113acf0a205faa0b51a`: IO 9+2, tests 81+1, progress 13+1, tasks 3+3 = 113/200 new; human C total 107 retained + 93 planning + 113 new = 313/400.

### Unit 3B3-A Completion
- Status: tasks 3.13–3.15 complete (25/36 after the separately reserved final review-followup tasks); A-only strict TDD under auto-chain/stacked-to-main. G/U4/U5/followups remain pending and production stays unavailable.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` exit 0, 65 tests/1 suite. An indispensable injection-seam characterization rerun used the same command and also passed 65 tests before behavioral tests were added.
- Behavioral RED: the same focused command exited 1 with 68 tests/1 suite and 8 issues. Policy calls were absent (`events` observed `add,copy,update` instead of application/access first), `kSecAttrAccess` was nil, both trusted-application and both access failure cases threw nothing, and each failure pair performed two adds instead of zero.
- GREEN: focused command exit 0, 68 tests/1 suite; after normalization the final focused command again exited 0 with 68 tests/1 suite. Full `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` exited 0 with 81 tests/2 suites. The opt-in native Keychain test skipped in every run.
- Harness/limits: the focused suite exercised the real policy-coupled `IsolatedKeychainAdapter` initializer and create/update path using synthetic `NSObject` references and injected Security call closures. It proves call order, status/nil refusal, exact creation attributes, zero add on policy failure, and persistent-ref/data-only update without delete; it does NOT verify actual approved-binary ACL construction, code signing compatibility, native denial, or Keychain behavior.
- Cleanup/rollback: only in-memory references/counters were released; no external cleanup was required. Revert the A policy-call seam and policy-coupled initializer in `ClaudeLoginIO.swift`, the three A tests, tasks 3.13–3.15, the final-slice reservation, and this A evidence; retain E/C/U3A and earlier history. `R3-alias-final-newline` remains intentionally open for the final slice, while C already resolved the two historical custody findings.
- Budget against baseline `25420694dc3d794aee56a433e87d00537a55baa6`: IO 48+8, tests 133+0, tasks 12+4, progress 13+1 = 219/340 new; human A total is 60 retained/planning + 219 new = 279/400.

### Unit 3B3-G Partial / Failed Gate
- Status: tasks 3.16–3.18 pending (25/36); independent requirements check returned PARTIAL. Existing G code/tests are retained, production stays unavailable, and no U4/U5/followup work is authorized here.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` exit 0, 68 tests/1 suite; the event-instrumentation characterization rerun also passed 68 tests.
- RED: the focused command exited 1 with 73 tests and 4 issues at raw-output lines 184, 198, 255, and 310; lines 315–316 report 73 tests/4 issues. Raw output: `$TMPDIR/opencode/manage-claude-logins-u3b3-g-red.log`.
- GREEN/triangulation: parent independently observed focused exit 0, 75 tests/1 suite with 1 skip and `git diff --check` exit 0; actor reported full exit 0, 88 tests/2 suites. These are subset/regression results, not complete G proof.
- Runtime harness: disposable native `ManagerFileLock` exercised protection, contention, release, and serialization; routing/process/custody/policy used synthetic injected boundaries. No credentials, default Keychain, live Claude state, network, or full-host enumeration was accessed.
- Requirements-check findings: `Manager.swift:119–123,176–181` marks mutation guarding true after passing a callback to arbitrary custody; only the test wrapper at `Tests:1473–1484` invokes it. `Manager.swift:177–181,285–302` with `IO.swift:245–261` can recreate after an observed item disappears. Journal `recoveryRequired` maps to generic exit 3 rather than documented exit 4 (`Manager.swift:269–271`, test 599, design 19).
- Missing representative G proof: lock competition during capture/mutation/readback/final verification; release/refusal for factory/capture/write/readback throws; pre-capture process refusal check 1; command-level manual-B, same-identity, collision, third-alias, and dead-credential cases; asserted fixture-directory cleanup rather than only `try?` defer. Component variants need not become a blind cross-product.
- Rollback: revert G changes in `ClaudeLoginManager.swift`, G test/helper changes in `ClaudeLoginManagerTests.swift`, tasks 3.16–3.18, and this G evidence only; retain E/C/A and earlier units.
- Corrected artifact budget: 96 retained/planning + 312 new additions+deletions against baseline `743cbde3b8720d5ebf3e208165f72bbdec7375cd` = 408/450. Corrected ordered NUL-framed IO/Manager/tests/tasks SHA-256: `05617d3caad0afca836ef43d702851c671b47bb3505c0f4d095dbcbd259a5764`.

### G-M / G-C Approved Planning-Only Amendment

- Authority: OpenSpec is authoritative at `~/projects/ai-control/openspec/changes/manage-claude-logins`; Engram is recovery-only. Parent-supplied `gentle-ai.sdd-status/v2` reports artifactStore openspec, apply ready/next apply, blockedReasons [], 25/36 before refinement, verify/archive blocked and missing verify report. Human consent is planning-only despite that status; no phase/model implementation state call or task completion occurred.
- Native objective remains `unit-3b3-g-guard-composition`, goal `command-lock-routing-before-io-per-mutation-process-guards-safe-enrollment-list`, original maxChanged 354/maxAttempts 2. Failed whole-G evidence `sha256:05617d3caad0afca836ef43d702851c671b47bb3505c0f4d095dbcbd259a5764` remains unresolved. Failed settle returned proceed, not implementation consent or child budget authority. No ledger/reset/rescope/review command ran; no guessed future invocation is prescribed. Separate future implementation approval and documented native-authority negotiation are required; no reset or child pass clears this proof.
- Scope: G-M owns mutation-safe custody/backend; G-C owns dependent command integration and required whole-G proof. Tasks preserve all 25 completed IDs/text/status and U4/U5/FINAL unchanged; six pending child tasks replace three pending G tasks, yielding 25/39 complete. Existing ownership is 102 + 306 = 408 once; shared/mixed amendment lines belong to G-C.
- Measured amendment against the pre-edit document blobs: tasks 30 additions + 3 deletions (G-M 4, G-C 29); design 13 + 1 (G-M 1, G-C 13); progress 15 + 0 (all G-C). Total 58 + 4 = 62, allocated G-M 5/G-C 57 exactly once. Current cumulative charges are 107/400 and 363/500; remaining hard-cap room is 293/137, including future code/tests and closure. No old estimated planning allowance is added again.
- Verification/rollback: documentation-only structural readback and `git diff --check`; no tests/builds/runtime, auth/credentials/Keychain/full-host/delegation, staging/commits/branches/push/PR, or source-mutating normalization. Rollback only this amendment using the three pre-edit document blobs, preserving pre-existing work/history and all source/tests/untracked documents. Parent owns the proportional review gate; stop after documentation.

| Child | Existing | This planning | Remaining code/tests | Future evidence/checkbox closure | Cumulative forecast / cap |
|---|---:|---:|---:|---:|---|
| G-M | 102 | 5 | 99–155 | 10–16 | 216–278 / 400 |
| G-C | 306 | 57 | 111–160 | 10–16 | 484–539 / 500: PARTIAL/not ready, upper exceeds cap by 39 |

### Integrated Saved-Alias UI Product Amendment — Documentation Only

- Authority: user selected integrated app selection; latest `continua` permits this next planning step only. OpenSpec remains authoritative; parent-supplied native status was 25/39, apply ready/next apply, no blocked reasons, missing verify report and verify/archive blocked. No new native assessment or phase advancement occurred; human constraints override artifact readiness.
- Scope/count: saved aliases → user choice → shared guarded use, not usage fetching, OAuth/token refresh or OpenCode orchestration. Initial enrollment/manual re-login is distinct from subsequent switching. Added pending UI 4.7–4.9 before unchanged FINAL; all 25 completed tasks remain unchanged, now 25/42 complete and 17 pending.
- Safety/product gate: desired OpenCode-open/user-cancel-resubmit flow is conditional. Existing active/uncertain writer/lock guards remain; controlled proof and human lifecycle approval must reconcile idle clients with writers before relaxation/live activation. The user's backoff/logout-login/Esc/resubmit report proves neither attribution nor mechanism/concurrency. G-M/G-C and U4/U5 remain prerequisites; native ACL/G2/signing/denied and G5/live approval are separate, production remains unavailable.
- UI planning charge against the five saved pre-edit blobs: proposal 15+5, specification 39+2, design 21+2, tasks 25+2, progress 10+1 = 110 additions + 12 deletions = 122, allocated once to UI. Remaining code 120–180, tests 110–160 and future closure/interaction evidence 18–26 total 248–366; cumulative UI forecast 370–488/400, upper overage 88. No G charge moves. Stop PARTIAL for a human workload decision; no further automatic split, exception or evidence reduction.
- G continuity: charges remain G-M 107/400, forecast 216–278; G-C 363/500, forecast 484–539, unresolved 39-line upper overage. Whole-G failed `sha256:05617d3caad0afca836ef43d702851c671b47bb3505c0f4d095dbcbd259a5764`, objective `unit-3b3-g-guard-composition`, maxChanged 354/maxAttempts 2 remain unchanged; no ledger amendment or additional 550/600 allowance exists.
- Verification/rollback: five-document structural readback and read-only Git diff/hash evidence only; before/after blobs and unchanged source/test/untracked hashes accompany the handoff. No code/tests edits, tests/builds/runtime, credentials/Keychain/live Claude/network/full-host actions, delegation, ledger/review/reset/rescope or Git delivery. Rollback only this amendment against its five saved pre-edit blobs, preserving earlier uncommitted work/history. Parent owns structural spotcheck and the next human decision; no implementation permission is granted.

### Unit 3B3-G-M RED-Only Handoff

- Status: behavioral RED ready for parent spot-check; task 3.16 remains pending and no GREEN, G-C, UI, full-suite, native credential, ledger, review, or Git-delivery action ran.
- Authority: audited reset revision `sha256:6faaf189c4bc37f056e01d1106ead03cadbdcb8bbedaf3d6bc22439247b5809b`, current batch baseline `a217422ae49af2e36e6e591fbe6e5997ebee1586`, proceed token `sha256:ef5003069ddd8dcc963c43bbca2beb80b9300da223d6cea4190e94a7b41d9afd`, and failed whole-G binding `sha256:05617d3caad0afca836ef43d702851c671b47bb3505c0f4d095dbcbd259a5764`; parent retains settlement authority.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` passed 75 tests in one suite with the opt-in Keychain test skipped. Raw output: `$TMPDIR/opencode/manage-claude-logins-gm-baseline.log`.
- Indispensable seam characterization: added a default no-op native `beforeMutation` callback, invoked after persistent-reference lookup and immediately before `add`/`update`; the same focused command still passed 75 tests before fresh behavioral tests. Raw output: `$TMPDIR/opencode/manage-claude-logins-gm-seam.log`.
- Behavioral RED: after correcting a test-only collection-type compiler error, the same focused command exited 1 with 81 tests, one suite and 9 behavioral issues. Raw output: `$TMPDIR/opencode/manage-claude-logins-gm-red.log`.
- Failures prove the plain-store boundary writes before check 2 (create count 1 versus 0; update count 1 versus 0; mutated bytes versus unchanged preimages), successful create/update paths perform only two checks versus the required three, and an initially existing empty envelope that disappears is read three times, recreated once, and replaced from 47 bytes to 348 bytes instead of refusing with two reads and zero writes.
- Native fake-OS seam evidence passed with exact events `guard, add, lookup, guard, update`; it preserves persistent-reference/data-only update semantics and does not claim native Keychain, approved-binary ACL, denial, credential, or process-exclusion proof.
- Strict-TDD state: 3.16 RED written and observed; GREEN, triangulation completion and refactor are intentionally pending. Runtime harness is the injected plain external store plus fake Security closures; rollback removes only this seam, six tests, and the plain-store helper while retaining all earlier G history.

### Unit 3B3-G-M Completion

- Status: `success_for_GM`, tasks 3.16–3.18 complete (28/42); `partial_for_whole_G`. G-C, U4/U5, UI and FINAL remain pending, and the public production backend remains unavailable.
- Authority: implementation used proceed token `sha256:ef5003069ddd8dcc963c43bbca2beb80b9300da223d6cea4190e94a7b41d9afd` against batch baseline `a217422ae49af2e36e6e591fbe6e5997ebee1586`; no lifecycle, review or Git-delivery action ran.

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 3.16–3.18 | Focused 81 tests/1 suite, exit 1, 9 expected issues: plain create/update mutated before check 2, success had 2 rather than 3 checks, and existing-empty disappearance recreated data. | Targeted 5 tests/1 suite, exit 0; focused 81 tests/1 suite, exit 0; full 94 tests/2 suites, exit 0. | No source normalizer is configured; final focused/full runs followed the final source/test mutation, and `git diff --check` exited 0. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; exit 0, 81 tests/1 suite, opt-in native Keychain test skipped. Log SHA-256 `9569fd68b9cf2526de000d8b61c1288ccfc51fbeed9ddd57563656d53fa8c026`. |
| Runtime harness | Exact targeted command from the RED handoff, excluding the separately passing native seam case: 5 tests/1 suite, exit 0. It used an injected plain external store and process snapshots; no credential, live Keychain, network or full-host access. Log SHA-256 `7569ee930a7e64cb08b5a97e76bc1e6ac7c28620f4466589588d516b305c072a`. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`; exit 0, 94 tests/2 suites, opt-in native Keychain test skipped. Log SHA-256 `79488ecb8f7a9fb6b5a942bf45fb3228234460ed2624b889760d49d8332e7e4d`. |
| Rollback boundary | Revert only G-M protocol/custody/native guarded-overload changes in `ClaudeLoginIO.swift`, command-initial custody changes in `ClaudeLoginManager.swift`, the six G-M tests/plain helper, tasks 3.16–3.18 and this completion record. G-C must be absent or reverted first; retain E/C/A and earlier G history. |

- Implementation: custody now owns guarded create/update dispatch, records command-initial presence, refuses missing↔existing mutation-mode changes, and invokes the process check at the concrete mutation boundary. The isolated adapter places the supplied update guard after persistent-reference lookup and immediately before the data-only OS update; the lookup-to-update interval cannot exclude non-cooperating external writers and is not claimed as native proof.
- Final budget against batch baseline `a217422ae49af2e36e6e591fbe6e5997ebee1586`: IO 44+5, Manager 13+10, tests 140+0, progress 30+0 and tasks 3+3 = 248 new authored lines; with 107 retained/planning, G-M totals 355/400. Ordered `path UTF-8 || NUL || file bytes || NUL` SHA-256 for IO/Manager/tests/tasks: `be532d3dcfe019167fc3aa6f2e308d6d1d0660cf35676130aabbf9d2db690d25`.

### Unit 3B3-G-C Partial Evidence Correction

- Status: tasks 3.22–3.24 are incomplete (28/42). The one authorized correction attempt failed focused verification, so whole G cannot settle and no automatic retry or full post-correction run was performed. U4/U5/UI/FINAL remain pending; public production remains unavailable.
- Authority: the fresh parent token SHA-256 was `958d71d7cd8ed471949f3bf3f6be2bb137707861b5b6cd778366d0b052360e84`. G-C started with 363 charged and now uses 179 new lines for 542/550. No lifecycle, native, credential, probe, UI, or Git action was performed.

| Task | Safety net | RED | GREEN / triangulation | REFACTOR |
|---|---|---|---|---|
| 3.22 | Correction baseline focused 84/84, exit 0 | Original focused 83-test RED remains the only behavioral RED: two exit/output issues | Inside-lock and process-check-1 oracles passed, but the correction suite failed elsewhere | No production behavior was changed |
| 3.23 | Same correction baseline | Original 3.22 test preceded the retained three-line source catch | Source command behavior remains correct; phase fixture normalization regressed an existing readback-error contract | FAILED evidence gate; no retry |
| 3.24 | Parent independently reported full 97 passed/1 skipped before correction | Original 3.22 RED retained | Post-correction focused run: 84 tests, exit 1, four issues; full post-correction run not attempted | Tasks reverted to unchecked |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; exit 1, 84 tests/1 suite, four issues: three in `commandInitialExistingEmptyThenMissingRefusesCreate` and one in `commandEnrollmentMatrixUsesCachedState`. Output exists only in the foreground tool capture; no raw correction log file was created. |
| Behavioral RED | Same command; exit 1, 83 tests/1 suite, 2 issues at the pending-journal exit/output assertions. Raw log `$TMPDIR/opencode/manage-claude-logins-gc-red.log`, SHA-256 `3f8cb87de239ad18948a9d28894f028ffd95236cea15811aca0bddf71e8b6a88`. Earlier compiler failure was test-authoring error and is not RED evidence. |
| Runtime harness | `commandScopedSaveOrdersEveryGuard` now attempts a competing `ManagerFileLock.acquire` from capture, mutation, readback, and final-process event hooks; those assertions passed in the failed focused run. `commandScopedProcessRefusalStopsWrites` adds check 1 and records any capture invocation; all five cases passed. |
| Full regression | Not run after the focused failure, per the one-pass correction gate. Historical parent evidence remains 97 passed/1 skipped before correction and is not post-correction proof. |
| Rollback boundary | Revert only the recovery-required CLI mapping, G-C command tests/helper extensions, tasks 3.22–3.24, and this section; retain G-M/E/C/A. |

- Coverage: inside-lock and check-1/capture-refusal assertions passed. The new intermediate A/B preimage assertion used the wrong active hint, and changing shared `readbackError` to mutation-phase semantics broke the existing empty-envelope refusal; phase-based readback evidence therefore remains unresolved.
- Scope: synthetic identities and stores only; no credentials, Claude configuration, default/isolated Keychain, network, full-host scan, native ACL/denial/adoption/exclusion, OpenCode operation, or live auth was accessed. The mandatory unavailable public default remains unchanged.
- Final pre-G-C-tree delta: Manager 3+0, tests 128+14, tasks 4+0, progress 27+3 = 179 new; 363+179 = 542/550, leaving 8. Combined runtime implementation cost is G-M 248 + G-C 179 = 427 lines against their respective baselines.
- SHA-256: IO `eda798200787a7b4d0299e639a3b88f262ba60c3432a65c9ef63fc2daf7be56c`; Manager `552006ed890a091f9bb177dfd25ae9789f2c43371cf290d68ba90b5852ec50d5`; tests `3873e4c3229c682d7b7247a12ac9b327bd84e475db3b125cc3d3f45e1e801d21`; tasks `c5374c77e0c90e48f1d4d4f8296ad16ff0b883c11da6303630d7535fbac9d1e4`. Ordered NUL-framed IO/Manager/tests/tasks SHA-256: `a2b0a64fa384473ad342d6024787976f41782e74e95888bfe5a220262db1bf34`.
- Latest G-C acceptance supersedes the partial status above, retaining its failed-attempt history: corrected the intermediate hint to alpha and separated post-mutation read failure from existing second-read semantics; production unchanged. Writer targeted 3/focused 84/full 97 tests passed; parent independently reran targeted 3, and the independent requirements recheck returned PASS_FOR_G for held-lock competition, check-1 refusal, phase-based readback and intermediate A/B preservation. Tasks 3.22–3.24 are complete (31/42); 363 retained + 180 corrected work + 6 checkbox changes + this evidence line = 550/550. Native settlement remains parent-owned; U4/U5/UI/FINAL and live acceptance remain pending.

### U4 F/S Split and Cleanup Contract — Documentation Only

- Human approval covers F ≤400 / S ≤600 cumulative and the post-commit cleanup distinction, not implementation. OpenSpec is authority; Engram is recovery-only. Parent status: 31/42 before refinement, apply-ready/next apply, blockedReasons [], verify/archive blocked; human planning-only consent controls.
- Native U4: failed binding `6def010cd5a981c97539af31a099d210054f600e5ee7e2dff2bbec11a6793b86`; reset baseline R=`71a6fe0597972eab85b20e9d72c62cf08b8b0725`, maxAttempts 2/maxChanged 33 after the 450 exception, no active attempt, latest failed settle PROCEED. Separate human/native authority is still required; no new reset or child pass clears failure. Parent's 88 focused GREEN remains partial requirements evidence, not closure.
- Audited B=`5615fb631076ab9a2fb29edf52817feed5b87d1b` → R: 385 additions + 32 deletions = 417. Historical R ranges below are immutable ownership locators, not current line claims; no tests/assertions/fixtures move for budget fit.

| Child | Retained ownership | Remaining source / tests / closure |
|---|---|---|
| F | ALL IO 84+12=96 (R81,121–255,334–363,577); Manager R72,75–123 50+0; total 146. | 65–105 / 70–115 / 8–12 |
| S | Remaining Manager R124–407 92+15=107; ENTIRE Tests R278–365,1623–1706 159+5=164, including failure enum/both fixtures; total 271. | 40–75 / 120–180 / 10–16 |

- Actual planning: proposal 2+2, spec 10+2, design 21+4, tasks 7+4, progress 16+2 = 56 additions + 14 deletions = 70; F 12+0, S 44+14. This replaces F12–20/S30–45 estimates once. Charges F158/S329; unchanged remaining ranges yield F301–390/400 (10 upper room), S499–600/600 (zero upper room). F-only contracts/tasks/ownership rows belong to F; all shared/mixed lines and old deletions to S. Stop if forecasts exceed caps; no automatic split, exception or evidence reduction.
- Verification/rollback: documentation-only diff/hash/task-continuity checks; no tests/builds/runtime, native ledger/reset/rescope/review, Git delivery, credentials/network or delegation. Revert only these five amendment hunks using saved pre-edit document blobs; preserve source/tests/untracked bytes and all earlier history. STOP before implementation; FINAL 5.1–5.2 remains last.

### U4-F Partial / Not Accepted

- Status: PARTIAL/not accepted; tasks 4.1–4.2 remain pending (31/44 complete). Public production remains unavailable. The parent owns FAILED settlement, lifecycle/review, and the unresolved whole-U4 binding `sha256:6def010cd5a981c97539af31a099d210054f600e5ee7e2dff2bbec11a6793b86`.

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.1–4.2 | Focused 92 tests/1 suite, exit 1, 14 behavioral issues: inconsistent journal images/marker admitted, normal decode returned recovery before byte/depth refusal, secure replacement skipped after-lookup reread, and stale configuration roots mutated. Earlier test compilation failure is excluded. | Same focused command passed 92 tests/1 suite; full suite passed 105 tests/2 suites. Native Keychain test skipped because opt-in was unset. | Reused existing codec bounds, persistent-reference query, and protected-file replacement path; no further source/test mutation after GREEN. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; exit 0, 92 tests/1 suite. GREEN log SHA-256 `a7a32c05ba1a4e7d80a0b905cbd8e66f28949753954a4183e8d602ef5da2364b`. RED log SHA-256 `e0f2d76241587ac13afdd24e184c92097cb20c56d1932c568b665896e6014b2c`. |
| Runtime harness | The focused suite exercised journal bytes in memory, an injected Security-call adapter race, and a disposable protected configuration file stale-root race; exit 0 with exact preservation assertions. No real credential/default Keychain/live Claude/network/full-host boundary ran. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`; exit 0, 105 tests/2 suites. Log SHA-256 `0c1dc4d2b505acb0283ab1df2370c6be32de6d9ef74ae51e1737a3fe4cb12ac5`. |
| Rollback boundary | Revert U4-F codec/resource changes in `ClaudeLoginIO.swift`, its four tests in `ClaudeLoginManagerTests.swift`, tasks 4.1–4.2 and this section. U4-S must be absent/reverted first; retain G and earlier history. |

- Unresolved F-local findings: journal cache `.value` raw JSON is validated only in snapshots, so encode can serialize malformed raw content as a string that `decodeRecoveryRecord` later rejects; replacement tests cover early refusal only and lack admissible success, executed/throwing guard, zero-mutation, and exact persistent-reference DATA-only payload witnesses; serialized negatives use encode rather than hostile recovery bytes and omit hostile image/marker/phase/keys/presence/raw cases plus a valid committed roundtrip.
- Evidence disposition: the recorded 92-test RED, 92-test focused GREEN, and 105-test full GREEN remain truthful subset evidence only; no additional implementation or test attempt occurred in this bookkeeping correction.
- Budget: this correction is 16 authored additions+deletions versus the prior docs, charged to F; prior 365/400 becomes 381/400, leaving 19. Exact baseline numstat and parent settlement hash are reported by the apply handoff.

### F-J / F-K / F-C Cumulative Amendment — Documentation Only

Human approval covers this seven-slice plan and J `size:exception` 536 TOTAL, not a new 536. OpenSpec is authority, Engram recovery only. Supplied native status remains apply-ready (31/44 before this refinement), verify report missing and verify/archive blocked. Native objective `unit-4-f-journal-resource-foundation` retains maxChanged 242/maxAttempts 2; no active attempt, last failed settle PROCEED, not complete. Latest F failure `2785b53667a9381f8e45dc77cc6f727da425a492c54015b4639f2343f5ef4231` and whole-U4 binding above remain unresolved; separate implementation approval and documented native-authority reconciliation are required, without reset/rescope/counter changes here.

Immutable audit anchors: B=`5615fb631076ab9a2fb29edf52817feed5b87d1b`, R=`71a6fe0597972eab85b20e9d72c62cf08b8b0725`, P=`d8887c6e89011cf0e007a6bb1566a8d81019bc88`, Q=`a5a8344d3964f9960ae917dee645bdd333c01536`. IO/Manager/Tests denote the existing paths defined in tasks; ranges identify those snapshots. The prior 381 is charged exactly once:

| Historical charge | Reproducible ownership anchors | J / K / C |
|---|---|---:|
| Retained F 146 | B→R: all IO 84+12=96 journal DTO/codec/custody; Manager R72,75–123=50 journal/owned models/shared roots/resource contracts. Original 417 remains F146/S271. | 146 / 0 / 0 |
| Original F planning 12 | R→P: design 54–58,61–63=8; tasks 141,205–206=3; progress 305=1. Original 70 remains F12/S58; mixed F/S planning deletions stay S. | 12 / 0 / 0 |
| Writer 207 | P→Q: J IO added Q186–187,250–251,255–259 and deleted P248,252=11; Tests Q425–507=83; all progress20+2/tasks2+2=26. K IO Q472–475,498–507=14 + Tests Q895–932=38. C IO Q632–639,643–645,677,702–705=16 + Tests Q933–951=19. | 120 / 52 / 35 |
| Bookkeeping 16 | Q→pre-amendment: shared progress6+6 and checkbox reversal2+2. Preserve failed history; net P→pre-amendment 203 cannot replace cumulative381 because it erases20 churn. | 16 / 0 / 0 |

| Child | Prior + actual planning | Unchanged remaining source/tests | Future closure | Cumulative forecast / cap | Remaining hard cap, including closure |
|---|---:|---:|---:|---|---:|
| F-J | 294 + 45 | 121–182 (raw34–54 + serialized87–128) | 10–14 | 470–535 / 536 | 197 |
| F-K | 52 + 5 | 67–96 | 10–14 | 134–167 / 400 | 343 |
| F-C | 35 + 5 | 75–112 | 10–14 | 125–166 / 400 | 360 |

Future verification only, not executed: each child runs `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`, then `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`. Require genuine behavioral RED for missing behavior (never passing characterization), normalized GREEN, exact argv/exit/assertions/observed-versus-expected/counts/raw locator/cleanup. J uses memory, K fake OS, C disposable files. Each closure reserve is four checkbox-change lines plus 6–10 evidence lines: 30–42 replaces old20–30, not an additional charge. Historical parent92 focused GREEN/writer105 full remain subset evidence only, not child or whole-F/U4 closure.

Actual planning replaces prospective J30–46/K6–10/C6–10 (42–66) against the three supplied beforeblobs; count additions+deletions once, assigning explicitly owned task/contract/boundary/forecast rows to J/K/C and all shared/mixed lines or deletions to J unless already identified as single-owner. No source/tests/requirements move or shrink for budget fit. S retains329 charged/271 remaining, inherited499–600/600 (including original164 test/fixture lines); UI retains122+248–366=370–488/500; neither is freshly audited. U5/FINAL have no verified forecast. Stop if actual planning or upper forecast breaches a cap; no automatic repartition/exception/implementation. No fake activation, usage requests, OpenCode orchestration, native workflow or delivery action is authorized.

### U4-F-J Completion

- Status: `success_for_J`; tasks 4.1–4.2 complete (33/48). Whole F/U4 remains partial because F-K/F-C/S are pending; failed F `2785b536…` and U4 `6def010c…` obligations remain.
- Safety/RED: focused baseline passed 92 tests. The same command then failed behaviorally with 93 tests/3 issues: malformed JSON, value-null and over-depth cache `.value` inputs returned encoded bytes instead of `.invalid`. Raw logs: `manage-claude-logins-u4-f-j-baseline.log` and `manage-claude-logins-u4-f-j-red.log` in the approved temporary log root. One later depth fixture correction and one access-control compiler correction were test-authoring/tooling issues, not RED.
- GREEN: parent pre-correction check passed 95 focused tests; after the last correction mutation, focused passed 95 tests/1 suite and full passed 108 tests/2 suites, both exit 0. Opt-in native Keychain remained skipped. Raw logs: `manage-claude-logins-u4-f-j-correction-focused.log` and `manage-claude-logins-u4-f-j-correction-full.log`; no source/test normalizer is configured and `git diff --check` passed.
- Coverage: fifteen hostile serialized-byte cases derive from an admitted pending control; construction now occurs outside the decoder-only expected-error assertion. The added `overDepthRaw` case mutates `journal.before.configuration.modelAccessCache.value` in otherwise valid serialized bytes, directly proving bounded embedded-cache rejection. Exact stale-pending and committed roundtrips remain intact.
| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.1 | Focused 93 tests/1 suite, exit 1, 3 expected issues: malformed JSON, value-null and over-depth raw values encoded instead of `.invalid`. | Covered by final focused 95 tests/1 suite, exit 0. | Corrected depth and access-control test-authoring defects; neither counted as behavioral RED. |
| 4.2 | Reused 4.1 RED before production mutation; hostile matrix was post-GREEN triangulation from an admitted control. | Focused 95 tests/1 suite and full 108 tests/2 suites, exit 0. | Reused `Presence.decoded`; no Manager or replacement/coordinator behavior changed. |

| Work Unit Evidence | Result |
|---|---|
| Focused | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0; 95 tests/1 suite passed; opt-in native Keychain skipped. |
| Runtime harness | N/A: J is a pure in-memory journal codec boundary with no external state; full suite passed 108 tests/2 suites. |
| Rollback | Revert only J codec validation, J tests/fixture correction, tasks 4.1–4.2 and this section; dependent F-K/F-C/S consumers must be absent/reverted first. |
- Budget: original baseline `74516b26f3ab85b0ba44aafcce0fab09df9bce13`; final net numstat is IO 8+0, tests 123+1, tasks 3+3, progress 19+1 = 158. Honest churn is 339+155+4=498 before correction; final correction delta versus `fc77c539a2cc93226e5ac86c66c0175947e734cc` is tests 5+2, tasks 1+1 and progress 4+4 = 17, plus 6 lines of intermediate evidence-count correction churn, yielding cumulative J 521/536.

### J Fresh Verification and Closure Decision

- Fresh verification only: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` passed 95 tests/1 suite; `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` passed 108 tests/2 suites; both exit 0 with one native Keychain test skipped. Source/test bytes unchanged; no new RED. Raw logs: `$TMPDIR/opencode/u4-f-j-closure-d4acd772-focused.log` and `$TMPDIR/opencode/u4-f-j-closure-d4acd772-full.log`.
- Human decision: explicitly accepts native v2.7.0 J-objective passed closure discharging the current chain failure frontier while ancestor failed history is retained. Earlier child-pass restrictions concern aggregate whole-F/U4 feature claims, not continued native enforcement; whole F/U4 remains OpenSpec-pending and is not claimed repaired (33/48 complete, 15 pending).
- Handoff: actual native settlement remains parent-owned and pending, with no success prediction or review reuse. This documentation-only pass costs 10 authored additions+deletions against candidate `784b3957e27e521d1a53d8524fa7ccd66efb779c`, with no intermediate churn: J 521+10=531/536, 5 remaining; no task checkbox, source/test, K/C/S/UI budget, or native field changes.

### U4-F-K Completion

- Status: `success_for_K`; tasks 4.12–4.13 complete (35/48). Whole F/U4 remains partial while F-C/S are pending; J remains 531/536, and native K settlement is parent-owned and pending.

| Task | Safety net | RED / proof | GREEN | REFACTOR |
|---|---|---|---|---|
| 4.12 | Focused 95 tests/1 suite, exit 0 | Three new behaviors and the corrective exact-one search-list cardinality assertions passed as CHARACTERIZATION/PROOF, not fabricated RED. | Identity lookup, selected-reference read, and update queries each proved one search-list member while retaining identity checks. | Closes the prior cardinality-proof omission; production remained byte-identical. |
| 4.13 | Same baseline | Reuses 4.12 proof because no production gap existed. | Final focused 98 tests/1 suite and full 111 tests/2 suites passed, exit 0; native Keychain skipped. | No source normalizer configured; final checks followed the last source/test mutation. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` emitted 98 tests/1 suite passed with one native Keychain skip in `$TMPDIR/opencode/manage-claude-logins-u4-f-k-correction-focused.log`; the enclosing capture shell exited 1 afterward because `status` is read-only in zsh. No retry occurred. |
| Runtime harness / cleanup | Fake `KeychainNativeCalls` proved identity lookup → persistent-reference read → guard → one data-only update, exact queries/postimage/unrelated preservation and zero add/delete/re-add. In-memory objects required no external cleanup; no real credentials, SecItem calls, policy, Claude state, network, or full-host scan. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` passed 111 tests/2 suites, exit 0, with one native Keychain skip; log `$TMPDIR/opencode/manage-claude-logins-u4-f-k-correction-full.log`; Keychain opt-in was unset. |
| Rollback boundary | Revert only the four K secure-replacement tests/assertion strengthening, tasks 4.12–4.13, and this K record; downstream F-C/S consumers must be absent first. |
| Budget | Corrective delta against stored pre-correction tree `0a9d136997feb6d074a6dc2d3ea32d1d395f40ea` is tests 3+0, progress 5+5, tasks 1+1 = 15 with no intermediate file churn. Original K 295 + 15 yields cumulative K 310/400; 90 remain. |

### U4-F-C Completion After Test-Syntax Repair
| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.14–4.15 | Characterization/proof only; the known pre-repair compiler failure (`try` on comparison RHS) is test-authoring evidence, not business RED. | Focused command passed 100 tests/1 suite; full command passed 113 tests/2 suites; both exit 0 with native Keychain opt-in unset. | One assertion reordered operands only; no production/source behavior or other test changed. |
| Work Unit Evidence | Result |
|---|---|
| F-C syntax repair and closure | Focused: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`, exit 0, 100 tests/1 suite. Runtime/broader: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`, exit 0, 113 tests/2 suites; disposable configuration races proved exact external-inode retention after refusal, content/protection preservation, UUID-child/temp cleanup, and the native Keychain test remained skipped. Rollback: revert only the operand-order repair and these F-C task/progress hunks; retain production IO, J/K/G and historical failure evidence. Budget: 26 successful pending-reset/syntax operations + 24 closure operations = 50 new; retained 400 + 50 = 450/450. No source/test normalizer is configured. |

### U4-S Partial / Not Accepted After Independent Requirements Check
| Evidence | Result |
|---|---|
| TDD cycle | Reported 104-focused/117-full GREEN remains historical subset proof, not S acceptance. Preserved code proves checkpoint-first fresh/dead same-alias and actual unsupported-root refusal, but the matrix lacks exact checkpoint/journal images, resource bytes, marker checks per phase, pre-mutation/immediate-post-commit process guards, and missing/ambiguous/unmatched refusal witnesses. Manager invokes secure then configuration callbacks before combined capture without source-owned secure postimage verification; fake `secure-readback` is only a label. Commit certainty follows custody readback plus an extra read, so an extra-read throw can wrongly map to recovery; the direct `afterReadback` postcheck is too late, although the command branch postcheck is correct. |
| Focused / full | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 104 tests/1 suite; `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 117 tests/2 suites. Native Keychain remained skipped. |
| Runtime harness | Command `use` proved only post-return lock reacquisition, not held-lock competition; `save` evidence does not substitute. `SelectionFixture` creates a directory for eight consumers, but only the matrix calls non-deferred cleanup, so seven consumers lack cleanup/deinit and throwing assertions can bypass matrix cleanup. No actual leak enumeration was performed; all-temporary-removal is unproved. |
| Rollback / budget / status | Preserve all source/tests and history; no behavioral correction is authorized. This bookkeeping costs exactly 16 authored operations, so reported S rises from 583 to 599/600; the 232-line net against stored pre-S tree `0214658da5cd6cf3bf1166993176502c4195ec9a` is not cumulative accounting. Tasks 4.10–4.11 return pending (37/48); U5/UI/FINAL remain unchanged and public production unavailable. Parent owns active S token `491…` and failed settlement. |

### Approved L → A → V → O Amendment — Documentation Only

- Authority: OpenSpec owns this amendment; Engram observation 8578 is audit/recovery context only. User approved four cumulative 400 caps (maximum 1600 INCLUDING 599), ONE audited old-S→L reset by the parent after gate validation, and AUTO remaining dependency-ready work. Reset was NOT executed here; no additional resets, candidate consent, live permissions or Git delivery follow. U5/UI/FINAL budgets and mandatory gates remain unchanged.
- Parent-supplied native v2: last 37/48 accepted, 11 pending, apply-ready/next apply, no blockers, verify/archive blocked. Failed nonterminal objective `unit-4-s-selection-coordinator`, goal `checkpoint-first-guarded-selection-per-resource-verification-phase-outcomes-command-lock-proof`, maxChanged 271/maxAttempts 2, cumulative 1/228 net, no active attempt; revision `9f5a1691bd5cad54c24e938899af16da29305526f2aa8ca43252482547c4fad5`, failed binding `c2b0d74e0b721cf171ef94aca7798695b857928b1dccfb8d38c30eb14be633cb`. This supersedes old active-token prose, not ledger fields. Child PASS/chain-discharge versus aggregate-pending qualification remains accepted; no S completion claim.
- Immutable anchors: B=`5615fb631076ab9a2fb29edf52817feed5b87d1b`, R=`71a6fe0597972eab85b20e9d72c62cf08b8b0725`, P=`d8887c6e89011cf0e007a6bb1566a8d81019bc88`, Q=`0214658da5cd6cf3bf1166993176502c4195ec9a`, W=`95d2574a90606ed7dd2f3a3bc9cb40377942e636`. Manager/Tests use the existing paths in tasks. Count changed lines with `git diff --no-ext-diff --unified=3 OLD NEW -- PATH`; W matched all three supplied beforeblobs before amendment.

| Historical component / checkable ownership | L | A | V | O | Total |
|---|---:|---:|---:|---:|---:|
| B→R S Manager: command wiring; admission R180–197; persist/preparation/resources/commit; cleanup/catch/output. Excludes F R72,75–123 and all IO. | 32 | 18 | 33 | 24 | 107 |
| B→R Tests: L whole SelectionFixture R1663–1706/command edits; A R298–315,351–365; V whole MemorySelectionResources R1625–1662; O roundtrip/failure tests/enum. | 56 | 33 | 38 | 37 | 164 |
| R→P old mixed F/S planning: proposal4/spec12/design17/tasks8/progress17, preserving shared history/deletions. | 0 | 0 | 0 | 58 | 58 |
| Q→W Manager endpoint: A initial/updated-target/root admission; V prepared/committed/persist callbacks; O cleanup/catch/CLI. | 0 | 15 | 12 | 11 | 38 |
| Q→W Tests endpoint: L whole SelectionFixture W2263–2335 changes; A W368–394,2178–2179; V W2229,2238–2239,2247–2248; O whole phase/store/oracle/matrix integration. U3 is 163+15, not U0 realignment 164+16. | 64 | 29 | 5 | 80 | 178 |
| Unmapped intermediate source/test churn: shared failed integration, no invented exact provenance. | 0 | 0 | 0 | 22 | 22 |
| Original S closure authored operations, retained failure history. | 0 | 0 | 0 | 16 | 16 |
| Independent S downgrade authored operations, retained above. | 0 | 0 | 0 | 16 | 16 |
| Historical total, redistributed exactly once | 152 | 95 | 88 | 264 | 599 |

| Child | Historical + actual amendment = charged | Remaining code/tests | Future closure | Remaining within 400, including closure | Cumulative forecast / cap |
|---|---:|---:|---:|---:|---|
| L | 152 + 6 = 158 | 95–150 | 8–13 | 242 | 261–321 / 400 |
| A | 95 + 5 = 100 | 17–30 | 5–8 | 300 | 122–138 / 400 |
| V | 88 + 6 = 94 | 121–204 | 8–13 | 306 | 223–311 / 400 |
| O | 264 + 50 = 314 | 48–70 | 8–12 | 86 | 370–396 / 400 |
| Total | 599 + 67 = 666 | 281–454 | 29–46 | 934 | 976–1166 / 1600 cumulative maximum |

- Amendment accounting: one successful patch, no intermediate churn; W→working design16+0 (L2/A1/V2/O11), tasks14+5 (L3/A3/V3/O10), progress31+1 (L1/A1/V1/O29) = 67 authored additions+deletions. Explicit child task/contract/work-unit/forecast rows belong to that child; all shared headings/narrative/mixed history and old S deletions belong to O integration. Whole helpers keep named historical ownership; later amendments are new owner cost, never a transfer. Actual67 replaces prospective36–56 ONCE.
- Forecast: preserve original remaining304–491 = code/tests281–454 + evidence23–37. Extra per-child evidence6–9 yields closure29–46; actual planning67 plus extra evidence6–9 adds73–76, replacing the prospective42–65 addition. Estimates are not guarantees; no correction reserve is funded. Stop PARTIAL if any actual charge plus unchanged remaining upper and closure exceeds400; no shifted cost, automatic new split or expanded cap.
- Verification/handoff: documentation structural checks only; no tests/build/runtime/native SDD/ledger/reset/rescope/review/Git delivery/network/credentials/delegation. Preserve all37 completed lines and U5/UI/FINAL text/status/IDs; six new pending IDs produce37/54,17 pending. Parent validates diff/hash/task continuity and remaining caps before its authorized transition, then L follows the cleanup-first plan in design. Historical104/117 GREEN cannot accept S; rollback only these planning hunks against W, retaining source/tests, unrelated documents and all failure history.

### U4-S-L Completion

| Task | Safety net / RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.16–4.17 | Cleanup-first `Selection fixture cleans owned lock directories on normal, throwing, and initialization-failure paths` passed 1 test/1 suite before the fresh 105-test focused baseline; its normal/throw branches remove the owned UUID child and its initialization-failure branch proves non-creation. Existing command locking was characterization, so no artificial production RED or Manager edit was made; one focused expectation-correction run failed with 5 issues. | Final focused passed 107 tests/1 suite; full passed 120 tests/2 suites, both exit 0 with native Keychain skipped. | Every original SelectionFixture consumer now defers asserting cleanup; cleanup reacquires the lock and removes only its exact owned UUID directory. |

| Work Unit Evidence | Result |
|---|---|
| Focused / runtime | Cleanup `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter selectionFixtureLifecycle`: 1 test/1 suite, exit 0, session `ses_f71e0d8ccffeRZrfMamcFtlzvj`, call `call_1o8Iw4bOcdnlSaJDoxAZWpqj`; it ran before baseline by verified timestamps. Exact baseline and final argv was `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: baseline 105 tests/1 suite, exit 0, `call_B2xqtrDObv2Y4RzXv7qMZeOj`; final 107 tests/1 suite, exit 0, `call_wcur6Kttbq2CJVKMmOxxjZsz`. Actual `use` callbacks proved contention through capture, mutation/readback and final release. |
| Guard / regression | Four process-fault cases proved preimages, write bounds 0/0/2/2, forbidden later callbacks and release. The same exact focused argv failed only the intermediate expectations with 107 tests/5 issues, exit 1, `call_zOpIWPwQaAXzxzX3Y6ipGZ8S`, raw `~/.local/share/opencode/tool-output/tool_08e2658a9001lLZzHk8BsT8aHT`; final focused raw is `~/.local/share/opencode/tool-output/tool_08e2713e7001WssNHADFUv0pEY`. Full `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: 120 tests/2 suites, exit 0, session `ses_f71e0d8ccffeRZrfMamcFtlzvj`, call `call_gKpf0efQjhMWacPAusHsywdg`; cleanup/baseline/full are untruncated inline exported call parts, not physical log files. |
| Rollback / status | Revert only L lifecycle/lock-proof tests and helpers plus tasks 4.16–4.17 and this record; never restore leaking fixture behavior. Production Manager stayed byte-identical. L is complete at 39/54, but aggregate S remains pending A/V/O and parent native settlement remains pending. |

- Budget: L was 380/400 before this corrective artifact gate; this pass used exactly 16 successful documentation additions+deletions including churn, so L closes at 396/400. Other budgets are unchanged.
- Continuity: source/test hashes remain IO `29f4d2c9e6d3a46e9cf2ce831c97f6aaad5cabbc42bd6b13c52bcbde26dc5ea7`, Manager `84e21606f1a9db48d2b3094f116c040463beb77ff62916247b951108df0611d9`, tests `7ed5077719709cad73bf71c7225cf9e2021315c7cebf94ec16aa24fd32db2103`; current tasks `96f49f974505528f7e51af9188833a1f2cf605c7799794f46e5e67ffe910b472`. The prior tasks hash/evidence digest were pre-correction historical. Current ordered `path UTF-8 || NUL || file bytes || NUL` IO/Manager/tests/tasks SHA-256: `6b497795c508489bf55728964a677e9deb39cd78fe8d8ff1133e1889a72d5af3`.

### U4-S-A Partial — Test-Authoring Compiler Failure

- Status: PARTIAL; tasks 4.18–4.19 remain pending (39/54). Per the one-pass failure gate, no production correction, retry, full suite, task checkbox, native lifecycle, review, or Git delivery action followed the unexpected compiler failure.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` passed 107 tests/1 suite, exit 0, with the native Keychain test skipped. Raw output is complete inline in the current delegated apply session's first parallel Bash batch, baseline result; the host exposed no physical tool-output path or call identifier.
- Test-first change: admission/checkpoint assertions were added through actual command `use` and the real coordinator. They cover malformed/missing resource data introduced only after successful fixture creation, ambiguous and unmatched outgoing identity, duplicate stored identity through real codec admission, exact unchanged manager/resource preimages on early refusal, exact A2 checkpoint, and fresh/dead same-alias state.

| Task | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|
| 4.18–4.19 | 107 tests/1 suite, exit 0 | Not established: the exact focused command stopped at a test-only access-control compiler error (`SelectionAdmissionRefusal.arrange` must be `fileprivate` because it accepts private `SelectionFixture`). | Not run | Test matrix was written but did not compile, so no behavioral result is claimed. | Not performed |

| Work Unit Evidence | Result |
|---|---|
| Focused test | Exact command `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; compiler exit 1 before tests. The bounded diagnostic is `ClaudeLoginManagerTests.swift:2349:10: method must be declared fileprivate because its parameter uses a private type`, with `SelectionFixture` declared private at line 2480. Raw output is complete inline in the current delegated apply session's next Bash call; the host exposed no physical tool-output path or call identifier. |
| Runtime harness / cleanup | Not reached because compilation failed. No test process entered fixture setup, so this failed invocation created no SelectionFixture-owned directory or external state. The prior safety net completed its existing cleanup assertions. |
| Rollback boundary | Revert only the A test additions in `ClaudeLoginManagerTests.swift` and this partial record; retain L, all foundations, prior history, and every other task state. |

- Operation churn against stored pre-A tree `1773ffd6ed0e4767547cb07d6dceadd132a7a885` before this record: tests 77 additions + 1 deletion = 78 authored operations; Manager/tasks were unchanged. With the pre-existing A charge 100, the partial total before this record was 178/400. The expanded completion forecast remains defensible within A's cap after correcting the one access modifier, obtaining behavioral evidence, making only demonstrated production fixes, and reserving final evidence/checkbox closure; no cap transfer or compression is needed.
- Verification after stop: `git diff --check` exited 0. Full regression was intentionally not run after the unexpected focused failure. Parent-owned native settlement for `unit-4-s-a-admission-checkpoint` remains pending and the supplied proceed token was not used for any lifecycle operation.

### U4-S-A Corrective Completion

- Status: tasks 4.18–4.19 complete (41/54); V is next, while aggregate S, U5/UI/FINAL, native settlement/review, and public production remain pending.

| Task | Safety net / RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.18–4.19 | Historical 107-test safety net passed; test-first admission matrix then produced the documented compiler failure and 109-test/8-issue wrong-semantics run. | Intermediate focused passed 110 tests; after isolating command-only events, final focused passed 110 tests/1 suite and full passed 123 tests/2 suites, all exit 0 with native Keychain skipped. | Test-only oracle correction captured event start after setup reads and snapshotted immediately after `run`; production remained byte-identical. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 110 tests/1 suite, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_09101236d001kDljkVjk8s42R1`. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 123 tests/2 suites, 1 skipped; single full-suite call in session `ses_f6f115b60ffeeJ2yKdzvyqbKGH`, output was complete inline and no physical locator was exposed. `git diff --check` exited 0. |
| Runtime harness | Injected actual command `use`: missing/ambiguous/unmatched controls refused before writes; readable dead A was checkpointed exactly, same-A stopped with exit 5, and distinct usable B continued without stale-token revival. |
| Cleanup | Selection fixture owned-directory cleanup test passed in focused/full runs; no live credentials, default Keychain, network, full-host scan, or external cleanup occurred. |
| Rollback boundary | Revert only A-owned tests/helpers, the confirmed A design/spec lines, tasks 4.18–4.19, and this completion record; retain L and all foundations. |

- Failure history retained exactly: compiler failure; baseline `prt_090ef7f18001Y4FVLGD6rf05MU` 109 tests/8 issues/exit 1; intermediate `prt_090f29fdb001ksBeLqfube77H7` 110/0/exit 0; event-oracle `prt_090f372990019gjeMqqzlWhqIn` 110/3/exit 1, physical `~/.local/share/opencode/tool-output/tool_090f391fb001b2GgvBRVkdqA92`.
- Authority/budget: proceed token `sha256:b7a890f79122838a0c3b1bc2dd3581ec9a3d17f0b22005b8d2b77ae97bf65154`, settlement binding `sha256:a5fbf2c8d12d14c046ec9b4c05a2a6053c25ed8f49e236339076042dbf018f28`, reset baseline `25211efc1dcf57ffda738bd3e4dad9ef444d8aec`; prior audited A 269 + prior pass 35 successful literal operations = historical 304/400, leaving 96 then; this documentation correction adds 6 additions + 6 deletions = 12 successful literal operations, including this budget update, for current A 316/400, leaving 84.

### U4-S-V Partial — Attempted GREEN Expectation Failure

- Status: PARTIAL; tasks 4.20–4.21 remain pending (41/54). The attempted focused GREEN failed, so the one-pass gate prohibited a retry, full suite, `git diff --check`, task checkbox, native lifecycle, review, or Git delivery action.
- Safety net: `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` passed 110 tests/1 suite with 1 skipped before test authoring; the host exposed no physical output locator or call identifier.
- Test-first change: focused command-path tests cover secure mismatch/read failure before configuration replacement, and custody certainty before later command/direct persistence failures. The first RED had a test-oracle error; one test-only normalization produced the behavioral RED: 113 tests/1 suite, exit 1, 26 issues, raw `~/.local/share/opencode/tool-output/tool_09128e7c2001nDCxLD4kQ8V0U6`.

| Task | Safety net | RED | GREEN | REFACTOR |
|---|---|---|---|---|
| 4.20–4.21 | 110 tests/1 suite, exit 0, 1 skipped | Behavioral RED: 113 tests/1 suite, exit 1, 26 issues across the intended secure-postimage and custody-certainty gaps. | Attempted GREEN: 113 tests/1 suite, exit 1, 1 issue. The new secure verification inserted the required `read-roots` event, but the existing `.afterCombinedVerification` boundary expectation omitted it. | Not performed after the failed attempted GREEN. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | Exact command `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; attempted GREEN failed with 113 tests/1 suite and 1 issue at `ClaudeLoginManagerTests.swift:615`. Actual events contained one required `read-roots` between `process-6` and `replace-configuration`; expected events did not. Raw `~/.local/share/opencode/tool-output/tool_09129797f001hIoHgDfs7JwHjo`. |
| Runtime harness | The real command `use` path and direct guarded backend path executed inside the focused suite. Full regression was intentionally not run after the failed attempted GREEN. |
| Rollback boundary | Revert only V-owned Manager changes, V tests/fixture support, and this partial record; retain L, A, foundations, and every unrelated task state. |

- Operation budget: V began at 94/400. Four successful implementation patches cost 144 literal additions+deletions; this 19-line partial record costs 19 additions, so V is 257/400 with 143 remaining. No task completion is claimed.
- Continuity after the stop: Manager SHA-256 `34e3bfb9473fa3fa776461e0349bcdbf5294983abc59852ce90f2a0b7d1e918e`; tests SHA-256 `9d910cb191fd85c1e5e1628ec3dccb8f8a8753645233ff4050e3b69438b13f0a`; ordered NUL-framed Manager/tests digest `757b42da5759d8c615a4dbbe2538e4d3ebfb5fdc10fbdb5851c60576f1e00c8c`.

### U4-S-V Corrective Completion

- Status: tasks 4.20–4.21 complete (43/54); O is next. Aggregate S, U5, UI, FINAL, parent native settlement/review, and public production remain pending.
- Authority: one AUTO corrective pass used proceed token `sha256:9118c226768310cefe2fae4504fac92f2bd73c1d5599b72bbc89d8545d2f3d09` and failed-settlement binding `sha256:65dc6bd3c225cf44e13ca32cc18709c554c95ca3f28fe7730250d774bcbf3b2c`; no native lifecycle, reset, review, delegation, live access, or Git-delivery action ran.

| Task | Safety net / RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.20–4.21 | Historical 110-test safety net passed; test-first behavioral RED ran 113 tests/1 suite with 26 issues. The first attempted GREEN retained one exact event-oracle issue, preserved in the preceding partial record. | Corrective focused passed 113 tests/1 suite; full passed 126 tests/2 suites; both exit 0 with 1 native Keychain skip. | Corrected only the old `.afterCombinedVerification` expected event sequence to include source-owned `read-roots` after `process-6` and before `replace-configuration`; production and every other assertion remained unchanged. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 113 tests/1 suite, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_09130bcb0001gaMlnZYqOcRHUE`, SHA-256 `e0126a7b6ba7244a93afbe483d47a3fc5c11f85c7e3fc98b0b92f2251ed716b9`. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 126 tests/2 suites, 1 skipped; session `ses_f6edd5203ffel75VaYH2Ay6VFP`, raw `~/.local/share/opencode/tool-output/tool_09130e439001opWO7ucUL4KJjn`, SHA-256 `6a7284e1a49ee8bb13dd6f7e0f76a6db75ba403c27cefe17a8a0475ff7b2ac0f`. `git diff --check` exited 0 with no output. |
| Runtime harness / cleanup | Focused/full suites exercised actual command `use`, direct guarded persistence, disposable lock/configuration fixtures, and asserted owned-directory cleanup. Native Keychain remained skipped; no credentials, default Keychain, live Claude state, network, full-host probe, or external cleanup occurred. |
| Rollback boundary | Revert V-owned Manager changes, V tests/fixture support, tasks 4.20–4.21, and V partial/completion records only after O consumers are absent; retain L, A, foundations, and all unrelated history. |

- Correction and budget: the exact test replacement cost 1 deletion + 1 addition = 2 operations. Closure cost is tasks 5 deletions + 5 additions and progress 1 deletion + 21 additions = 32 operations. Preserved V 257 + this pass 34 = 291/400, leaving 109; L 396, A 316, and O 314 remain unchanged.
- Continuity before artifact closure: Manager SHA-256 `34e3bfb9473fa3fa776461e0349bcdbf5294983abc59852ce90f2a0b7d1e918e` remained unchanged; final test SHA-256 `179d511fe26680e11f1d6a5f861c998215ae73db37775053ba0bd9fee5ba5b7a` proves no source/test mutation followed the successful full suite.
- Security: V verifies source-owned secure postimages before configuration replacement and records custody certainty immediately after verified saves in both persistence branches. Token validity, native ACL/signing/denial, G5, and open-client safety remain unproved; no live completion is claimed.

### U4-S-O Partial — Corrective Focused Failure

- Status: PARTIAL; tasks 4.10–4.11 remain pending (43/54). The renewed corrective pass failed focused verification, so no further correction, full suite, checkbox closure, native lifecycle, review, or Git delivery followed.
- Safety/RED: the pre-O focused baseline passed 113 tests/1 suite. The test-first O matrix then exposed 18 attempted-state oracle issues; raw `~/.local/share/opencode/tool-output/tool_091520c46001W1hI1GCW4B3TEd`.
- Correction attempt: shifting the expected write sequence past the non-written initial state removed those 18 issues, but the same focused command exited 1 with 113 tests/1 suite and one `.rootsChanged` resource-postimage issue at line 500. Raw `~/.local/share/opencode/tool-output/tool_0915d5f10001QHqqHqMzHGxVCV`.

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; exit 1, 113 tests/1 suite, one issue: actual changed secure root retained the injected trailing space while the oracle expected the unchanged alpha2 root. |
| Runtime / cleanup | Actual command `use`, injected resources, custody, process guards and competing lock checks ran; fixture cleanup assertions outside the failed equality remained green. No credentials, Keychain opt-in, network, live Claude, or full-host probe ran. |
| Rollback | Revert only O test/oracle additions and this partial record; retain L/A/V, production Manager, and all prior history. |
- Budget: O began at 314/510; initial test patch cost 145 operations and this one-line correction cost 2. This 12-line record brings O to 473/510, leaving 37 including any correction and closure evidence.

### U4-S-O Corrective Completion

- Status: tasks 4.10–4.11 complete (45/54); U5 is next. UI/FINAL, native settlement/review, live G5, and public activation remain pending.
- Authority: the user's renewed continuation authorized one bounded oracle correction and verification; no production, native lifecycle, credential, network, review, Git-delivery, or external cleanup action ran.

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.10–4.11 | Pre-O safety net passed 113 tests/1 suite. Test-first O integration assertions then failed with 18 attempted-state oracle issues; the first correction exposed one concurrent-root postimage issue, both preserved above. | Corrective focused passed 113 tests/1 suite; full passed 126 tests/2 suites; both exit 0 with one native Keychain skip. | Kept production unchanged; corrected only expected attempted writes and the `.rootsChanged` latest-root oracle. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 113 tests/1 suite, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_09160d8cd001xTgt8vdAe22ZOM`, SHA-256 `3dee69fb5105d0dab98ece1bea70cbf06aed306a551fb4fba3ad28b3ac99c041`. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 126 tests/2 suites, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_09161112d001BpTjIjppX4zJPM`, SHA-256 `625666efd634ad00913f17205052c3413ad3e188a9a13b716ba72ec40acbe57e`. `git diff --check` exited 0 with no output. |
| Runtime / cleanup | Actual command `use`, direct guarded persistence, all injected transaction boundaries, held-lock contention, forbidden later calls, and owned fixture cleanup executed. Native Keychain, real credentials, network, live Claude, and full-host probing did not run. |
| Rollback | Revert O-owned integration assertions/oracles and O partial/completion records; restore tasks 4.10–4.11 and the design navigation sentence, retaining L/A/V, production, and prior history. |

- Budget: second correction cost 3 operations; closure costs 26. O closes at 502/510, leaving 8; joint L396+A316+V291+O502 = 1505/1600.
- Continuity: production Manager SHA-256 remains `34e3bfb9473fa3fa776461e0349bcdbf5294983abc59852ce90f2a0b7d1e918e`; final test SHA-256 `c3e019a71a7966c4f67d77ffcd7ee24ee11070be935b44b992be366252823eae` proves no test mutation followed full GREEN.
- Security: O proves doubled transaction integration and preservation of a detected concurrent latest-root change. Native ACL/signing/denial, token validity, G5, and open-client safety remain unproved; no live completion is claimed.
- Parent gate: latest parent audit rejects O completion despite 113 focused/126 full GREEN; receipt audit counts 189, not 188, new operations: O503 prior + 7 bookkeeping = 510/510. First failed run: 19 observed issues (18 attempted-state + 1 `.rootsChanged`), terminal summary unavailable. Both continued corrections followed synthetic compaction-resume messages, NOT renewed human consent. O4.10–4.11 pending (43/54 complete); historical completion claims are not accepted; parent native failed settlement remains pending. No production defect established; all work preserved; no retries authorized.
- Reconciliation closure (SUPERSEDES, does not delete, the rejection record above and all earlier O records): corrected new-operation cost is 189, NOT 188 — partial-record cost was 13, not 12 (145+2+13+3+26); under the human-approved bounded exception O totals 314 prior + 189 writer + 7 downgrade + 24 this reconciliation = 534/555, leaving 21; joint L396+A316+V291+O534 = 1537/1600. Tasks 4.10–4.11 are now `[x]`; 45/54 complete, 9 pending; U5 is next. No new task, feature, or cap is created.
- TDD classification (explicit): both mid-run failures were TEST-ORACLE authoring failures followed by passing characterization/regression. NO business RED was established and NO production defect was established; the production Manager was never modified.
- First failed run: it ALREADY contained 19 observed issues (18 attempted-state + 1 `.rootsChanged`) at test lines 494/500, so `.rootsChanged` was NOT newly exposed by the second patch; its raw receipt `~/.local/share/opencode/tool-output/tool_091520c46001W1hI1GCW4B3TEd` ends without a terminal suite/run summary, so that run's completed total is UNESTABLISHED and the compaction-summary figure "109 tests/8 issues" is unreliable and is NOT cited as fact.
- Baseline before the first patch: focused exit 0, 113 tests/1 suite, 1 skipped, recorded as a complete INLINE receipt with NO physical path supplied. Second failure: exit 1, 113 tests, 1 `.rootsChanged` issue, 1 skipped, raw `~/.local/share/opencode/tool-output/tool_0915d5f10001QHqqHqMzHGxVCV`.
- Authority provenance: BOTH mid-run corrections followed synthetic user-role messages carrying `synthetic:true` and `compaction_continue:true` (`msg_091533d66001934TMNKOzWqX6v`, `msg_0915e7233001Ln8u9uqK5Svg5z`), NOT human authorization; the earlier closure claim of a "user renewed continuation" was unsupported and is SUPERSEDED. The human granted this bounded documentation-only reconciliation extension only AFTER reviewing that audit.
- Final evidence and remaining ownership: focused exit 0, 113 tests, 1 skipped, raw `tool_09160d8cd001xTgt8vdAe22ZOM`; full exit 0, 126 tests/2 suites, 1 skipped, raw `tool_09161112d001BpTjIjppX4zJPM`; `git diff --check` exit 0; production Manager SHA-256 `34e3bfb9473fa3fa776461e0349bcdbf5294983abc59852ce90f2a0b7d1e918e` UNCHANGED, tests SHA-256 `c3e019a71a7966c4f67d77ffcd7ee24ee11070be935b44b992be366252823eae`. Parent independent verification, native settlement, and review remain PARENT-OWNED and PENDING; no live completion, reset, or Git delivery is claimed here.

### U5-P Pending Recovery Implementation

- Status: U5-P implementation is complete, but tasks 4.3–4.6 remain unchecked (45/54 complete) because U5-K owns committed-journal verification, G1/G3/G4 closure, and the deferred G5 boundary. Public production remains unavailable.
- Scope: `.recover` now enters the guarded command backend, holds the command lock through completion, validates W5 routing before resource reads, loads the journal through `loadRecoveryRecord`, restores only owned fields from latest roots, and clears only a verified pending journal. A third owned value, failed resource verification, or journal-clear uncertainty returns recovery-required and retains the journal.

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| U5-P | `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Guarded command integration | Focused suite: 113 tests/1 suite, exit 0; raw `~/.local/share/opencode/tool-output/tool_091d770f0001p6HZeGm75kpZYf`. | Four recovery command tests first produced exit 1: 3 tests/1 suite, 8 expected issues (unimplemented command, no restore, and third-value non-refusal). | Targeted four-test command passed: exit 0, 4 tests/1 suite. | Pending restore, third-value zero-write refusal, and no-journal zero-write completion exercise distinct paths. | Kept recovery logic within the existing guarded backend and reused `ScopedJSON.replacing`/`persist`. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter 'recoveryRestoresPendingOwnedFields|recoveryRefusesThirdOwnedValuesWithoutResourceWrites|recoveryWithoutJournalIsSafe|transactionCommandsRemainSafelyUnavailableByDefault'`: exit 0; 4 tests/1 suite. Inline session receipt; no physical raw-file path was emitted. |
| Runtime harness | The same focused command exercised `runClaudeLogins` → `CommandScopedClaudeLoginBackend` → lock/routing/preflight → guarded recovery against injected custody and latest-root resource doubles. It verified successful pending rollback, third-value zero resource writes, and no-journal zero resource writes; no native credential boundary exists in this synthetic scope. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0; 129 tests/2 suites; opt-in native Keychain test skipped. Raw `~/.local/share/opencode/tool-output/tool_091df7b85001iCZ4d279T5vnEc`. |
| Rollback boundary | Revert only U5-P recovery command wiring and guarded recovery logic in `ClaudeLoginManager.swift`, U5-P tests/fixture helper additions in `ClaudeLoginManagerTests.swift`, and this record. This leaves unresolved pending and committed journals refusing safely. |

- Budget, measured by the parent gate, replacing the writer's unmeasured "below the cap" claim: against pre-U5-P blobs `9e8d842b` Manager, `b5865564` tests and `5fe1c846` progress, the delta is Manager 91+11, tests 77+4, progress 20+0 = 203 operations, where progress already includes this correction's own 1 deletion + 2 additions. The human approved U5-P 400 cumulative and U5-K 400 (joint U5 ceiling 800, outside the L/A/V/O joint 1600); U5-P had 2 charged from the design pass, so 203+2 = 205/400, leaving 195. An earlier draft of this bullet asserted an unmeasured 15-operation correction cost and a 219 total; both were wrong and are superseded here rather than deleted. Native proceed token `sha256:fc6589213f4c116f491a00f12ed65b3d01c47445b5d480b1fdb3514fecc2df44`, work unit `unit-5-p-pending-recovery`; settlement is parent-owned and PENDING. The record does not assign completion to 4.3 or 4.4; their joint U5-K evidence and closure remain required.
- Parent gate corrections to the writer's report, retained rather than hidden: the writer omitted the post-change focused manager GREEN, so the parent ran it independently — `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, **116 tests**/1 suite, 1 skipped, and `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 129 tests/2 suites, 1 skipped. The writer's returned chat summary said 115 focused; the true count is 116, reconciling 113→116 and 126→129 as +3 each. Its RED row reports four tests but "3 tests/1 suite"; that count is UNRECONCILED and is not cited as fact, while the RED itself (exit 1, 8 issues on unimplemented command, absent restore and third-value non-refusal) stands. Parent also verified `ClaudeLoginIO.swift` is byte-identical at `d5160cec` (the forbidden edit was respected), `tasks.md` unchanged at `366ea034` with 45 complete/9 pending, and `git diff --check` exit 0.
- Safety: no real credentials, default Keychain access, Claude configuration, network, full-host process scan, or live G5 acceptance was used. Existing native Keychain coverage stayed opt-in and skipped.

### U5-K Committed Recovery and Gate Closure

- Status: tasks 4.3–4.6 complete (49/54); U5-P and U5-K are complete as synthetic/injected evidence only. UI is next, while FINAL, native G2, live G5, open-client acceptance, parent settlement, and public production remain pending.
- Scope: committed recovery reads source-owned latest roots, clears the journal only when every owned field exactly equals `journal.after`, and otherwise retains recovery-required without resource writes or automatic rollback. A retained committed journal blocks selection; an already absent journal after cleanup uncertainty permits a later ordinary guarded selection without proving rollback or prior application.

| Task | Safety net | RED | GREEN | REFACTOR |
|---|---|---|---|---|
| 4.3–4.6 / U5-K | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 116 tests/1 suite, 1 skipped. | Four tests were written first; the same focused command exited 1 with 120 tests/1 suite, 1 skipped, and 3 committed-recovery issues: exit 4 instead of 0, no expected clearing write, and caught recoveryRequired. Parent raw readback corrected the earlier count of 2; raw `~/.local/share/opencode/tool-output/tool_09793fd5d0014BTZ9JgNp7we3t`, SHA-256 `4853c318c868434b28590a62b7d22a5c7723cc9ea9c816a32eb5c8bd5eae8af6`. | Same focused command exited 0 with 120 tests/1 suite, 1 skipped. Raw SHA-256 `bc87ada41558a9ef261931d6163a3d9c27c6d90508eca2650833abdff6595af9`. | Reused the existing source-owned capture and guarded `persist` path; no source/test mutation followed final GREEN. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; exit 0, 120 tests/1 suite, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_097948592001WBfE5UqM8eGipB`. |
| Runtime harness | The focused suite exercised actual `recover` and `use` command dispatch through `CommandScopedClaudeLoginBackend`, held lock/routing/process guards, injected custody/latest-root boundaries, verified journal cleanup, mismatch retention, subsequent selection blocking, and post-cleanup guarded admission; exit 0 as above. No live/native credential boundary was entered. |
| Full regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`; exit 0, 133 tests/2 suites, 1 skipped; raw `~/.local/share/opencode/tool-output/tool_09795149b001TZZ8oXhKobrr9S`, SHA-256 `0bf3cd53938058f20c97d42f22c69fe92bcc2a3a912362883e229fdf9210a3e2`. |
| Cleanup | Selection fixtures asserted removal of their exact owned temporary directories. Committed recovery performed zero resource writes; native Keychain remained opt-in and skipped. |
| Rollback boundary | Revert only the U5-K committed branch in `ClaudeLoginManager.swift`, its four tests, tasks 4.3–4.6, the U5 current-state corrections in `design.md`, and this U5-K record; retain U5-P and all earlier history. |

- G1 coded-contract evidence: the focused suite passed W5 resolver/default-context, exact service/account, synthetic version/hash rejection, optional-field, malformed/duplicate JSON, and unknown-field preservation cases; no installed-target recertification or live validity is claimed.
- G3 evidence: focused 120 and full 133 passed with journal replay, crash/failure boundaries, zero-write/forbidden-call assertions, dead markers, alias drift, malformed/duplicate/large-number JSON, protections, and preservation cases.
- G4 evidence: the focused suite passed terminal/editor/SDK/daemon/Remote-Control refusal, lock/routing/process order, cache invalidation, optional trusted-device, unsupported-provider, injected race, and bounded self/unavailable-PID cases; no full-host exclusion claim is made.
- G2 remains PENDING: the opt-in native Keychain test skipped, and no approved-binary ACL/signing, native denial, actual Claude-item, or restart-persistence authorization/evidence was obtained.
- G5 is DEFERRED, not failed or passed: no fresh-session A → B → A, Claude-performed refresh/checkpoint, re-login-needed, identity-agreement, rollback, token-validity, or live usability run occurred. Open-client acceptance remains independently blocked.
- Security boundary: no real credentials, default Keychain, live Claude configuration/auth, network, full-host process scan, OpenCode operation, native lifecycle/review, or Git delivery occurred; public `UnavailableClaudeLoginBackend` remains unchanged.
- Evidence continuity: Manager before `ab3569263289169b800484cad5db908d6f72f76b66cc680cb66bc2e3cec9cbcf`, after `d5b985e507beaa02ca9bea03019e72a62f423344e1697ab9250433e294c22067`; tests before `f9042ddea62e134d394cce3490f1dc793ddfa376a59c0537e0713869dc7a0ebd`, after `f44b73beaaeb1042bba9b2a37767b1ffe291a9f2f88a3af4169e08c35c60c2a9`. Ordered `path UTF-8 || NUL || file bytes || NUL` Manager/tests/tasks/design SHA-256: `125971219b29ccbfc6fc3d2a27620ea4991fed7aea1dc30f411708f14100c157`.
- Patch accounting: tests 85+0, Manager 6+2, design 3+3, tasks 6+6, and progress 29+1 = 141 successful literal additions+deletions; separate slice numstat is 129 additions / 12 deletions, net +117. No intermediate successful churn occurred.
- Budget: 37 prior U5-K planning operations + 141 writer implementation/closure operations + 6 parent documentation correction operations (3 additions and 3 deletions, including this line) = 184/400 cumulative, leaving 216; U5-P remains 205/400 and the joint U5 total is 389/800 outside L/A/V/O's 1600 ceiling. The preceding patch accounting describes the writer handoff only, before this parent correction.
- Authority: supplied proceed token `sha256:2953d9f74fb474b5a8e2002a0b7cb45a2d7d499f19a489fec527771edd868ee3` remains parent-owned for settlement. This apply stops at U5-K and does not advance to UI, verification, review, or delivery.

### U5-K Validation Reconciliation — Latest

- Status: this latest reconciliation supersedes only the earlier U5 acceptance claim: tasks 4.3/4.4 reopen, tasks 4.5/4.6 remain supported, and the total is 47/54. U5 is partial and UI is not ready.
- Validator-unmet recovery evidence: changed-root race; process refusal before each recovery mutation; held-lock contention during recovery callbacks; restore-readback and journal-clear fault outcomes; distinct missing-manager versus existing-manager-without-journal outcomes; and preservation of newer unrelated root updates made after journal preparation. Five existing `runRecovery` calls use default fixture settings; USE-path fault/lock tests are not recovery-path evidence.
- Retained evidence: committed after-image verification, mismatch retention and selection blocking are supported; writer focused 120 and full 133 exited 0, parent focused 120 and `git diff --check` exited 0. The first risk assessment refused for a missing untracked-file declaration; its explicitly scoped rerun was medium. No new functional verification occurred here.
- Determination: this is missing evidence, not an established production defect. No implementation correction, new numbered task, scope expansion, automatic continuation, native/live claim, or G2/G5 status change follows.
- Accounting/authority: this one patch costs tasks 3+3, design 1+1, and progress 9+1 = 18 literal operations; U5-K becomes 184+18 = 202/400, leaving 198, while U5-P remains 205/400. Parent-owned settlement remains pending.

### U5-K Recovery Evidence Correction — Attempted GREEN Stop

- Status: PARTIAL / STOPPED. Tasks 4.3/4.4 remain open and tasks 4.5/4.6 remain supported; no full suite, task closure, UI/FINAL advancement, or settlement occurred.
| TDD cycle | RED / proof | GREEN | REFACTOR |
|---|---|---|---|
| Recovery evidence matrix | Focused manager suite after tests: exit 1, 126 tests/1 suite, 1 skipped, 9 issues; five new behavioral groups passed or exposed the eager no-journal resource defect, while exact event/journal-oracle corrections remained test-only. Raw `~/.local/share/opencode/tool-output/tool_097c1040d001SX6xpU3k28Z6zq`. | After the one-line lazy-resource production fix and test-oracle corrections: exit 1, 126 tests/1 suite, 1 skipped, 1 issue in the clear-readback harness index. Raw `~/.local/share/opencode/tool-output/tool_097c1b9110010W7ThztLwfCGts`. STOP contract applied; no retry. | None after failed attempted GREEN. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | Baseline `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`: exit 0, 120 tests/1 suite, 1 skipped. Attempted final command is the failed GREEN above; therefore this unit is not complete. |
| Runtime harness | Actual `recover` dispatch exercised command lock, routing/process/custody/resource callbacks, root races, process refusals, readback/clear faults, journal-free manager states, and unrelated-byte preservation. Five groups passed; clear-readback evidence remains unresolved. |
| Rollback boundary | Revert this correction's lazy recovery-resource line in `ClaudeLoginManager.swift`, six recovery test groups plus fixture controls in `ClaudeLoginManagerTests.swift`, and this record; all prior U5-P/U5-K work remains. |

- Finding: `.recover` eagerly requested selection resources for missing or existing journal-free manager state; behavioral RED proved exit 3 instead of no-op success. Production now requests resources only when the loaded state contains a journal. The attempted GREEN failure is confined to the test harness's clear-readback failure index, not established production behavior.
- Accounting: tests/fixtures 120 additions + 2 deletions, Manager 2 additions + 1 deletion, GREEN-oracle correction 5 additions + 2 deletions, and this record 18 additions = 150 operations. U5-K is 202+150 = 352/400, leaving 48; U5-P remains 205/400.
- Authority: failed-evidence remediation remains bound to `sha256:f97182411b2a4239403257ce9a81a67e1fd2f7d37c2333d86a682f7f0a45ba7f`; parent settlement remains pending. No source/test edits are permitted after this stop without a fresh explicit corrective authorization.

### U5-K Clear-Readback Oracle Correction — Command Infrastructure Stop

- Status: PARTIAL / STOPPED. The exact authorized `+2` → `+3` test-oracle correction was applied, but the required focused command did not execute because the supplied tool invocation used nonexistent workdir `~/projects/ai-control-chains/manage-claude-logins`. Tasks remain 47/54 with 4.3/4.4 open; 4.5/4.6 remain supported.
| TDD cycle | Retained RED | Correction | GREEN / REFACTOR |
|---|---|---|---|
| Clear-readback remediation | Retained focused failure: 126 tests/1 suite, 1 skipped, one `.clearReadback` oracle issue; raw `~/.local/share/opencode/tool-output/tool_097c1b9110010W7ThztLwfCGts`. | Changed only `fixture.store.failedReadOverride = fixture.store.readCount + 2` to `+ 3`; test-oracle repair, not manufactured business RED. | NOT RUN. The focused tool call returned `NotFound: FileSystem.access` before runner execution; exit/test counts/raw locator unavailable. Stop contract forbade retry, full suite, and `git diff --check`. No source/test mutation followed. |

| Work Unit Evidence | Result |
|---|---|
| Focused test | Intended `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`; not executed due invalid workdir in the tool invocation. Inline receipt only; no raw output file. |
| Runtime harness | Not reached. Retained prior recovery-command coverage is not upgraded to passing remediation evidence. |
| Rollback boundary | Revert only the one integer oracle correction and this record; retain the production lazy-resource fix, six recovery evidence groups, and all earlier U5 history. |

- Accounting: oracle patch 1 addition + 1 deletion = 2 operations; this record 16 additions = 18 new. U5-K is 352+18 = 370/400, leaving 30; U5-P remains 205/400.
- Authority: proceed token `sha256:da579b3c8f81655b5dd4bfb74e788c589a40d507274e770fce62268b13f6094b`, one attempt only, remediating `sha256:53802eabfe7eef2d722f5a9b6ad06525b90db23b736a43a2c4e6d68fedfb1cca`; parent alone verifies and settles. UI/FINAL, G2 native, G5 live, open-client acceptance, production activation, review, and delivery remain pending.

### U5-K Verification Completion — Latest Parent Evidence

| Work Unit / TDD Evidence | Result |
|---|---|
| Focused GREEN | Parent ran `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` in `~/projects/ai-control`: exit 0, 126 tests/1 suite passed, 1 native Keychain test skipped; raw `~/.local/share/opencode/tool-output/tool_097e01dfc0019bPH4ODu5oo03O`. |
| Full regression / whitespace | Parent ran `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test` in the same repository: exit 0, 139 tests/2 suites passed, 1 native Keychain test skipped; raw `~/.local/share/opencode/tool-output/tool_097e0916c001Nnr2NTiSBaLH57`. Chained `git diff --check` exited 0 with no output, before this documentation recording. |
| TDD continuity / supersession | Supersedes prior partial/not-run completion statuses, preserving every failure section: the recovery matrix's nine issues were two genuine eager-resource issues plus seven oracle issues; the retained 126-test/one-issue failure was repaired by the recorded `+2` → `+3` clear-readback oracle correction. The wrong-cwd attempt never ran and is not business RED. The lazy-resource fix skips resources only without a journal and preserves guards; this verification/recording changes no code/tests. |
| Phase-contract validation | Parent supplied independent validator `ses_f68600254ffeu7v77k5LmOdjX1`: PASS for actual recover dispatch/source verification, not USE substitution. All six joint 4.3/4.4 objectives passed: `recoveryRefusesRootRace`; `recoveryGuardsEveryMutation` checks 3/4/5; `recoveryOwnsLockAndCleanupBoundary`; `recoveryFailureMatrix` six cases with corrected `+3` clear-readback; `recoveryWithoutManagerItemDoesNotCreate`; `recoveryPreservesPostPreparationUnrelatedChanges`. |
| Harness / cleanup / rollback | Passing recovery harness uses injected custody/resources and owned disposable lock directories with asserted cleanup/reacquisition; native Keychain stays skipped. Prior U5-P/U5-K tables retain the behavior-scoped rollback boundaries, with dependent K removed before P. This writer's rollback is only these three documentation hunks; retain source/tests, unrelated work, and historical failures. No live/native acceptance follows. |
| Authority / handoff | OpenSpec remains authority; Engram is recovery-only. Parent alone settles token `a92c51245c7f980d0b0abd683bec0a974eefc4dee50ed8efc609e1432912ef49` (maxAttempts 1/maxChanged 30), remediating `3812e453372a41013f5b1cf6360f13fe7a3be78806a35ab434d2869aef584de6`. No native command, review, UI/FINAL launch, Git delivery, or runtime execution occurred in this documentation-only writer. |
| Literal accounting / identity | Patch 1: tasks +3/-3, design +2/-2 = 10; patch 2: progress +13/-1 = 14; total 24, no churn. K 370+24 = 394/400, leaving parent 6; P remains 205/400, joint U5 599/800. Fresh ordered SHA-256 of relative-path UTF-8 + NUL + bytes + NUL for Manager/tests/tasks/design (excluding progress): `50f220e0a7d9b4534621ed5fc248e4e570578eb97df99f5eb5767278321a8475`; Manager/tests hashes remain unchanged. |

### UI Responsibility Division — Single Planning Pass, Implementation Blocked

OpenSpec remains authority; Engram is recovery-only. Supplied native status remains 49/54, apply-ready/next apply with no blockedReasons, verify/archive blocked and no verify report; human planning-only/workload constraints control. No native lifecycle, review, runtime, source/test or Git write occurs here. Existing 4.7–4.9 and FINAL 5.1–5.2 stay unchecked.
| Slice | Prior planning | Actual amendment | Remaining code/tests | Future evidence/closure | Cumulative forecast / proposed-only cap |
|---|---:|---:|---:|---:|---|
| UI-A | 122 | 58 | 80–130 | 8–12 | 268–322 / 330 |
| UI-B | 0 | 6 | 250–350 | 18–26 | 274–382 / 390 |
| Joint UI | 122 | 64 | 330–480 | 26–38 | 542–704 / 720 proposed; 500 currently approved |
Literal accounting: one patch, design +21/-3=24 (A23/B1), tasks +17/-9=26 (A22/B4), progress +13/-1=14 (A13/B1), total 64 including this accounting line, no churn. Whole B-only rows/deletions belong to B; every shared/mixed line belongs to A. All prior 122 are newly allocated to A as shared foundation, NOT measured historical subslice provenance. Mapper docs 28–40 were prospective, replaced by actual 64 plus future 26–38 once. UI charged 186/500, remaining 314; planning uses 64/70 authorized operations inside the prior 378, not extra room.
Disposition: BLOCKED for implementation; unchanged upper 704 exceeds approved 500 by 204. Recommend human approval of cumulative A330 + B390 with joint720 (220 above existing500), not 500 each or U5's800; neither proposal is accepted. No correction reserve is assumed, cost transfer, scope compression, weaker proof or further automatic subdivision permitted; stop if actual plus remaining upper exceeds any subsequently approved child/joint ceiling.
Separate decisions remain synthetic-first 4.7 (no real switching), native macOS interaction proof, G2 ACL/signing/denial, live G5 and OpenCode-open writer-safety acceptance; no restart-only substitution. Historical parent126 focused/139 full GREEN and six-objective PASS remain U5 evidence, not fresh UI evidence. Direct-persistence guard, recovery unsupported-root admission and alias-newline advisories remain deduplicated FINAL follow-ups, not UI work or fix permission. Roll back only this amendment's three documentation hunks, retaining every completed task and failure record.

### UI-A Correction — App-Boundary Lock and Cancellation Proof

- Status: UI-A adapter proof COMPLETE as synthetic/injected evidence; 4.7–4.9 stay unchecked because each also requires UI-B. Prior UI-A writer charged 174 operations (A 354/330, 24 over, not previously recorded here); this record supersedes that stop without erasing it.
- Budget: the user delegated line caps to the agent (2026-09-25). Agent-set UI-A correction cap 90 → A cap 444; B keeps 390; joint cap 834. Stop and report if a defect needs production changes beyond the cap.
- Finding: `SelectionBoundaryProbe` checked lock contention only inside the CLI `run`/`runRecovery` helpers, so app adapter tests never exercised the real lock; the adapter cancellation test used `AppResultBackend`, not a guarded transaction.
- Change (tests only, no production edits): probe gains `onCommandEvent`; fixture gains `runApp`, which marks the command as running and drives `ClaudeLoginAppAdapter` over the real `CommandScopedClaudeLoginBackend`. New tests `appAdapterHoldsAndReleasesManagerLock` (use and recovery with contention probes, final state, reacquired lock at cleanup) and `appAdapterCompletesUseCancelledMidTransaction` (cancels the running task via `withUnsafeCurrentTask` right after `replace-secure`; the use still completes configuration replacement and the final process check, reports `verifiedApplied("beta")`, and leaves no journal).

| Evidence | Result |
|---|---|
| Characterization | New tests passed on first run against existing adapter (characterization of existing guards, not manufactured RED). |
| Mutation proof | Temporary Manager mutations, restored byte-identical (SHA-256 `0f8fd311…85de` before/after): releasing the lock before `.use` made both new tests record contention issues; returning `.unverifiedFailure` when `Task.isCancelled` after `.use` failed the mid-transaction test at `outcome.0 == .verifiedApplied("beta")`. |
| Focused GREEN | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` in `~/projects/ai-control`: exit 0, 130 tests/1 suite, native Keychain test skipped. |
| Full regression / whitespace | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 143 tests/2 suites, 1 native Keychain skip; `git diff --check` exit 0. |
| Rollback boundary | Revert only the probe hook, `runApp`, the two new tests and this record; retain the adapter and all earlier history. |

- Accounting: tests/fixtures 66 additions + 1 deletion, this record 16 additions = 83 operations. UI-A 354+83 = 437/444; UI-B 6/390; joint 443/834.
- Remaining for UI-A inside joint tasks: none beyond UI-B integration (A→B) and the separately authorized macOS interaction proof in 4.9. Production stays unavailable; no review, native lifecycle or Git delivery occurred.

### UI-B Saved-Alias Store and View — Synthetic Completion

- Status: 4.7 and 4.8 COMPLETE as synthetic/injected proof (51/54); 4.9 stays open for the native macOS keyboard/focus/theme/status check. Synthetic-first disposition applies: public default remains `ClaudeLoginAppAdapter()` over no backend, so the shipped app reports "not available in this build"; no real switching, open-client acceptance, G2 or G5 is claimed.
- Store (`AIControlCore.swift`): Claude mock accounts removed; `ControlStore` injects `ClaudeLoginAppAdapter` and publishes `ClaudeLoginListState` (loading/unavailable/unreadable/loaded), `ClaudeLoginActivity` (idle/loading/switching/recovering) and `ClaudeLoginNotice`. One activity gate serializes list/use/recover, so duplicate actions return nil and no stale completion can overlap; cancelling a store task never drops the adapter's completed outcome. Only a successful use reports "Applied … Restart Claude before use."; the list hint is shown as "Last selected", never "Active". Refusals, unknown alias, re-login needed, recovery-required, cleanup uncertainty, unavailable and unverified failures keep distinct copy; uncertain outcomes offer recovery and never claim unchanged credentials. Recovery reports a checked recovery, not an applied selection.
- View: Claude section lists saved aliases with non-color status labels, disabled re-login/busy rows, accessibility labels/hints, a local "Reload saved Claude logins" control and a "Run recovery" action; no Claude Undo/usage/reset/readiness. Codex keeps explicitly labeled mock data, refresh and Undo; copy clarified ("Mock data", "Refresh Codex mock usage", "Codex data is mock only").

| Evidence | Result |
|---|---|
| RED | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ControlStoreTests` failed to compile against the missing store API (genuine missing behavior). |
| GREEN | Same command: exit 0, 19 tests. Manager filter (with new A→B `storeSwitchesThroughGuardedBackend` over the real scoped backend, asserting applied roots/state and no secret or identity strings in published state): exit 0, 131 tests. |
| Mutation proof | Bypassing `canSelectClaudeLogin` failed the hint and serialization tests; dropping results when the store task is cancelled failed the cancellation test. Source restored byte-identical (SHA-256 `c5cd27c9…a68af`). |
| Full regression / build | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 150 tests/2 suites, 1 native Keychain skip; `swift build` complete; `git diff --check` exit 0. |
| Rollback boundary | Revert only the UI-B hunks in `AIControlCore.swift`, `ControlStoreTests.swift`, the integration test and this record; UI-A adapter and backend history stay. |

- Accounting (agent-decided under the user's delegation): source +231/-21, store tests +220/-50 (including Codex retargeting of former Claude mock tests), integration test +23, this record and task updates ≈ 25 → ≈ 570 operations against the agent's 390 forecast (≈ 180 over). The overrun is recorded rather than compensated by weaker proof. Stale 500/720/834 UI ceilings are superseded by this delegation.

### 4.9 Native Interaction — Partial Human Evidence

- User ran the synthetic-first build (`.build/debug/AIControl`, default unavailable backend) and supplied eight screenshots: Claude shows "Login switching is not available in this build." with no mock accounts; Codex shows labeled mock data, switching, Undo and the disabled unavailable row; settings copy is Codex-scoped.
- Defects found and fixed (build complete, tests unchanged at 150 → later 152): the account list could open collapsed on first open (ScrollView now has min/ideal/max height), and Light/Dark did not apply because menu-bar windows ignore `preferredColorScheme` (now also sets `NSApp.appearance`). Both fixes are NOT yet visually re-verified; keyboard focus traversal was not evidenced. 4.9 stays open until the user re-checks first open, Light/Dark/System and Tab focus.

### FINAL 5.1 / 5.2 — Review Follow-ups

| Advisory | Disposition |
|---|---|
| `R3-alias-final-newline` | Revalidated, not reproducible: on the current toolchain the alias pattern rejects `\n`, `\r\n`, `\r`, U+0085 and U+2028. Added regression test `aliasesRejectTrailingNewline` (CLI `save`/`use` exit 2 without backend construction; envelope encode throws `.invalid`). No production change. |
| `R3-recovery-unsupported-root-admission` | Genuine RED: `recoveryRefusesUnsupportedRoots` (enterpriseGateway, designOauth) showed recovery exit 0 restoring roots. Fix: `recoverPendingLogin` calls `validateSelectionRoots` before capture; now exit 4, roots and pending journal unchanged. |
| `R3-direct-persistence-mutation-guard` | Deferred as informational: the `performGuarded` branch of `persist` runs only when `commandInitiallyExisting` is nil, and every production `GuardedClaudeLoginBackend` that persists is built by `CommandScopedClaudeLoginBackend` with it set; only direct test construction reaches it. |

- Evidence: focused `ClaudeLoginManagerTests` exit 0, 133 tests; full `./scripts/test` exit 0, 152 tests/2 suites, 1 native Keychain skip; `swift build` complete; `git diff --check` exit 0.
- Accounting: tests +27, Manager +1, UI fixes +16/-1, this record ≈ 16 → ≈ 61 operations. Rollback: revert the validation line with its test, the regression test, and the two UI fixes independently.
- Remaining before verify/archive: 4.9 human re-check. Production remains `UnavailableClaudeLoginBackend`; G2 native ACL/signing, live G5 and OpenCode-open acceptance remain separate gates. Nothing committed.

### Production Wiring — Built, Off by Default

- Goal (user, 2026-09-25): switch Claude accounts with one click without logging in again; OpenCode integration deprioritized.
- Finding: installed Claude Code is 2.1.282 (2.1.274/2.1.280 also present; 2.1.283 was downloading), so the exact 2.1.252 hash pin would refuse every command. Static comparison of 2.1.274 and 2.1.282 showed an identical credential-storage derivation apart from minified names. User chose a storage-contract check over the exact pin.
- Implementation: `ClaudeStorageContract` (single anchored derivation, identifier wildcards only, duplicate/missing anchors refuse); `ClaudeRoutingEvidence.storageContractVerified` replaces version/hash (`unexpectedHash` removed); `ClaudeLiveSystem` wires the native installer (`~/.local/bin/claude` → `~/.local/share/claude/versions/*`), the default login Keychain (`Claude Code-credentials` item via persistent-reference replace; manager item `AIControl-claude-logins.v1` with approved-binary ACL), `~/.claude.json` owned-key-only replacement (refuses edits to non-owned keys), the manager lock at `~/Library/Application Support/AIControl`, and process checks that treat any installed Claude version as running. Conflicts: `CLAUDE_CONFIG_DIR`, `CLAUDE_SECURESTORAGE_CONFIG_DIR`, custom/local OAuth variables, API key/token/Bedrock/Vertex variables, `~/.claude/.credentials.json`, `~/.claude/.config.json`. Enabled only with `AI_CONTROL_CLAUDE_LIVE=1` for both the CLI and the app; otherwise unavailable as before. A running Claude now yields distinct CLI/app copy (`claudeRunning`).
- Limitations: environment conflicts reflect AI Control's own environment, not the user's shells; only the native installer is supported; the contract checks the storage derivation, not every Claude behavior (refresh/cache semantics remain as researched).

| Evidence | Result |
|---|---|
| RED | Focused manager filter failed to compile against missing live types. |
| GREEN / regression | `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`: exit 0, 162 tests/2 suites, 2 opt-in skips; `swift build` complete (existing SecKeychain deprecation warnings); `git diff --check` exit 0. |
| Real binaries (opt-in) | `AI_CONTROL_CLAUDE_BINARIES=<2.1.274:2.1.280:2.1.282> … --filter installedBuildsSatisfyStorageContract`: pass, under 1 s total. Test fixtures embed the exact derivation bytes of 2.1.274 and 2.1.282 (verified present in those binaries). |
| Mutation proof | Dropping the versions-directory requirement, the secure-storage override conflict, or the versions-directory process check each failed its test; sources restored byte-identical. |
| Live read-only smoke | `AI_CONTROL_CLAUDE_LIVE=1 .build/debug/AIControl claude-login list` → "No saved Claude logins.", exit 0, no files created; without the flag → unavailable, exit 3. |

- Remaining for real one-click use (needs the user at the Mac): save two logins (`AI_CONTROL_CLAUDE_LIVE=1 AIControl claude-login save <alias>` after signing in with each account), approve macOS Keychain prompts (G2), run the live A→B→A switch with Claude closed (G5), then decide to enable by default. Nothing committed yet.

### Open Sessions Allowed — Last-Applied Alias Names the Live Login

- User decision (2026-09-26): switching must not require quitting Claude sessions; in the user's experience running sessions pick up a login changed elsewhere and retry. The live preflight now sets `permitsOpenSessions`; process checks stay available for tests and non-live backends.
- Outgoing checkpoint rule: configuration agrees with the alias applied last → full checkpoint (unchanged); configuration names another saved alias → trust the alias applied last, re-saving only the live Keychain login with that alias's own stored profile (refused if identities disagree); configuration names an unknown or unreadable account → refuse without writes (likely a native login that should be saved first). With no last-applied alias the previous identity-match rule applies.
- Codec: the journal no longer requires the live configuration `oauthAccount` to equal the source snapshot's; the secure before-image binding stays.
- Copy: CLI "Applied alias X."; app "Switched Claude to X." (no restart claim).
- Evidence: full `./scripts/test` exit 0, 171 tests/2 suites, 2 opt-in skips; existing admission refusals (unknown and unreadable identity) still refuse; new tests cover stale configuration, reselecting the last-applied alias, and the preflight flag.
- Not proven: that every open session re-reads the switched login without error; the earlier 13:03/13:26 configuration rewrites were not attributed to a specific process.
