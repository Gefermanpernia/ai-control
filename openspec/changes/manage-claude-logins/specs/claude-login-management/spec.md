# Claude Login Management Specification

## Purpose

Provide terminal enrollment and in-app saved-alias selection for exactly two user-established Claude Code logins while retaining one shared Claude context and protecting credential state.

## Requirements

### Requirement: Terminal Login Enrollment and Status

The system MUST support enrollment of a first alias and then a second alias from the terminal, with a hard maximum of two aliases; the completed managed configuration consists of exactly two user-established logins. It MUST snapshot only the latest observed outgoing login/account subset, preserve absent, null, and present optional values distinctly, and emit only non-secret status. It MUST retain a re-login-needed state rather than revive known-dead credentials. Invoking the executable with no arguments MUST retain GUI startup, with the saved-alias bridge specified below.

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

Manager snapshots and recovery journals containing secrets MUST be Keychain-only. Before credential writes, the system MUST persist/read back a protected journal of owned-field before-images and desired values, verify each mutation, and commit the alias last. Pending-transaction recovery MUST restore only owned fields from latest roots, never historical whole roots; verified-commit cleanup follows the distinct scenario below, not automatic rollback.

#### Scenario: Recover a partial switch

- GIVEN a failure or interruption occurs after verified journal preparation but before verified commit
- WHEN the manager starts recovery
- THEN it MUST verify an owned-field rollback from the journal
- AND retain recovery-required state if rollback is uncertain or fails

#### Scenario: Concurrent external update

- GIVEN a managed-field race or unexpected writer is detected during switching
- WHEN verification or recovery runs
- THEN the system MUST abort without overwriting unrelated latest changes

#### Scenario: Verified-commit cleanup becomes uncertain

- GIVEN the marker and committed phase were atomically persisted and read back after combined resource verification
- WHEN journal removal, its readback, or a final process check fails
- THEN the system MUST report distinct non-success post-commit cleanup uncertainty, never authenticated/success or automatic rollback
- AND it MUST NOT claim the journal remains: removal may already have occurred; any remaining committed journal MUST block selection
- AND later confirmed journal absence MAY allow ordinary guarded admission, qualifying unresolved-recovery blocking below; never blind retry, scripted reset or an invented persistent block flag

### Requirement: Fail-Closed Preflight and Lifecycle Boundary

The system MUST block enrollment and selection when recovery is unresolved. It MUST make no live writes for any command when processes are active or uncertain, the lock is unavailable, a required resource is unreadable, missing, ambiguous, or corrupt, Keychain access is locked or denied, plaintext fallback is used, or routing/account state is unsupported. A readable, uniquely identified outgoing resource with missing, null, or dead credentials MUST be checkpointed exactly: selection of a distinct stored usable alias MAY continue, while selection of that dead outgoing alias MUST stop as re-login-needed before journal or resource writes. Recovery MAY perform verified journal-scoped writes while recovery is unresolved only when every other safety precondition passes. It MUST NOT terminate processes, independently refresh credentials, or use logout as switching. A completed selection MUST require a fresh Claude session; it MUST NOT promise hot switching or token validity.

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

### Requirement: In-App Saved-Alias Selection

The app MUST load persisted aliases through the manager-only list boundary, not mock identities, active Claude capture, manager creation or write-oriented ACL setup. It MUST expose aliases and safe state only; credentials, identity fields and raw backend errors MUST NOT reach UI/logs. A persisted marker is a last-selected hint, not authentication or account-attribution proof.

#### Scenario: Choose an already enrolled account

- GIVEN accounts were enrolled previously and the user knows which has available usage
- WHEN the user opens our app and selects a saved alias
- THEN the app MUST invoke the same guarded transactional use backend as the CLI, not a parallel credential-writing path
- AND latest outgoing checkpoint, protected scoped writes/journal/readback, alias-last commit and recovery-before-further-use MUST remain mandatory
- AND subsequent selection MUST NOT require repeated Claude CLI login/logout, own OAuth/token refresh, or revive known-dead credentials

#### Scenario: Safe presentation and failure states

- GIVEN saved-alias loading or selection is pending, unavailable, refused or interrupted
- WHEN the app presents the outcome
- THEN it MUST distinguish loading, empty, disabled, in-progress, safe error, recovery-required, re-login-needed, backend-unavailable and verified-application success states
- AND pre-write refusal MUST preserve prior app selection; partial/uncertain writes MUST show recovery-required without claiming the prior credentials remain applied
- AND duplicate actions MUST be disabled during an operation; stale completions MUST NOT overwrite newer state
- AND only verified application MAY update the displayed applied alias; no label may claim authenticated status or reliable usage availability
- AND empty/re-login states MUST direct the user to existing manual enrollment/re-login; safe reload is distinct from transaction recovery and MUST NOT bypass its guards

No real usage fetching, limit detection or automatic selection is included. Hardcoded percentages, reset timers, freshness and readiness labels MUST NOT represent saved aliases as available. Offline/local evidence cannot establish token validity or remaining usage. Keyboard-operable selection, visible focus and text-based status MUST be retained; credential switching MUST NOT use the existing in-memory Undo as rollback.

### Product Amendment: Open Safety Validation Gate

The desired acceptance is an OpenCode window remaining open while the user cancels/resubmits their own work after app selection. The tool MUST NOT close OpenCode, cancel/retry requests, manage sessions, detect request quiescence without evidence, or promise in-flight migration/hot reload.

This narrows the product intent of the earlier fresh-session/restart-required and stopped-host wording, NOT its current safety enforcement. Active/uncertain writer refusal, locking, journal and mutation guards MUST remain until separately authorized controlled evidence reconciles an open idle client with actual credential writers and the human approves the resulting lifecycle contract. No flag, user attestation or OpenCode API is presumed to solve that gate. If safe distinction cannot be established, desired open-client acceptance remains blocked; do not silently require a restart and call it satisfied.

#### Scenario: Observation is not concurrency proof

- GIVEN the user reported OpenCode waiting after a five-hour limit, official Claude CLI logout/login, two Esc presses and successful resubmission without restarting
- WHEN assessing the desired open-client flow
- THEN this MUST remain user-reported observation, not independently verified account attribution, mechanism, writer exclusion or permission to relax guards
- AND open-client acceptance MUST stay pending until controlled safety validation and explicit authorization; fresh-session G5 alone does not prove it

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
