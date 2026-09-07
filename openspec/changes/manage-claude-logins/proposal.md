# Proposal: Manage Claude Logins

## Intent

Provide a terminal-managed, local switcher for exactly two user-established Claude Code logins while retaining one shared Claude context. The manager must protect credentials and prevent account-state corruption rather than promise hot switching or token validity.

## Scope

### In Scope
- Add a terminal dispatcher that reuses the executable and testable `AIControlCore` package; no-command GUI behavior remains unchanged.
- Enroll and select two aliases using native Keychain-backed opaque snapshots, outgoing-state checkpointing, and non-secret status output.
- Switch only after process/lock preflight, protected recovery journaling, field-scoped Keychain and `~/.claude.json` updates, verification, and bounded rollback.

### Out of Scope
- Separate `CLAUDE_CONFIG_DIR` roots, GUI changes, metrics, provider bridges, OAuth client flows, dependencies, or automatic process termination.
- Live credential access/writes in this phase, explicit logout as a switch operation, stale-token revival, or hot-switch guarantees for running Claude sessions.

## Capabilities

### New Capabilities
- `claude-login-management`: Safely enroll, select, recover, and report two local Claude Code login aliases from the terminal.

### Modified Capabilities
None. No current specs exist and mock GUI behavior is unchanged.

## Approach

Use a narrow coordinator with native Security-framework storage, injected adapters, and a manager lock. Capture the outgoing login after Claude is stopped; maintain its complete opaque login/account subset with presence-aware optional fields. Update only allowlisted active account fields and account-derived caches, preserving unrelated Keychain-root data (including MCP/plugin secrets), shared configuration/history/settings/skills/plugins, unknown JSON, and protections. Journal before-images and desired values, read back each resource, commit the alias last, and retain recovery-required state on ambiguity or failed rollback. Reject unsupported routing/account-bound state and never use plaintext fallback or delete/re-add Keychain writes.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Sources/AIControl/AIControlMain.swift` | Modified | Route terminal commands without changing GUI startup. |
| `Sources/AIControlCore/ClaudeLoginManager.swift` | New | Coordinator, recovery, process/lock preflight, and adapters. |
| `Package.swift` | Modified | Link native Security framework only if required. |
| `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | New | Strict-TDD synthetic failure and preservation contracts. |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Credential/config divergence or concurrent refresh | Medium | Stop-process gate, lock, latest checkpoint, journal, verified rollback. |
| Undocumented runtime storage differs | Medium | Pass G1–G4 before the separately authorized live test; require G5 before live usability/completion. |
| Secret exposure or unrelated-state loss | Low | Keychain-only manager secrets; field-scoped updates; redacted tests/logs. |

## Rollback Plan

Before mutation, persist a protected journal of owned-field preimages. On any failure, restore only owned fields from latest roots and verify. If recovery is uncertain, retain the journal and block further switches; remove the manager without touching Claude state only after recovery succeeds.

## Dependencies

- G1–G4 acceptance evidence, including exact installed-contract and native Keychain validation, before a separately authorized live test; G5 is required before live usability/completion.

## Success Criteria

- [ ] Synthetic A → B → A tests preserve latest outgoing state, unrelated data, and presence semantics without secret output.
- [ ] Every preflight, write, crash, and rollback failure path fails closed or leaves a durable recovery-required record.
- [ ] After G1–G4 and separate authorization, the live G5 A → B → A test proves fresh-session usability; completion remains pending until it passes.
