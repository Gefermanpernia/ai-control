# Apply Progress: Manage Claude Logins

## Cumulative State

- Unit 1 (`unit-1-pure-foundation`): tasks 1.1–1.4 complete.
- Unit 2 (`unit-2-terminal-enrollment`): tasks 2.1–2.3 complete; review explicitly declined after the provider issue.
- Unit 3A and Unit 3B1: tasks 3.1–3.6 complete; Unit 3B2: tasks 3.7–3.9 complete, including the concrete native enumerator; Units 3B3–5 remain pending.
- Mode: Strict TDD. Delivery: auto-chain, stacked-to-main; production credential persistence remains unavailable until U3B protections and integration are complete.
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
