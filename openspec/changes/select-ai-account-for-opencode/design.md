# Design: Select AI Account for OpenCode

## Technical Approach

Add credential-free selection/usage to `AIControlCore`. `@MainActor ControlStore` coordinates UI; an injected repository owns I/O. Production leaves ordinary OpenCode untouched while any gate is unproven.

    ControlView → ControlStore → non-secret selector
                                      ↓ future human `opencode`
    provider/OpenCode secrets → OpenCode-owned binder ← adapter validation
                                      ↓ direct exec of absolute binary

The adapter receives only IDs, validates resolution/version/revision, and never supervises. Credentials never enter AI Control, selector, adapter, logs, or diagnostics; exposure kills production. Only authentication may differ. Sessions/conversations, projects, config, plugins, skills, Gentle AI, cache, state, logs, MCP auth, worktrees, snapshots, plans, tool output, cwd, and child environment stay shared. Running processes never change.

## Architecture Decisions

| Decision | Choice | Alternatives / rationale |
|---|---|---|
| Failure baseline | Stock resolution until five gates pass; unknown versions fail closed. | Avoids partial support. |
| State | Versioned selection plus allowlisted opaque context map; compare-and-advance revisions. | Reject credentials, labels, HOME/XDG, auth JSON, live symlinks. |
| Process | Manual adapter, absolute binary, direct `exec`; AI Control only writes state. | Launchers/proxies violate ownership/fidelity. |
| Auth | Conditional pinned auth-only binder. | Stock `v1.18.27` and plugin `1.6.1` fail; no patch/fork is ready. |
| Usage | Matched stable ID plus freshness, else degradation. | Inference misattributes. |

## Gate Design

| Gate | Pass evidence / failure |
|---|---|
| Kill—auth boundary | Concurrent identities share one session DB with zero non-auth/cwd/environment drift. Drift, cross-switch, or credential exposure kills production. |
| Kill—Claude stability | Refresh and 401/429/529 remain selected or fail closed. Alternate main/CCS discovery or overwrite kills production. |
| Required—adapter | zsh bare resolution, argv, TTY, PID/group, signals, exit, recursion prevention, hashes, bypass diagnostics, and rollback pass. Silent bypass fails. |
| Required—selector | Ownership/mode, validation, `fsync`, same-filesystem rename, parent sync, concurrency, revisions, and recovery pass on macOS. Partial/widened state fails. |
| Required—usage | Supported ID matches registration with freshness; missing/expired/aggregate/unmatched data degrades. Credential/label inference fails. Gates remain independently reportable. |

## File Changes

| File | Action | Description |
|---|---|---|
| `Sources/AIControlCore/AIControlCore.swift` | Modify | Keep UI/`@MainActor ControlStore`; inject boundaries. |
| `Sources/AIControlCore/SelectionState.swift`, `Sources/AIControlCore/SelectorPersistence.swift`, `Sources/AIControlCore/UsageState.swift` | Create | Contracts, atomic persistence, verified usage. |
| `Tests/AIControlCoreTests/ControlStoreTests.swift` | Modify | Store success/failure transitions. |
| `Tests/AIControlCoreTests/SelectorPersistenceTests.swift`, `Tests/AIControlCoreTests/UsageStateTests.swift` | Create | Persistence and usage contracts. |
| `Package.swift`, `Sources/OpenCodeStartupAdapter/OpenCodeStartupAdapter.swift` | Conditional | Add executable after gates pass. `Sources/AIControl/AIControlMain.swift` stays unchanged. |

Spike binaries, fake contexts, pinned copies, and fixtures are disposable temporary artifacts, never production sources or credentials.

## Interfaces / Contracts

```swift
struct AccountSelection: Codable, Sendable { let schemaVersion: Int; let provider: CLIProvider; let accountID: String; let revision: UInt64 }
struct AuthContextReference: Codable, Sendable { let provider: CLIProvider; let accountID: String; let opaqueID: String }
enum SelectionError: Error { case malformed, unknownAccount, unauthorized, inaccessible, nonMonotonic, unsafePermissions, interrupted }
enum UsageState: Sendable { case available(percent: Int, observedAt: Date, freshUntil: Date); case unavailable, stale(Date), aggregateOnly, unverifiedIdentity }
enum AdapterError: Error { case unsupportedVersion, invalidResolution, invalidSelection, recursion }
enum AdapterDecision { case exec(absoluteBinary: URL, arguments: [String], context: AuthContextReference); case refuse(AdapterError) }
```

Repository methods are validated `load()` and compare-and-advance `update(...)`. The adapter preserves arguments/environment and changes only auth binding.

## Testing Strategy

RED→GREEN→REFACTOR uses `./scripts/test --filter …`, then `./scripts/test`. Swift Testing uses temporary directories and `@MainActor` tests. No integration/E2E runner exists. Disposable harnesses prove PTY/signals, concurrency, fault injection, and path/environment snapshots; they are not configured coverage.

## Threat Matrix

| Boundary | Status | Safe/failure behavior | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A—no file classification | Execute only configured binary. | None |
| Git repository selection | N/A—no Git invocation | Cwd unchanged. | None |
| Commit state | N/A—no commits | No VCS. | None |
| Push state | N/A—no pushes | No VCS. | None |
| PR commands | N/A—no PR commands | No composition. | None |
| PATH/bare resolution | Applicable | Verified adapter or explicit diagnostic refusal. | alias, function, absolute bypass, shadowing, stale hash |
| Absolute exec/process fidelity | Applicable | Allowlisted non-self absolute binary; exec or refuse. | recursion, argv, TTY, PID/group, signal, exit propagation |
| Selector/filesystem input | Applicable | Allowlisted restrictive state; reject before logging. | symlink/path substitution, partial/malformed/secret input, stale revision, interrupted write |

Applicable row names and cases must propagate unchanged to tasks and RED tests.

## Migration / Rollout

No credential migration. Ship disabled gate reporting; enable a pinned allowlist only after all five pass. Rollback removes adapter precedence, clears zsh hashes, verifies direct binary resolution, and leaves credentials untouched.

## Open Questions

- [ ] What upstream-supported or auditable auth-only primitive passes the kill gate? Until answered, production remains disabled.
- [ ] Which provider surfaces supply stable non-secret IDs and freshness?
