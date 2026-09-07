---
schema: gentle-ai.sdd-research/v1
revision: 3
project: ai-control
change: manage-claude-logins
outcome: done
scope: Public-source static research; not implementation or live compatibility certification.
session_date: 2026-09-04
accessed_at: 2026-09-05
accessed_at_timezone: UTC
artifact_store: openspec
artifact_store_selection: openspec_only
openspec: openspec/changes/manage-claude-logins/research.md
engram_topic: sdd/manage-claude-logins/research
engram_role: historical_non_authoritative
engram_historical_revision: 2
store_choice_recorded_at_preproposal_revision: 5
selection_recorded_at_preproposal_revision: 2
---

# Research: Manage Claude Logins

## Result and authority

All four research questions have mapped public evidence, including readable JavaScript embedded in the official Claude Code **2.1.252 darwin-arm64 binary**, fetched without executing it and verified against its published SHA-256. Research is `done`; runtime behavior, installed-binary identity, native Keychain access permissions, and live account switching remain untested. These are explicit implementation/pre-live-write acceptance gates below, not official-support or policy gates.

The explicit `research_now` answer was applied once to the existing `research_timing` group at preproposal revision 2 before external retrieval. The answered question is historical state, not another interview. Product decisions remain confirmed: exactly two user-owned Claude logins, terminal selection, the same main configuration/history/skills/plugins; no separate contexts, dashboard expansion, usage metrics, or OpenCode/OpenAI bridge. Undocumented mechanisms are allowed. Engineering recommendations here are non-authoritative inputs to the parent, not new product selections. No proposal was invoked.

## Admission and boundaries

- Declared schema: `gentle-ai.sdd-research-capability/v1`.
- Requested, admitted, and observed exact grants: `[documentation, open-web]`; no other evidence class admitted.
- Documentation retrieval: Context7 resolve/query and `webfetch`; open-web retrieval: `webfetch` and read-only Playwright browser navigation/evaluation using public GET requests with `credentials: omit`.
- Browser evaluation fetched and inspected public bytes as data; no package, binary, or embedded source was executed. A 210,000,000-byte/45-second retrieval bound was used for the native binary.
- No local Claude credential/configuration reads, Keychain access, auth commands, authenticated API requests, login accounts, credential mutations, builds, or tests occurred. The parent-reported installed version/path was not rechecked.
- Only research/preproposal artifacts are authored. Existing unrelated working-tree changes and exploration/init artifacts are untouched. Tool-managed retrieval output is not a project implementation artifact.

## Questions

1. **Q1:** What does exact-version public evidence establish about default macOS service/account/payload and matching account metadata?
2. **Q2:** What is the smallest preservation-safe snapshot/restore boundary, including fields that must not be overwritten?
3. **Q3:** What supports refresh rotation, cached/multiprocess authentication, login/logout revocation, outgoing capture, and stop/restart requirements?
4. **Q4:** What minimal recoverable local design and synthetic verification oracles follow, and what remains before live writes?

## Sources

Every source below was retrieved on `2026-09-05` UTC. `accessed_at` is a retrieval date, not the publisher's update date. Community commits are pinned but are not assertions of compatibility with 2.1.252. Documentation is current and mutable; the exact binary has immutable content identity.

| ID | Class | Title / publisher | URL | accessed_at | Excerpt / inspected evidence |
|---|---|---|---|---|---|
| D1 | documentation | Authentication / Anthropic | https://code.claude.com/docs/en/authentication | 2026-09-05 | "On macOS, credentials are stored in the encrypted macOS Keychain"; rejected writes can use `.credentials.json`; "Once the stored login expires and can't be refreshed" sign-in is needed. |
| D2 | documentation | Troubleshoot installation and login / Anthropic | https://code.claude.com/docs/en/troubleshoot-install | 2026-09-05 | "Parallel sessions on one machine share a saved login and coordinate its renewal"; logout removes stored credentials, "saved MCP server logins, and plugin sensitive values". |
| D3 | documentation | Explore the .claude directory / Anthropic | https://code.claude.com/docs/en/claude-directory | 2026-09-05 | `.claude.json` holds "theme, OAuth session, per-project trust decisions, your personal MCP servers, and UI toggles"; user settings and skills have separate paths. |
| D4 | documentation | Updating and deleting keychain items / Apple | https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items.md | 2026-09-05 | "update the existing item instead"; `SecItemUpdate` modifies all matching items; check returned status and distinguish `errSecItemNotFound`. |
| D5 | documentation | kSecClassGenericPassword / Apple | https://developer.apple.com/documentation/security/ksecclassgenericpassword.md | 2026-09-05 | Composite identity includes account, service, synchronizable, and applicable access group; `kSecAttrAccessible` on macOS applies only with data-protection Keychain or synchronization. |
| W1 | open-web | claude-code 2.1.252 package metadata / Anthropic via npm | https://registry.npmjs.org/@anthropic-ai/claude-code/2.1.252 | 2026-09-05 | `version: 2.1.252`; per-platform optional native dependencies; seven package files. |
| W2 | open-web | 2.1.252 package file listing / Anthropic via UNPKG | https://unpkg.com/@anthropic-ai/claude-code@2.1.252/?meta | 2026-09-05 | Includes `cli-wrapper.cjs`, `install.cjs`, `sdk-tools.d.ts`; no `cli.js` in this package listing. |
| W3 | open-web | 2.1.252 native ARM package listing / Anthropic via UNPKG | https://unpkg.com/@anthropic-ai/claude-code-darwin-arm64@2.1.252/?meta | 2026-09-05 | `/claude`, 197220928 bytes; SHA-256 integrity `tmHGoJT8wyZWv3wAccW0W/kAs01PChqz14/Vmuuiwsc=`. |
| W4 | open-web | 2.1.252 release manifest / Anthropic | https://downloads.claude.ai/claude-code-releases/2.1.252/manifest.json | 2026-09-05 | Commit `c0778c45886d8f1ed8bd5e7c972b8507d299a548`; build `2026-08-31T16:11:11Z`; ARM size/hash match W5. |
| W5 | open-web | 2.1.252 darwin-arm64 native distribution, embedded static source / Anthropic | https://downloads.claude.ai/claude-code-releases/2.1.252/darwin-arm64/claude | 2026-09-05 | Fetched 197220928 bytes; computed SHA-256 `b661c6a094fcc32656bf7c0071c5b45bf900b34d4f0a1ab3d78fd59aeba2c2c7`, equal to W4. Readable `// Version: 2.1.252` modules contain the functions mapped below. |
| C1 | open-web | paths.ts / malakhov-dmitrii, claude-switch | https://raw.githubusercontent.com/malakhov-dmitrii/claude-switch/9d8859f237f3775f269824a58985ef7b5b387e6e/src/lib/paths.ts | 2026-09-05 | `KEYCHAIN_SERVICE = "Claude Code-credentials"`; account override or `userInfo().username`. |
| C2 | open-web | keychain.ts / malakhov-dmitrii, claude-switch | https://raw.githubusercontent.com/malakhov-dmitrii/claude-switch/9d8859f237f3775f269824a58985ef7b5b387e6e/src/lib/keychain.ts | 2026-09-05 | `find-generic-password`; deletes before adding; nonzero reads become null. These are observed hazards, not adopted controls. |
| C3 | open-web | use.ts / malakhov-dmitrii, claude-switch | https://raw.githubusercontent.com/malakhov-dmitrii/claude-switch/9d8859f237f3775f269824a58985ef7b5b387e6e/src/commands/use.ts | 2026-09-05 | Reads a profile JSON into Keychain and says "restart Claude Code to use the new credentials". |
| C4 | open-web | switch.cjs / Fei2-Labs, oauth-switch | https://raw.githubusercontent.com/Fei2-Labs/oauth-switch/984a64ab98ab76674ead1b4a3cc15f1be00cc9ef/bin/lib/actions/switch.cjs | 2026-09-05 | `nextConfig.oauthAccount = deepCopy(selected.metadata)`; refreshes target snapshots and retries newer stored refresh tokens. Its network refresh is not adopted. |
| C5 | open-web | store/io.cjs / Fei2-Labs, oauth-switch | https://raw.githubusercontent.com/Fei2-Labs/oauth-switch/984a64ab98ab76674ead1b4a3cc15f1be00cc9ef/bin/lib/store/io.cjs | 2026-09-05 | Reads Keychain before file; writes plaintext credentials and backups; suppresses Keychain write errors. |
| C6 | open-web | store/accounts.cjs / Fei2-Labs, oauth-switch | https://raw.githubusercontent.com/Fei2-Labs/oauth-switch/984a64ab98ab76674ead1b4a3cc15f1be00cc9ef/bin/lib/store/accounts.cjs | 2026-09-05 | `syncStoreFromLive` captures `oauthAccount` and credentials, but retains old token fields when live values are empty. |
| C7 | open-web | store-sync-refresh-token.test.cjs / Fei2-Labs, oauth-switch | https://raw.githubusercontent.com/Fei2-Labs/oauth-switch/984a64ab98ab76674ead1b4a3cc15f1be00cc9ef/test/store-sync-refresh-token.test.cjs | 2026-09-05 | Contains synthetic assertions for full outgoing updates and merging missing token fields. Reviewed statically only; no test execution or copying of sample identities. |

### Reproducible exact-version source anchors

W5 was decoded one byte per character for locating ASCII JavaScript; offsets are zero-based **binary byte offsets**, not source line numbers. These ranges contain readable source rather than merely string-table occurrences. Minified function names are version-local. Fetch W5, verify W4's hash, inspect these ranges as data; do not run the binary to reproduce static findings.

| Anchor | W5 byte range | Function / excerpt and relevance |
|---|---|---|
| B1 | 154211897–154215320 | Build constants: the production OAuth suffix is empty. |
| B2 | 155301800–155304400 | Credential service name derivation: `Claude Code` plus the OAuth suffix, the `-credentials` suffix and, for non-default configuration directories, a short hash; the account is the sanitized `USER` or OS user name; reads are cached for 30 seconds. |
| B3 | 155304950–155315200 | Secure storage selection: Keychain with a plaintext fallback, a `.storage-write` read-modify-write lock, a JSON payload, updates of the existing generic password with `-U`, and hex-encoded UTF-8 data. |
| B4 | 156173000–156182200 | Token refresh: response mapping, refresh-token revocation request, and OAuth account metadata and roles. |
| B5 | 156219250–156226800 | Login persistence: only `claudeAiOauth` is merged into the secure root; refresh uses compare-and-swap; dead tokens are cleared and auth caches reset. |
| B6 | 156231900–156238650 | Refresh locking: `.oauth_refresh.lock` and a legacy lock; the store is invalidated and read again after locking; a sibling's newer access token is detected. |
| B7 | 169623350–169626950 | Logout versus re-login: account-related secure fields and account-derived configuration caches are cleared. |
| B8 | 174808450–174811000 | Normal login cleanup runs with in-process tokens and non-Anthropic auth preserved, so it does not request revocation of the outgoing `claudeAiOauth` login. |
| B9 | 159317000–159319000; 182299500–182307200 | MCP and plugin secrets (`mcpOAuth`, `pluginSecrets`) share the same secure store as the Claude login. |
| B10 | 158634200–158638600 | `trustedDeviceToken` is read from the same secure store and can be enrolled with Claude's OAuth token under policy. |
| B11 | 154297900–154298250 | Configuration path: a legacy `.claude/.config.json` candidate, otherwise the global configuration file beneath the configuration override or home. D3 confirms ordinary `~/.claude.json`. |

### Retrieval limitations and recovery actually performed

- W2 proved the wrapper has no old-style `cli.js`; this was not treated as absence of public implementation evidence.
- Older `2.1.89` package listing contains a 13,081,065-byte `cli.js`, but its `webfetch` retrieval exceeded the 5 MB tool limit. No older first-party implementation claims are made.
- Chrome DevTools page creation timed out. The UNPKG native-binary GET returned HTTP 500. A cross-origin browser GET to the official binary failed CORS; navigating to the public manifest on the same origin allowed the ordinary unauthenticated GET to succeed. No CORS/security settings were disabled.
- A guessed community `bin/lib/live-state.cjs` URL returned 404; the pinned repository tree resolved the actual `store/io.cjs`. No claims rely on the failed URL.
- No Intel binary or user's installed executable was inspected. W5 proves this official ARM build's static implementation, not deployment-wide runtime equivalence.

## Validated claims and answers

### Q1 — Default credential contract

**V1 [W1–W5, B1–B3]:** In the inspected production ARM build with no configuration/OAuth overrides, service derivation yields **`Claude Code-credentials`**, generic-password storage. The Keychain account is `process.env.USER || userInfo().username`, limited by `/^[a-zA-Z0-9._-]+$/`; lookup failure or an invalid name uses `claude-code-user`. It is an OS-account selector, not the Claude email. C1's username-only default is therefore incomplete for this version. Do not select an arbitrary first matching service item.

**V2 [W5, B2–B3, B11; D1, D3]:** Config overrides affect both location and Keychain service. `CLAUDE_SECURESTORAGE_CONFIG_DIR` can override secure-storage derivation independently; non-default config paths add an eight-character SHA-256 suffix. Custom OAuth also changes the suffix. The ordinary metadata file is `~/.claude.json`, with a legacy resolver case. None of these overrides or legacy files was checked locally. Fail closed on ambiguous/non-default routing instead of inventing another context.

**V3 [W5, B3–B5, B9]:** The generic-password value is a JSON **secure-storage root**, not just one access token and not exclusively Claude login data. `claudeAiOauth` contains `accessToken`, `refreshToken`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`, `subscriptionType`, `rateLimitTier`, and optional `clientId` according to the storage helpers. Timestamp calculations use milliseconds. Optional values can be absent/null; scopes and tokens must not be fabricated. `mcpOAuth` and `pluginSecrets` use the same root. Preserve the login subtree opaquely, including future keys, rather than rebuilding only these known fields.

**V4 [W5, B4, B8]:** Matching `oauthAccount` identity includes `accountUuid`, `emailAddress`, `organizationUuid`. Observed metadata additionally includes `displayName`, `fullName`, `hasExtraUsageEnabled`, `billingType`, `accountCreatedAt`, `subscriptionCreatedAt`, `ccOnboardingFlags`, `claudeCodeTrialEndsAt`, `claudeCodeTrialDurationDays`, `seatTier`, `profileFetchedAt`; role fetch merges `organizationRole`, `workspaceRole`, `organizationName`. Store the complete per-account subtree with presence semantics, not just email. C6's `workspaceUuid`/`workspaceId` and `organizationId` aliases are community handling, not verified requirements of this exact metadata writer.

### Q2 — Minimum preservation boundary

**V5 [W5, B5, B7–B10; D3]:** Native credential saves spread the current secure root and replace `claudeAiOauth`. Native account changes also prune account-associated secure fields `organizationUuid`, `trustedDeviceToken`, `enterpriseGateway`, and `designOauth`; this disproves a universal claim that swapping the whole root, or always swapping only one token, preserves everything correctly. Native logout invalidates `additionalModelOptionsCache`, `additionalModelCostsCache`, `modelAccessCache`, `orgModelDefaultCache`, `lastSeenOrgDefaultUpdatedAt`, `clientDataCache`, `clientDataCacheSlots`, `autoCompactWindowsCache`, and `cachedUsageUtilization` in the global configuration.

**Engineering recommendation, not a proved runtime sufficiency theorem:** For ordinary subscription logins, snapshot the complete `claudeAiOauth` and matching `oauthAccount`; retain presence-tagged `organizationUuid` and `trustedDeviceToken` with their own account when present. The smallest safe initial adapter must reject unclassified conflicting providers/account-bound state (notably `enterpriseGateway` or `designOauth`) rather than copy, erase, or silently use it across accounts. Supporting such states needs its own verified lifecycle; research has not chosen that product extension. A regular two-login design remains feasible without it. Preserve all unrelated secure-root keys, notably MCP/plugin credentials and device-level state, from the current root.

Replace the incoming **whole `oauthAccount` subtree**, not the entire file and not a deep merge of A's identity into B. Preserve unknown fields within each captured account's own subtree. Missing, null, and present are distinct: if B lacks A's optional role/name field, it must not survive from A. Invalidate the observed account-derived cache keys on switch rather than replaying A's cache as B's; use presence-tagged preimages only for rollback. Do not change `hasCompletedOnboarding`, theme, project trust, `projects`, `mcpServers`, IDE toggles, user settings, permissions, hooks, instructions, skills, plugin configuration, history/session files, or other unknown non-owned keys. Source evidence for caches is not authorization to modify unrelated usage settings or build metrics features.

A field-scoped JSON update can atomically replace the physical file, but it must build from the latest original document, preserve all non-owned values (including unknown large integers), preserve ownership/mode/ACL protections, and detect symlink/race/corruption cases. Never restore a historical whole `.claude.json` or whole credential root from an account snapshot. Source does not prove that native macOS Security APIs can update this existing item's ACL-protected value from the eventual manager binary: that is test G2 below.

### Q3 — Lifecycle, concurrency, and restart

**V6 [W5, B4–B6; D2]:** Claude's refresh code accepts a returned refresh token, keeps the posted token if the server omits a replacement, calculates new expiration, then writes through compare-and-swap against the posted refresh token. It uses `.oauth_refresh.lock`, a legacy lock, and `.storage-write`, and re-reads after locking. This establishes concrete rotation/race handling, not that every refresh rotates or that old tokens always remain valid. The manager must not participate in OAuth exchange or borrow undocumented lock internals as a supported coordination API.

**V7 [W5, B5; C6–C7]:** The dead-token handler deliberately writes `refreshToken: ""`, `accessToken: ""`, `expiresAt: 0` after an `invalid_grant` for the current token. Thus C6/C7's practice of filling empty live fields from old snapshots can resurrect known-dead credentials in 2.1.252. Do not adopt it. Record an unusable/re-login-needed snapshot state, or refuse capture/switch without mutation; an expiry timestamp alone never proves server validity.

**V8 [W5, B2–B3, B5–B8; C3]:** Keychain data has a 30-second cache, failed reads can serve stale cache, and the auth layer memoizes tokens separately. There is change-detection/cache invalidation code; therefore "running sessions can never observe changes" is too strong. Conversely, no inspected source proves arbitrary external swaps atomically reset all identity, policy, model, and session caches. Native login explicitly runs broader in-process account-change cleanup. Restart is the conservative manager requirement, not a claimed universal storage limitation.

**V9 [W5, B4, B7–B8; D1–D2]:** Explicit first-party logout normally attempts refresh-token revocation via the OAuth revoke endpoint, then proceeds with local logout even if revocation fails. Normal login calls cleanup with `preserveInProcessTokens:true` and `preserveNonAnthropicAuth:true`; that branch avoids revoking the outgoing `claudeAiOauth` refresh token, but separately revokes/prunes `designOauth` and clears account-related state. Explicit `/logout` and `claude auth logout` are not safe switching primitives. Server-wide revocation scope, survival across a subsequent login, and continued acceptance of restored tokens were not tested; source control flow is not a promise of indefinite login.

**Operational recommendation:** Stop all Claude Code processes sharing this OS user/storage, including terminal sessions, editor/SDK child processes, background daemons, and Remote Control sessions; keep them stopped through commit or recovery, then start fresh sessions. Do not kill them automatically. A manager lock only serializes managers, not Claude. Detect uncertain process state and refuse mutation; a scan alone cannot eliminate a non-cooperating launch race. Capture the latest outgoing credential and metadata only after quiescence and immediately before writes. Preserve rotated A2 before activating B; switching back must restore A2, not the original A1. During enrollment, capture A before the human signs into B using Claude; later importing B must not overwrite A merely because an old active-alias marker still says A. Compare scoped identity/presence and refuse ambiguity; offline metadata matching is not token authentication.

### Q4 — Smallest recoverable local design

**V10 [D4–D5; W5, B3, B9]:** Native Security framework CRUD supports exact-match updates without delete-before-add; broad update queries can affect multiple items. Keychain storage and JSON-file replacement are separate operations. The inspected native credential fallback can write plaintext and can delete the old Keychain item after fallback succeeds; copying that policy would violate a manager Keychain-only requirement.

**Recommended native/stdlib boundary:** one CLI coordinator, a Security-framework adapter, a field-scoped JSON editor, process preflight, and a per-user interprocess manager lock. No daemon, new database, OAuth client, dependency, or profile-directory migration is needed for the proposed manager. Keep the existing GUI untouched. Store the two login bundles, matching sensitive identity metadata, and recovery journal in manager-owned, local/non-synchronizing Keychain items. On-disk bookkeeping contains only non-sensitive aliases/opaque IDs if needed; never tokens or identity values. Keychain-only describes manager secrets at rest, not Claude's existing metadata file, transient memory, or a guarantee that Claude itself never falls back to plaintext.

1. Lock and check no unresolved recovery; enforce the verified default-storage/version boundary, valid alias, readable unambiguous state, and no active Claude processes. Reject unreadable/locked Keychain, plaintext fallback involvement, corrupt/non-object/duplicate-key JSON, unexpected routing, or unsupported auth state without credential mutation. No implicit import/migration of fallback files.
2. Identify the actual outgoing account; snapshot its latest complete login/identity subset to that account's Keychain slot and verify readback. Do not synthesize a token pair. Acquire the target snapshot and validate structure/presence, not server validity.
3. Write and read back a Keychain-only recovery journal containing operation ID, source/target aliases, before-images of owned secure/config fields, desired after-images, and progress. Keep all unrelated secure data outside per-account snapshots. A complete root may exist transiently in memory for exact-value update, never in plaintext journals.
4. Re-read current secure/config roots and check for races. Update only the owned secure fields on the existing exact Keychain item using `SecItemUpdate`; never delete/re-add it or relax its ACL. Require one intended match. Write a same-directory protected temporary config document derived from the newest root, atomically replace, and verify owned values plus preservation invariants.
5. Mark the active alias only after both resources read back consistently. Commit/clear the journal only after durable success. Report selection completed/restart required, not server authentication verified.
6. On failure, restore only operation-owned fields using the journal and the latest roots; verify rollback. If rollback fails or an unexpected writer changed owned values, retain the journal, report recovery required, and refuse another switch. Do not claim filesystem/Keychain atomicity or erase evidence of a half-switch. Check crash/restart recovery even when the process died between a write and its progress marker.

This is engineering guidance grounded in the observed storage split, not implemented or executed verification. Access-control prompts, crash durability, and safe startup exclusion remain deliberate complexity; simplicity cannot remove them.

## Synthetic examples and verification oracles — not executed tests

Use invented marker strings, not captured credentials. One illustrative account bundle is:

```json
{"alias":"alpha","claudeAiOauth":{"accessToken":"SYNTHETIC-A2-ACCESS","refreshToken":"SYNTHETIC-A2-REFRESH","expiresAt":2000000000000,"refreshTokenExpiresAt":2001000000000,"scopes":["user:profile","user:inference"],"subscriptionType":"pro","rateLimitTier":null},"oauthAccount":{"accountUuid":"synthetic-account-a","emailAddress":"alpha@example.invalid","organizationUuid":"synthetic-org-a","futureAccountField":{"keep":true}},"optionalSecureFields":{"organizationUuid":{"present":false},"trustedDeviceToken":{"present":false}}}
```

The schema is an example, not a final manager wire format or a requirement that all timestamps/fields exist. Keep explicit absent/null/present wrappers for managed optional fields and rollback preimages. Let a current root contain synthetic unrelated `mcpOAuth`, `pluginSecrets`, `coworkRemoteDevice`, and `futureSecureField` sentinels, and let the configuration contain `projects`, `mcpServers`, theme, unknown nested values, and a large integer sentinel.

| Oracle | Required result |
|---|---|
| A1 saved, live A2 rotated, switch A -> B -> A | Outgoing alpha slot becomes A2; return uses A2; B's latest state is checkpointed; no token from A1 is merged. |
| B lacks an optional field present for A | B never retains A's account role/name/device token; switching back restores A's own presence/value. |
| Unrelated root/config content | MCP/plugin secrets, device-level state, trust/settings/history/skills/plugins and unknown values remain unchanged; only allowlisted identity/cache fields differ. |
| Empty live refresh/access token and expiresAt 0 | Fail closed or record unusable status; never refill from an older saved token. |
| Keychain denied/not found/multiple matches, corrupt JSON, unsupported routing, active/uncertain process | No live writes; no plaintext fallback; no sensitive output. |
| Failure at each journal/update/rename/readback/alias/cleanup boundary | Verified owned-field rollback, or persistent recovery-required state; no false success. |
| Concurrent attempts, process appears mid-switch, unrelated external config edit | Serialized managers; unsafe owned-field races abort; unrelated latest edits are not rolled back. |
| Explicit login B after saved A | Import B detects actual scoped identity despite stale alias A; cannot overwrite A with B. |

C7 is reviewed source for synthetic tests in another tool, **not** passing evidence for this design. No new fixtures or tests were created or run. Source-backed oracles answer the research question; the acceptance evidence must be produced during implementation, not invented here.

## Remaining gates before real credential writes

- **G1 — Target contract:** confirm the installed platform/version and manifest identity without exposing credentials; validate resolver/default-context behavior, exact service/account query, and optional/unknown field handling against synthetic inputs. ARM source does not certify Intel or a locally modified executable. Re-research a different version rather than silently trusting this adapter.
- **G2 — Native Keychain integration:** with separately authorized synthetic, manager-namespaced items in an isolated macOS test setup, prove exact `SecItemCopyMatching`/`SecItemUpdate` behavior, ACL and signing prompts, denied/cancelled/locked/missing/duplicate items, attribute preservation, no sync, no argv/log/plaintext leakage, and restart persistence. Synthetic CRUD does not by itself prove access to Claude's actual existing item; the eventual operator must explicitly authorize and validate that boundary before live switching.
- **G3 — Strict-TDD coordinator tests:** implement all oracles through injected stores/process/lock doubles; run the project `./scripts/test` contract. Cover every crash/failure boundary, durable journal replay, token-dead markers, active-alias drift, malformed/duplicate/large-number JSON, symlinks, permissions/ACLs, and unknown-field preservation. No suite was run in research.
- **G4 — Process and account-derived-state contract:** demonstrate no-write behavior with terminal, editor child, daemon/background and Remote Control processes; test non-cooperating startup races and the operational no-launch boundary. Verify the listed cache invalidations and optional trusted-device fields in a synthetic environment; reject unsupported account-bound/provider state rather than silently broadening scope.
- **G5 — Later explicit live acceptance:** only after new authorization, validate A -> B -> A with the user's two Claude-established logins, preserving the same context and observing fresh sessions. Include a Claude-performed refresh and checkpoint, the re-login-needed path, metadata/credential identity agreement, and rollback. Do not use logout as a switch test on saved live bundles. Prove live validity with Claude, not a manager-owned refresh request; do not record tokens or identities in evidence.

## Contradictions, uncertainty, and freshness

- Exact-version source is stronger than agreement between community tools. C1–C3 omit metadata and use delete-before-add/plaintext snapshots; C4–C6 improve identity/rotation handling but write plaintext, suppress errors, and can replace the aggregate secure root. None is a safe implementation template.
- C6's missing-token recovery assumption conflicts with the exact-version deliberate invalid-grant sentinel in B5. Future implementation must not inherit that assumption.
- The ordinary `claudeAiOauth` + `oauthAccount` pair is necessary but not a universal sufficient contract: exact source also exposes device/provider-associated secrets and account-derived caches. The recommendation explicitly accounts for these or refuses unsupported states; it does not claim transparent compatibility for every Claude feature.
- Native refresh/cache coordination exists, so the simplistic claim "all running Claude sessions always keep old credentials forever" is unsupported. Cold restart remains the conservative boundary for an external manager because full hot-switch equivalence was not demonstrated.
- Login cleanup does not revoke the outgoing subscription token in the inspected helper branch; this does not prove backend issuance never invalidates another token or that dormant snapshots remain refreshable. Logout does attempt revocation. No indefinite-login guarantee is supportable.
- Manager Keychain-only storage cannot enforce Claude's own future fallback behavior. Existing fallback or conflicting auth sources must be surfaced as explicit technical preconditions, not migrated silently.
- W5's size/hash/build provide auditable exact-version freshness. D1–D3 describe current documentation and may change. Installed local state, runtime security prompts, service-side responses, and uninspected account-specific features remain unverified.

## Handoff

Research outcome: **done** for Q1–Q4 at the stated static-evidence level. The user explicitly selected `openspec_only`, changing the current session artifact store to `openspec`. Proposal readiness requires successful native OpenSpec readback of this research revision and the current preproposal state, valid native research/exploration references, and the unchanged confirmed decisions. Engram artifacts remain historical, non-authoritative snapshots and are not required mirrors. The parent owns that gate and the proposal; no product discovery is needed for the already-confirmed scope. G1–G5 remain implementation/pre-live acceptance gates. No official-support prerequisite or unrelated third-party routing issue is introduced.

Historical hybrid mismatch at research revision 2 / preproposal revision 4: exact readback found Engram save/update removes the final LF while the permitted file patch tool retains it, including after an explicit no-final-newline patch marker. This remains evidence of unequal bytes; no normalization, byte recovery, or matching-mirror claim is made. Its blocking status is **resolved_by_store_choice** because the user's explicit `openspec_only` decision removes the required hybrid parity condition, not because byte equality changed. The persistence decision is applied once at preproposal revision 5; the earlier `research_now` answer remains applied once at revision 2. Research revision 3 preserves the substantive evidence, source URLs, binary hash, and G1–G5. This store choice authorizes no live credential access or writes, commits, push, or pull requests.
