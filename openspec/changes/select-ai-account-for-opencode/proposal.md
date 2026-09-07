# Proposal: Select AI Account for OpenCode

## Intent

Make AI Control a credential-blind bridge between one shared OpenCode workspace and three Claude/two OpenAI contexts. It persists a non-secret selection for later human-invoked `opencode` through a separately installed adapter. Neither reads, copies, mutates, refreshes, exposes, or logs credentials, or launches, closes, restarts, supervises, or proxies OpenCode. Selection affects future processes only.

Shared conversations/sessions, projects, config, plugins, skills, Gentle AI, cache, state, logs, MCP auth, worktrees, snapshots, plans, tool output, working directory, and normal child-tool environment remain unchanged.

## Scope

### In Scope
- Schema-versioned stable account ID, provider, monotonic revision, and separate non-secret context map.
- Gate-first spikes, conditional direct-`exec` adapter, and identity-verified usage.

### Out of Scope
- Production `HOME`/`XDG_DATA_HOME` switching, `OPENCODE_AUTH_CONTENT`, or live shared-auth symlink replacement.

## Capabilities

### New Capabilities
- `credential-blind-opencode-selection`: Gated validated selector for future supported bare `opencode` invocations.
- `provider-usage-identity`: Supported metadata matched by a non-secret stable provider ID.

### Modified Capabilities
None — `openspec/specs/` is empty.

## Approach

Production is blocked until all gates pass; unknown versions or any failure fail closed.

- **Kill — auth boundary:** A pinned auth-only override changes only provider auth; concurrent identities share one session database; all non-auth paths and environment stay unchanged.
- **Kill — Anthropic stability:** The selected Claude identity remains bound through refresh and 401/429/529 handling. Stock `opencode-anthropic-login-via-cli@1.6.1` unchanged is rejected.
- **Required — startup adapter:** Verify zsh bare resolution, arguments, TTY, signals, exit status, absolute-real-binary recursion prevention, stale hashes, diagnostics, and rollback.
- **Required — selector durability:** Verify restrictive permissions, validation, fsync, same-filesystem atomic rename, parent sync, concurrent readers, interruption recovery, and monotonic revisions.
- **Required — usage identity:** Accept provider metadata only with a matched non-secret stable provider ID; otherwise show unavailable/stale/aggregate-only/unverified.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Sources/AIControlCore/AIControlCore.swift` | Modified | Selector/usage boundary. |
| `Sources/AIControl/AIControlMain.swift` | Modified | Selection-state UI. |
| startup adapter installation | New | Direct-`exec` integration. |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| No auth-only override | High | Kill gate. |
| Adapter bypass/recursion | Med | Adapter gate. |
| Selector loss/mismatch | Med | Durability/identity gates. |

## Rollback Plan

Disable adapter/selector integration, clear shell hashes, restore direct OpenCode, and leave provider credentials untouched.

## Dependencies

- Pinned OpenCode/plugin versions passing every gate.

## Success Criteria

- [ ] All gates pass; otherwise production stays disabled.
- [ ] Only future supported bare invocations observe selection without credential, shared-state, or environment drift.
- [ ] Usage is verified or explicitly degraded.
