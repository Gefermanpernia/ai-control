# Claude Login Management Specification

## Purpose

Provide a terminal-managed local selector for exactly two user-established Claude Code logins while retaining one shared Claude context and protecting credential state.

## Requirements

### Requirement: Terminal Login Enrollment and Status

The system MUST support enrollment of a first alias and then a second alias from the terminal, with a hard maximum of two aliases; the completed managed configuration consists of exactly two user-established logins. It MUST snapshot only the latest observed outgoing login/account subset, preserve absent, null, and present optional values distinctly, and emit only non-secret status. It MUST retain a re-login-needed state rather than revive known-dead credentials. Invoking the executable with no arguments MUST preserve existing GUI behavior.

#### Scenario: Enroll two distinct logins

- GIVEN Claude is quiescent and an unambiguous eligible login is active
- WHEN the user enrolls it under an available alias and later enrolls a distinct login under the other alias
- THEN each alias has its own current scoped snapshot
- AND status exposes aliases and safe state only, never credentials or identity values

#### Scenario: Enroll a distinct second login after manual sign-in

- GIVEN alias A is enrolled, its marker remains A, and the user signs Claude into distinct current account B
- WHEN the user explicitly enrolls B into the unused second alias
- THEN the system MUST save B to that alias without checkpointing B over A
- AND the marker MUST NOT be treated as account identity authority

#### Scenario: Detect ambiguous identity or collision

- GIVEN current scoped identity is ambiguous, an alias collides, or enrollment would overwrite A with distinct B
- WHEN enrollment or selection is requested
- THEN the system MUST refuse mutation and report a non-secret diagnostic

### Requirement: Shared Context and Scoped Account Selection

The system MUST activate a selected enrolled alias within the same primary Claude context. It MUST replace only the scoped `claudeAiOauth`, `oauthAccount`, and supported optional own identity state; invalidate account-derived caches; and preserve MCP/plugin secrets, unknown secure-root data, shared settings, history, skills, plugins, project trust, and unknown configuration fields. It MUST reject unsupported account-bound/provider state rather than broaden scope.

#### Scenario: Switch using latest outgoing checkpoint

- GIVEN alias A was enrolled, its active state later changed to A2, and alias B is enrolled
- WHEN the user selects B and subsequently selects A
- THEN A is checkpointed as A2 before B is activated
- AND returning to A restores A2 without copying B fields or stale A data

#### Scenario: Preserve presence and unrelated state

- GIVEN the target lacks an optional identity field and current roots contain unrelated sentinel values
- WHEN the target is selected
- THEN the missing target field MUST remain missing and unrelated values MUST remain unchanged

### Requirement: Protected Recovery and Failure Handling

Manager snapshots and recovery journals containing secrets MUST be Keychain-only. Before any switch, the system MUST create a protected journal of owned-field before-images and desired values, verify each mutation, and mark the alias active only after consistent verification. Recovery MUST restore only owned fields from the latest roots; it MUST NOT restore historical whole roots.

#### Scenario: Recover a partial switch

- GIVEN a failure or interruption occurs after a managed write
- WHEN the manager starts recovery
- THEN it MUST verify an owned-field rollback from the journal
- AND retain recovery-required state if rollback is uncertain or fails

#### Scenario: Concurrent external update

- GIVEN a managed-field race or unexpected writer is detected during switching
- WHEN verification or recovery runs
- THEN the system MUST abort without overwriting unrelated latest changes

### Requirement: Fail-Closed Preflight and Lifecycle Boundary

The system MUST block enrollment and selection when recovery is unresolved. It MUST make no live writes for any command when processes are active or uncertain, the lock is unavailable, Keychain access is locked, denied, missing, ambiguous, corrupt, or uses plaintext fallback, or routing/account state is unsupported. Recovery MAY perform verified journal-scoped writes while recovery is unresolved only when every other safety precondition passes. It MUST NOT terminate processes, independently refresh credentials, or use logout as switching. A completed selection MUST require a fresh Claude session; it MUST NOT promise hot switching or token validity.

#### Scenario: Unsafe preflight

- GIVEN a non-recovery safety precondition is blocked
- WHEN enrollment, selection, or recovery is requested
- THEN the system MUST fail closed with no writes and no secret output

#### Scenario: Recover an unresolved journal

- GIVEN recovery is unresolved and every other safety precondition passes
- WHEN the user requests recovery
- THEN the system MAY perform only verified journal-scoped recovery writes
- AND a rollback failure MUST retain recovery-required state and block enrollment and selection

#### Scenario: Fresh-session boundary

- GIVEN a selection completed successfully
- WHEN the user starts Claude after all prior Claude processes remain stopped
- THEN status MUST report restart required, not authentication verified

### Requirement: Evidence Gates for Live Use

The system MUST satisfy G1–G4 static/native synthetic/preflight controls before any separately authorized live testing. G5 MUST perform an authorized live A-to-B-to-A fresh-session acceptance, including checkpoint and re-login-needed paths, before live usability or completion is claimed. G5 MUST NOT be treated as a prerequisite to planning or executing itself.

#### Scenario: No live authorization

- GIVEN live credential access or writes are not authorized
- WHEN planning or synthetic verification is performed
- THEN no live credential operation MUST occur and no live completion claim MUST be made

#### Scenario: Live completion evidence

- GIVEN G1–G4 passed and separate live authorization is granted
- WHEN G5 validates A-to-B-to-A through fresh Claude sessions
- THEN live completion MAY be claimed only if G5 passes
