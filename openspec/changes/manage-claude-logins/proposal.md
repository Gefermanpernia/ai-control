# Proposal: Manage Claude Logins

## Intent

Provide a local switcher for exactly two user-established Claude Code logins with terminal enrollment and an in-app saved-alias selection bridge, retaining one shared Claude context. The manager must protect credentials and prevent account-state corruption rather than promise hot switching or token validity.

## Scope

### In Scope
- Retain the terminal dispatcher and no-command GUI entry, reusing the executable and testable `AIControlCore` package.
- Enroll and select two aliases using native Keychain-backed opaque snapshots, outgoing-state checkpointing, and non-secret status output.
- Switch only after process/lock preflight, protected recovery journaling, field-scoped Keychain and `~/.claude.json` updates, verification, and bounded rollback.
- Load saved aliases in our app and let the user select one through that same guarded selection backend, without repeated Claude CLI login/logout. Availability is known by the user, not inferred by the tool.

### Out of Scope
- Separate `CLAUDE_CONFIG_DIR` roots, GUI changes beyond this saved-Claude-alias bridge, real usage/metrics fetching, provider expansion, OAuth client flows/token refresh, dependencies, or automatic process termination.
- Live credential access/writes in this phase, explicit logout as a switch operation, stale-token revival, or hot-switch guarantees for running Claude sessions.

## Capabilities

### New Capabilities
- `claude-login-management`: Safely enroll, select, recover, and report two local Claude Code login aliases; add app-based saved-alias selection while retaining terminal entry points.

### Modified Capabilities
The new capability narrowly replaces mock Claude identities/selection with saved aliases and verified application states; unrelated provider UI is not redesigned.

### Product amendment: integrated app selection (planning only)

The user enrolls accounts first, notices exhaustion independently, opens our app and chooses another saved alias. The tool applies stored credentials; known-dead credentials require manual Claude re-login and enrollment update, never revival. No automatic limit detection, account choice or OpenCode orchestration is included, and hardcoded usage must not appear as real availability.

The desired flow leaves OpenCode open while the user owns cancellation/resubmission. It neither promises in-flight migration nor credential hot reload. This supersedes CLI-only GUI exclusion, but the specification's open safety validation gate must reconcile idle clients with actual credential writers before changing the existing stopped-process requirements. Observation is not proof or permission; this amendment authorizes documentation only.

## Approach

Use a narrow coordinator with native Security-framework storage, injected adapters, and a manager lock. Capture the outgoing login after Claude is stopped; maintain its complete opaque login/account subset with presence-aware optional fields. Update only allowlisted active account fields and account-derived caches, preserving unrelated Keychain-root data (including MCP/plugin secrets), shared configuration/history/settings/skills/plugins, unknown JSON, and protections. Journal before-images and desired values, read back each resource, commit the alias last, and retain recovery-required state on ambiguity or failed rollback. Reject unsupported routing/account-bound state and never use plaintext fallback or delete/re-add Keychain writes.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Sources/AIControl/AIControlMain.swift` | Modified | Route terminal commands without changing GUI startup. |
| `Sources/AIControlCore/ClaudeLoginManager.swift` | New | Coordinator, recovery, process/lock preflight, and adapters. |
| `Package.swift` | Modified | Link native Security framework only if required. |
| `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | New | Strict-TDD synthetic failure and preservation contracts. |
| `Sources/AIControlCore/AIControlCore.swift`, `Tests/AIControlCoreTests/ControlStoreTests.swift` | Planned modification | Narrow saved-alias UI/store bridge and owning state-transition evidence. |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Credential/config divergence or concurrent refresh | Medium | Stop-process gate, lock, latest checkpoint, journal, verified rollback. |
| Undocumented runtime storage differs | Medium | Pass G1–G4 before the separately authorized live test; require G5 before live usability/completion. |
| Secret exposure or unrelated-state loss | Low | Keychain-only manager secrets; field-scoped updates; redacted tests/logs. |

## Rollback Plan

Before credential mutation, persist/read back a protected journal of owned-field preimages. Pre-commit failures stop writes; U5 owns guarded pending-transaction rollback. After verified commit, cleanup uncertainty is a distinct non-success, not automatic rollback or guaranteed journal retention: cleanup may already have removed it. The specification's cleanup scenario governs subsequent admission; remove the manager only after recovery is resolved.

## Dependencies

- G1–G4 acceptance evidence, including exact installed-contract and native Keychain validation, before a separately authorized live test; G5 is required before live usability/completion.
- Complete G-M/G-C and U4/U5 before UI integration can establish safe selection/recovery. The distinct UI forecast and unresolved open-client safety gate in tasks/design block implementation; native artifact readiness does not grant consent.

## Success Criteria

- [ ] Synthetic A → B → A tests preserve latest outgoing state, unrelated data, and presence semantics without secret output.
- [ ] Every preflight, write, crash, rollback and cleanup failure reports a safe non-success: checkpoint/prepare persistence may be uncertain, and verified-commit cleanup may leave no journal; neither permits fictional durability or restored-state claims.
- [ ] After G1–G4 and separate authorization, the live G5 A → B → A test proves fresh-session usability; completion remains pending until it passes.
- [ ] Saved-alias selection exposes safe loading/refusal/recovery/success states and verified application only; no mock availability, secret output or automatic OpenCode interaction. Open-client acceptance remains conditional on the safety gate.
