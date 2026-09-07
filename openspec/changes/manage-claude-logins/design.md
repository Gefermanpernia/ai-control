# Design: Manage Claude Logins

## Technical Approach

Native, single-user credential custody; Claude owns authentication. Reuse `AIControl`/`AIControlCore`; no-argument GUI and `ControlStore` remain unchanged. Synchronous, dependency-free; no network/logout/context changes. Authority: proposal/specification, research rev3, state rev5.

## Architecture Decisions

| Option | Tradeoff | Decision/rationale |
|---|---|---|
| Existing core / new target | Smaller boundary | Core coordinator; injected OS adapters. |
| One Keychain envelope / files | Atomic manager state, not cross-resource atomicity | Local nonsynchronizing envelope: two snapshots, marker, journal. |
| Raw JSON spans / numeric decoding | Parser complexity prevents rounding | Strict recursive validation, duplicate-key rejection; preserve untouched bytes. |

## Interfaces / Contracts

Expose `runClaudeLogins(arguments: [String]) -> Int32`; empty argv bypasses adapter construction and runs the GUI.

`AIControl claude-login save <alias>`, `list`, `use <alias>`, `recover`; aliases `[a-z][a-z0-9_-]{0,31}`. Exit 0=success, 2=usage, 3=blocked+safe-reason, 4=recovery-required, 5=re-login-needed. List reads manager state only, outputs aliases/states/last-selected hint, never identities. Selection reports restart-required, not authenticated. Absent manager state lists empty; only save creates it.

Envelope v1 stores presence-tagged bundles (missing/null/value), identity, usability, marker, and optional journal `{operationID,source,target,before,after,phase}`. Identity matches nonempty `accountUuid`/`organizationUuid`; optional secure organization must agree when non-null. Email/marker never establish identity; offline matching cannot authenticate tokens.

Exact ownership (research B5/B7):

| Resource | Keys | Selection |
|---|---|---|
| Secure root | `claudeAiOauth` | Whole opaque subtree |
| Secure root | `organizationUuid`, `trustedDeviceToken` | Target presence/value |
| `~/.claude.json` | `oauthAccount` | Whole opaque subtree |
| `~/.claude.json` | `additionalModelOptionsCache`, `additionalModelCostsCache`, `modelAccessCache`, `orgModelDefaultCache`, `lastSeenOrgDefaultUpdatedAt`, `clientDataCache`, `clientDataCacheSlots`, `autoCompactWindowsCache`, `cachedUsageUtilization` | Remove; journal preimages |

Everything else, including MCP/plugin secrets and shared context, remains untouched.

## Data Flow

1. Lock; enforce safety guards. Unresolved journal blocks save/use, never otherwise-safe recover.
2. Save: first enrollment allowed. Unused alias captures actual B despite marker A, without overwriting A. Existing aliases update only matching identities; duplicates/third aliases refuse.
3. Use: uniquely match outgoing identity; checkpoint/readback latest complete subset, including empty-token/zero-expiry invalidation markers. Never refill old tokens. Dead targets require Claude re-login then same-identity save.
4. Persist/readback journal → recompare roots → secure update → config/cache update → verify both → atomically commit marker+journal phase → clear/readback journal.
5. Recovery: pending transactions restore owned preimages into latest roots only when each owned-field vector matches before/after; third values refuse. Progress never proves writes occurred. Committed journals require after-image verification before cleanup. Preserve outgoing checkpoint. Failures attempt rollback only under safe guards; any uncertainty retains journal, never false success.

## IO Boundaries

Security adapter selects exactly one generic-password persistent reference: service `Claude Code-credentials`, account derived exactly per research V1. `SecItemUpdate` changes data only, retaining attributes/ACL; never delete/re-add. Manager service `AIControl-claude-logins.v1`, account UID, ACL restricted to approved binary. No plaintext archives, token argv/logs, or shell.

Require research W5 ARM 2.1.252 hash/default resolver. Reject overrides, legacy/fallback/alternate-auth involvement, `enterpriseGateway`/`designOauth` presence, unclassified account-bound state, and denied/cancelled/locked/ambiguous/corrupt storage or missing active resources.

Document adapter patches latest raw JSON via protected same-directory temporary file, fsync/rename/fsync; preserves numbers, owner/mode/ACL. Reject symlinks, changed content/identity/protections; verify preservation. Bound size/depth; validate OAuth structure without token decoding. Keychain roots also retain raw unrelated values.

Descriptor-held per-user `flock` at `~/Library/Application Support/AIControl/claude-login.lock` (0700 directory/0600 file; no symlinks) serializes managers. Native UID/executable/ancestry scans before every write/after verification block active or uncertain terminal/editor/SDK/daemon/Remote Control hosts. Operators must prevent launches throughout. Detection mid-switch stops writes, retains journal. Non-cooperating startup and check/write races remain possible; exclusion is not guaranteed.

## File Changes

| Path | Action |
|---|---|
| `Sources/AIControl/AIControlMain.swift` | Modify: dispatch before GUI |
| `Sources/AIControlCore/ClaudeLoginManager.swift` | Planned new: CLI/coordinator/contracts |
| `Sources/AIControlCore/ClaudeLoginIO.swift` | Planned new: native adapters |
| `Sources/AIControlCore/ScopedJSON.swift` | Planned new: lossless editor |
| `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Planned new: manager behavior |

`Package.swift` and `scripts/test` stay unchanged; native imports suffice. Existing `ControlStoreTests` owns mock GUI, not credentials.

## Testing Strategy

Swift Testing RED→GREEN: `./scripts/test --filter ClaudeLoginManagerTests`, then `./scripts/test`. Synthetic scenario mappings:

- [Enrollment](specs/claude-login-management/spec.md#scenario-enroll-two-distinct-logins)/[manual-B](specs/claude-login-management/spec.md#scenario-enroll-a-distinct-second-login-after-manual-sign-in)/[collision](specs/claude-login-management/spec.md#scenario-detect-ambiguous-identity-or-collision): identity/dispatcher/dead-markers.
- [A2](specs/claude-login-management/spec.md#scenario-switch-using-latest-outgoing-checkpoint)/[presence](specs/claude-login-management/spec.md#scenario-preserve-presence-and-unrelated-state): caches, large numbers, unrelated sentinels.
- [Partial](specs/claude-login-management/spec.md#scenario-recover-a-partial-switch)/[race](specs/claude-login-management/spec.md#scenario-concurrent-external-update)/[unresolved](specs/claude-login-management/spec.md#scenario-recover-an-unresolved-journal): every write/readback/crash/rollback/cleanup boundary.
- [Unsafe](specs/claude-login-management/spec.md#scenario-unsafe-preflight)/[restart](specs/claude-login-management/spec.md#scenario-fresh-session-boundary): guards, ACLs, safe output.
- [No-live](specs/claude-login-management/spec.md#scenario-no-live-authorization)/[completion](specs/claude-login-management/spec.md#scenario-live-completion-evidence): authorization/gates.

G2 native synthetic integration requires separate authorization; no existing E2E runner.

## Threat Matrix

| Boundary | Applicability/reason |
|---|---|
| Documentation-like paths | N/A: no executable classification |
| Git repository selection | N/A: no repository routing |
| Commit state | N/A: no commits |
| Push state | N/A: no pushes |
| PR commands | N/A: no PR automation |
| CLI/process integration | Applicable: malformed commands perform zero storage IO; process/lock uncertainty performs zero credential writes. RED at dispatcher/coordinator boundaries. |

## Migration / Rollout

No migration. G1–G4 precede separately authorized G5 live A→B→A fresh-session acceptance; G5 includes refresh/checkpoint, re-login-needed, identity agreement, rollback. No live completion before G5; no credential access or runtime tests now.

## Open Questions

None blocking design; native ACL/signing and live validity remain acceptance evidence, not established guarantees.
