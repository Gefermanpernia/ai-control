## Exploration: Manage Claude Logins

### Current State
AI Control is a macOS 13+ Swift package whose executable entry point always launches the SwiftUI menu-bar application through `runAIControl()`. `AIControlCore` contains an `@MainActor` `ControlStore` with deterministic mock accounts and in-memory account selection; it has no terminal command dispatch, credential persistence, Keychain adapter, Claude process guard, interprocess serialization, or recovery mechanism. Current tests cover only mock store transitions and refresh behavior.

This change is a local, first-party CLI credential-management boundary for one human using two of their own Claude Code accounts. Claude Code remains responsible for authentication and token issuance; AI Control would store opaque login bundles, select the active bundle, and preserve one shared primary Claude configuration, settings, history, skills, plugins, and context. Separate `CLAUDE_CONFIG_DIR` roots, dashboard work, usage metrics, provider bridges, and live switching of running Claude processes are outside scope. Public third-party source suggests Claude credentials may span a macOS Keychain item and account metadata in `~/.claude.json`, but that does not verify the exact storage contract of installed Claude Code 2.1.252.

### Affected Areas
- `Sources/AIControl/AIControlMain.swift` — dispatch terminal arguments to testable core logic while retaining GUI launch as the no-command behavior.
- `Sources/AIControlCore/ClaudeLoginManager.swift` — new, focused orchestration for enrollment snapshots, active-account selection, outgoing refresh checkpointing, process preflight, serialization, and bounded recovery.
- `Package.swift` — expose any required native macOS Security framework linkage without adding a third-party dependency.
- `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` — add deterministic unit and fixture-based contract tests using injected credential, metadata, process, lock, and failure-point doubles.

### Approaches
1. **Native Keychain snapshots with field-level active-state updates** — store each manager-owned opaque login bundle in macOS Keychain, retain only non-secret alias/state metadata outside it, checkpoint the current outgoing bundle before switching, and merge only verified Claude account metadata fields into the shared primary state.
   - Pros: Satisfies two saved logins and terminal selection while retaining one shared context; uses native security primitives; preserves refresh-token rotation; keeps the implementation isolated from the mock GUI; permits fail-closed tests and bounded rollback.
   - Cons: Depends on an undocumented installed-version storage contract; Keychain and JSON updates are not one transaction; requires interprocess locking, active-process detection, atomic file replacement, and recovery bookkeeping.
   - Effort: Medium

2. **Whole-profile snapshot and restore** — archive and replace Claude's complete primary configuration for each account.
   - Pros: Conceptually simple and less selective about undocumented fields.
   - Cons: Conflicts with the confirmed shared-context requirement; can roll back or fork settings, history, skills, plugins, and unrelated state; greatly increases secret exposure, corruption, and recovery risk.
   - Effort: Medium

### Recommendation
Use the native Keychain and field-level update approach. Keep GUI `ControlStore` behavior untouched in this change and add a narrow command dispatcher over a testable `ClaudeLoginManager`. Enrollment should snapshot only the login that the user has already established with Claude Code; AI Control should not implement Claude login, logout, or authentication-status flows.

Every mutation should acquire a cross-process manager lock, fail closed when a Claude process may be active, validate the selected enrolled alias, save the latest outgoing credential bundle to its Keychain slot, stage rollback data in protected storage, update the active Claude credential without delete-before-write behavior, and atomically merge only verified account metadata fields while preserving unknown and unrelated JSON fields and existing file protections. Success should update manager-owned active-alias metadata; failure should restore only the credential and managed metadata fields, never an old whole-configuration copy. Output and diagnostics must never contain credential payloads or sensitive identity attributes.

Before design or implementation claims compatibility, run a narrow external research lane against Claude Code 2.1.252 static source/package evidence or a disposable synthetic account environment—not the user's live secrets—to verify the credential location, payload shape, matching account-metadata fields, write semantics, and restart requirement. Encode the verified shapes as redacted fixtures and contract tests. Unit tests should prove outgoing refresh checkpointing, unrelated-field preservation, no-write behavior with active processes, serialized concurrent attempts, fail-closed enrollment errors, atomic replacement, and bounded recovery at each injected failure point.

### Risks
- Refresh tokens can rotate while an account is active; failing to checkpoint the outgoing bundle immediately before a switch can make a saved login unusable.
- Credential and identity metadata can diverge; a switch must treat the verified bundle and its matching account metadata as one recoverable logical operation.
- Unknown Claude fields, file permissions, ownership, or concurrent edits can be lost by whole-file reconstruction; fixture tests must prove preservation and atomic replacement.
- Keychain and filesystem writes cannot be committed atomically; injected failure tests must verify bounded rollback without restoring unrelated configuration.
- A Claude process can refresh or rewrite state during selection; process detection plus a cross-process lock must fail closed, with restart documented as an operational constraint rather than guaranteed hot switching.
- Enrollment can capture the wrong active login or overwrite an existing alias; the terminal flow must require an explicit alias, detect duplicates, and report non-secret confirmation before replacement.
- Undocumented storage details may change across Claude Code releases; installed-version compatibility remains unproven until the narrow research lane supplies evidence and redacted contract fixtures.

### Ready for Proposal
Yes. The product choices are already settled: manage exactly two user-owned Claude Code logins from the terminal while retaining one primary shared Claude context, with no GUI expansion or native authentication flow. The proposal can define the bounded enrollment/select lifecycle and security controls now, while making installed-version storage verification a pre-implementation evidence gate rather than treating undocumented storage as an impossibility.
