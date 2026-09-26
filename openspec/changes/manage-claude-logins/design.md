# Design: Manage Claude Logins

## UI-A → UI-B — Responsibility Division (Planning Only)

Current navigation: completed U5 → UI-A → UI-B → FINAL. Supplied parent authority confirms U5 settlement and acknowledged/burned review `review-ab0ffef2900cdee1`; older pending statements are historical. This single division pass authorizes documentation only; 49/54 tasks remain complete.

| Option | Tradeoff | Decision / owning files and boundary |
|---|---|---|
| UI-A: safe app adapter | Adds an independently testable boundary before any UI consumer | Modify existing `Sources/AIControlCore/ClaudeLoginManager.swift` and `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift`. Start with completed synchronous backend; finish with unused serialized list/use/recover adaptation and sanitized results, default unavailable. Own backend concurrency, error mapping, command-integration tests and evidence. Roll back only these additions/tests/docs after B is absent; retain CLI/U5. |
| UI-B: truthful app behavior | Depends on A, without redesigning its concurrency contract | Modify existing `Sources/AIControlCore/AIControlCore.swift` and `Tests/AIControlCoreTests/ControlStoreTests.swift`. Start with proven A and mock Claude UI; finish with saved-alias store/view behavior and owning state/integration/native-interaction evidence. Replace obsolete Claude mock assertions; retarget genuinely retained mock behavior to Codex. Roll back B-only adaptation/tests/docs, leaving A unused and backend/history intact. |
| One unit / further subdivision | One unit remains oversized; more slices fragment one adapter or one user flow | Choose the minimum two cohesive slices, not line chunks or a gates-only slice; retain stacked-to-main planning, with no branches or Git actions now. |

**Data flow / ownership:** main-actor view/store → dedicated off-main adapter actor → existing `CommandScopedClaudeLoginBackend.perform(.list/.use/.recover)` → sanitized immutable result → main actor. A constructs and retains the non-Sendable backend inside its isolation; no mutable backend crosses executors or gains unchecked Sendable. Each synchronous command runs without suspension through final lock release. Cancellation cannot end an executing transaction or release busy early; B retains the operation until actual completion and uses request identity to reject stale presentation updates. No CLI stdout parsing or parallel credential writer.
**Result contract:** aliases, re-login-needed flags, persisted last-selected hint and typed outcomes only; no snapshots, identity fields or raw errors. Only successful use returns verified-applied; list hints never do. Proven pre-write refusal preserves selection; unknown/partial/cleanup uncertainty never claims unchanged credentials. Recovery completion means checked/resolved recovery, not applied selection or rollback proof when no journal existed; no automatic retry or invented persistent block flag.
**UI contract:** loading, empty, unavailable, disabled, busy, safe error, recovery-required, re-login-needed and verified-application states remain distinct. Claude loses fake usage/readiness/reset/freshness and in-memory Undo; Codex retains explicitly labeled mock behavior, including scoped refresh/warnings. Reload means local list, not usage/token refresh; offline status proves neither validity nor availability. Preserve native labels, keyboard/focus/text status, existing semantic styling/themes and no redesign; no new files, dependencies, token system or migration.
**Evidence:** task mapping and future exact commands are in `tasks.md`. A proves real command composition with injected external IO; B proves observable states and A integration using deterministic completion control. Missing behavior requires genuine RED; already-correct guards remain characterization. Native interaction evidence cannot be replaced by browser checks or SwiftUI View-body assertions.
**Rollout / open decisions:** synthetic-first implementation is PROPOSED for explicit 4.7 approval, not already accepted; it delivers no real account switching. Keep public `UnavailableClaudeLoginBackend` and all guards. G2 ACL/signing/denial, live G5 A→B→A, and desired OpenCode-open writer-safety evidence/approval remain distinct; restart-only acceptance cannot substitute. No live access or guard relaxation follows.
**Budget:** retain the approved shared UI 500, superseding stale 400 wording; measured allocation, unchanged code/test ranges and proposed-only replacement caps are in the latest progress record. Implementation remains BLOCKED; no scope/test reduction, budget transfer or automatic repartition.

## Retained U5 Recovery Children — Historical Planning and Closure Context

U5 (tasks 4.3–4.6) decomposes into U5-P → U5-K; order becomes completed G/J/K/C/L/A/V/O → U5-P → U5-K → UI → FINAL. One unit is not defensible: the honest single-unit forecast is 395–576 authored additions+deletions, 176 above a 400 cap. Two children are the minimum honest split; a third gates-only child would be padding. No task ID is added: 4.3/4.4 are jointly owned, and 4.5/4.6 close with U5-K. The user approved cumulative caps of 400 for each child, with a joint U5 ceiling of 800 outside the earlier L/A/V/O 1600; U5-P completed at 205/400 before U5-K.

| Child | Start → required finished behavior and owning evidence |
|---|---|
| U5-P | `recover` returns exit 3 "not implemented" before backend construction with zero storage IO, while `save`/`use` already refuse pending journals at exit 4 (existing characterization, not artificial RED) → `.recover` becomes a real backend command holding ONE command lock through the final outcome, validating W5 routing before any resource read, loading through `custody.loadRecoveryRecord`, and restoring a `.pending` journal into LATEST roots per the contract below. Prove third-value refusal with zero resource writes, unrelated latest-byte/presence/large-number preservation, changed-roots race refusal, process refusal before each mutation, held-lock contention through every recovery callback, restore-readback and journal-clear faults retaining recovery-required, and owned fixture-directory cleanup. Missing manager item and `journal == nil` are distinct safe zero-write outcomes, never a create and never rollback proof. |
| U5-K | U5-P pending recovery with `.committed` still refusing safely → source-owned after-image verification: every owned key must equal `journal.after`; any mismatch retains recovery-required with zero resource writes and NEVER an automatic rollback. Verified commits resolve by clearing the journal only; the codec already binds `activeAlias == journal.target`. Reconcile the specification's post-commit cleanup scenario: removal may already have occurred, so later absence is ordinary guarded admission and proves neither rollback nor application; a retained committed journal still blocks selection; the existing `cleanupUncertain` exit 3 wording must not become a rollback claim. Then record G1/G3/G4 and the G5 deferral boundary. |

Recovery contract, both phases: every non-recovery precondition passes first — quiescence, lock, readable unambiguous roots, supported routing — or the command refuses at exit 3 with zero writes. Capture only the owned vectors, `claudeAiOauth`/`organizationUuid`/`trustedDeviceToken` and `oauthAccount` plus account caches, from LATEST roots, never historical whole roots. Pending classification is per key: equal to `before` needs no write; equal to `after` schedules restore to `before`; anything else is a THIRD VALUE that refuses the WHOLE recovery without merging or discarding the external value. An empty write set never proves the interrupted switch wrote nothing. Restores patch latest roots through `ScopedJSON.replacing`, guard immediately before each actual mutation, and verify the owned postimage equals `before` before continuing. Clearing reuses the existing `persist(_:permitsJournal:)` guarded save → readback → final check; no third resource, persistent block flag, scripted reset or blind retry. Recovery's entire write set is that owned-field restore plus the clearing persist: no alias change, capture, re-enrollment, refresh or logout. Any uncertainty retains recovery-required and reports non-success; recovery never reports false success.

Evidence boundary: 4.5 records only G1 coded contracts, G3 injected-boundary ordering/zero-write/forbidden-call proof and G4 routing/lock/process preflight, each with exact argv `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests` then `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`, exit status, counts, passed/skipped, raw locator and cleanup. G2 stays PENDING: the opt-in native test remains skipped, and synthetic references or injected status mapping establish no approved-binary ACL, signing compatibility or native denial. 4.6 keeps G5 deferred until separate explicit live authorization; only then may fresh-session A→B→A with A2 checkpoint, re-login-needed and rollback be proved, and only then may live completion be claimed. Open-client acceptance stays separately blocked; passing G5 does not establish it. No token-validity, authentication, usability or process-exclusion claim follows, and public production remains `UnavailableClaudeLoginBackend`.

| Child | This planning | Remaining source | Tests | Closure | Cumulative forecast / cap |
|---|---:|---:|---:|---:|---|
| U5-P | 2 | 85–115 | 120–185 | 10–16 | 217–318 / PENDING |
| U5-K | 37 | 25–40 | 70–115 | 46–66 | 178–258 / PENDING |
| Total | 39 | 110–155 | 190–300 | 56–82 | 395–576 / PENDING |

Counting follows the established convention: literal patch operations including replacements and churn, not net numstat. The planning column is this pass's MEASURED cost including its own budget correction, replacing the prospective estimate exactly once; explicit child rows are charged to that child and every shared heading, table frame, narrative line and the Open Questions refinement to U5-K. Ranges are judgment, not measurements, and no correction reserve is funded. The single human question is whether U5-P and U5-K each receive a cumulative 400 cap — joint U5 ceiling 800, outside the L/A/V/O joint 1600 — because both uppers fit that shape and no single-unit 400 cap is defensible. Stop PARTIAL if any actual charge plus unchanged remaining upper exceeds the approved cap; no automatic repartition, exception, evidence reduction or borrowed L/A/V/O allowance follows. Rollback is behavior-scoped with tests/docs: U5-K committed verification and gate records first, then U5-P command wiring and pending restore, leaving `.pending` and `.committed` journals refusing safely and retaining all failure history. No implementation, test execution, live authorization or Git delivery is permitted by this amendment.

## Approved S Recovery Children — Current Contract

Completed G/J/K/C/L/A/V/O → U5 → UI → FINAL. This amendment supersedes the older aggregate S600 scope/readiness and ordinary interactive continuation prompts: AUTO is approved for remaining dependency-ready work, subject to parent native gates. Cumulative child caps are L/A/V 400 each plus an approved bounded O 555, all inside the joint 1600 that includes historical S599, not 1600 new lines; measured ownership is in `apply-progress.md`. O is complete within approved O555; S aggregate integration is complete only as L/A/V/O proof, not whole-feature or live acceptance, and public production remains unavailable.

| Child | Start → required finished behavior and owning evidence |
|---|---|
| L | Existing command lock and unsafe fixture → safe `SelectionFixture` lifetime for every consumer, including initialization/assertion throws. Exercise actual command USE with competing `ManagerFileLock` acquisition inside resource/custody/process callbacks through capture, mutation/readback and final check; prove post-return reacquisition on success/refusal/throw, guard faults and forbidden later calls, and absence of the exact owned UUID directory. Existing correct locking is characterization, not artificial RED. |
| A | L-safe harness → complete admission/checkpoint proof from valid controls: missing/ambiguous resources or identity and valid-but-unmatched outgoing identity refuse safely; preserve exact manager preimages and permitted A2 checkpoint, fresh/dead same-alias semantics, and zero credential/journal writes on early refusal. Duplicate identities refuse at the existing codec, not a fabricated reachable coordinator state. Fix only demonstrated admission defects. |
| V | L/A plus completed adapters → source-owned secure owned-postimage readback BEFORE configuration replacement, followed by configuration/combined verification and alias-last commit. External fakes supply silent wrong data/read faults; real Manager verification must detect mismatches, not fake readback labels. Preserve unrelated bytes, immediate mutation guards and exact preparation/commit states; secure mismatch forbids configuration writes. |
| V certainty | In BOTH `persist` branches, mark preparation/commit certainty immediately after actual verified `custody.save` returns, before any extra read or fallible postguard. Distinguish mutation with failed custody verification from verified custody followed by extra-read/postcheck failure. Reuse custody verification and owned-vector projection; no IO-foundation edit or transaction framework. |
| O | Locally passing L/A/V → complete cleanup/catch/CLI outcomes and whole-transaction integration. At checkpoint/prepare/resource/combined/commit/clear/final faults assert full checkpoint/snapshot maps, journal before/after/source/target/operation identity, marker, resource bytes and attempted/forbidden later calls with safe diagnostics. Verify operation UUID format/stability, A2→B→A and L contention integration. Verified-commit cleanup failure may leave the journal absent; non-success is not automatic rollback. No U5 recovery implementation. |

L first: repair fixture ownership and author cleanup-only success/throw/init-failure characterization before any fresh baseline. Planned NEW test name `selectionFixtureLifecycle` is not existing evidence: run `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter selectionFixtureLifecycle`, then only after cleanup proof run the focused manager baseline. Never broadly delete unidentified historical temporary directories.
Every child plans baseline and appropriate RED→GREEN or passing characterization with `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test --filter ClaudeLoginManagerTests`, then after its last mutation `env -u AI_CONTROL_KEYCHAIN_TEST_ROOT ./scripts/test`. Record exact argv/exit/scenario/expected-versus-observed/counts/passed/skipped/raw-log locator and cleanup. Existing Swift Testing/Manager tests own the proof; historical S GREEN is subset evidence only. No commands above ran in this documentation amendment.
Rollback remains behavior-scoped with tests/docs: L command/lifecycle, A admission/checkpoint, V persist/resource verification, O outcomes/integration; remove dependent consumers first. Never restore active leaking fixtures or remove resource/failure history. Native G2/G5/open-client permissions and U5/UI/FINAL budgets are unchanged; no credential, live activation or Git delivery permission follows.

## Technical Approach

Native, single-user credential custody; Claude owns authentication. Reuse `AIControl`/`AIControlCore` and no-argument GUI startup; the planning-only UI bridge below supersedes unchanged `ControlStore` scope. Keep the synchronous backend dependency-free; no network/logout/context changes. Authority: proposal/specification, research rev3, state rev5, and the explicit integrated-app product amendment.

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
3. Use: refuse initially dead targets early; uniquely match actual outgoing identity and checkpoint/read back A2, including dead markers. A readable root with missing or null credentials is an exact dead snapshot, not a missing resource: after checkpointing it, a distinct stored usable target may continue, while same-alias selection stops before journal or resource writes. Only then resolve the updated selected snapshot, never captured A1: same-alias uses A2. Checkpoint persistence itself can be uncertain.
4. Persist/readback journal → recompare roots → guarded secure update/readback → guarded config OAuth/cache removal/readback → combined verification → atomic marker+committed-phase persistence/readback → clear/readback journal and final checks. Hold one command lock through the final outcome.
5. U5 owns restart/pending rollback into latest roots only when owned vectors match before/after; third values refuse. Progress never proves writes occurred. Committed journals require after-image verification/cleanup, not automatic rollback. Preserve the outgoing checkpoint; the specification's post-commit cleanup scenario qualifies journal-retention claims, including recovery uncertainty in task 4.4. U4 does not implement the U5 algorithm.

## IO Boundaries

Security adapter selects exactly one generic-password persistent reference: service `Claude Code-credentials`, account derived exactly per research V1. `SecItemUpdate` changes data only, retaining attributes/ACL; never delete/re-add. Manager service `AIControl-claude-logins.v1`, account UID, ACL restricted to approved binary. No plaintext archives, token argv/logs, or shell.

Require research W5 ARM 2.1.252 hash/default resolver. Reject overrides, legacy/fallback/alternate-auth involvement, `enterpriseGateway`/`designOauth` presence, unclassified account-bound state, and denied/cancelled/locked/ambiguous/corrupt storage or missing active resources.

Document adapter patches latest raw JSON via protected same-directory temporary file, fsync/rename/fsync; preserves numbers, owner/mode/ACL. Reject symlinks, changed content/identity/protections; verify preservation. Bound size/depth; validate OAuth structure without token decoding. Keychain roots also retain raw unrelated values.

Descriptor-held per-user `flock` at `~/Library/Application Support/AIControl/claude-login.lock` (0700 directory/0600 file; no symlinks) serializes managers. Native UID/executable/ancestry scans before every write/after verification block active or uncertain terminal/editor/SDK/daemon/Remote Control hosts. Operators must prevent launches throughout. Detection stops writes under the phase-specific failure contract below. Non-cooperating startup and check/write races remain possible; exclusion is not guaranteed.

### U4 F-J → F-K → F-C — Current Documentation-Only Contract

After completed G, review F-J → F-K → F-C → existing S → U5 → UI → FINAL. J supplies shared journal contracts; K and C have no mutual algorithm dependency, only serial review order. This documents the approved split, not implementation or delivery permission.

| Child | Required behavior and proof boundary |
|---|---|
| F-J | Journal/shared foundation: malformed cache `.value` must refuse encode consistently with decode. Exercise hostile serialized `decodeRecoveryRecord` bytes for phase, UUID, aliases, keys, presence, raw values, images and marker; derive every negative from a valid control. Prove exact pending, stale-hint and committed roundtrips. Correct the ACCESS/REFRESH versus A/R wrong-cause fixture as future work; reuse codec/owned-vector validation, no framework. |
| F-K | Secure replacement: exercise actual adapter lookup → read → guard → update, including throwing guard with zero mutation. Assert exact persistent reference/search list, ONLY `kSecValueData`, payload/postimage and unrelated preservation, with no add/delete/re-add. Reuse `IsolatedKeychainAdapter` through fake Security only; no real credential or native ACL claim. |
| F-C | Configuration replacement: expected-root success, cache clearing, presence, unrelated large-number and protection preservation; late-race and throwing-guard refusals preserve exact destination bytes/inode. Explicitly prepare temporary/fixture parents and assert cleanup; historical `try?` cleanup is not proof. Reuse `ProtectedConfigurationFile`, disposable files only, no native credential integration. |

Each child owns source, tests, closure/cleanup and rollback in the existing IO/Manager/Tests boundaries. Revert only owning hunks; dependent S must be absent/reverted before foundation rollback, and all consumers before J shared contracts. Preserve completed G and failure history; child passes cannot clear whole F/U4. Future commands/evidence and cumulative caps are recorded in progress.

The retained F/S bullets below are historical aggregate ownership, now distributed fully across J/K/C; S contracts remain unchanged.

- F: Bound journal bytes/depth before parsing; oversized or excessively deep input cannot reach the recursive parser.
- F: Strictly validate phase, operation ID, aliases and owned-field vectors; pending markers need not equal source because a stale hint is valid.
- F: Before-image projection must match the actual outgoing checkpoint; after-image must match the selected snapshot with caches cleared; committed marker must equal target.
- F: Source-owned resource adapters recompare expected roots/data and guard immediately before actual native update/rename, after lookups; a fake-owned guard algorithm is not evidence.
- F: Reuse `IsolatedKeychainAdapter`, `ProtectedConfigurationFile` and `ScopedJSON`; inject only external/native IO, not a general transaction framework.
- S: Enforce route and actual-root rejection of `enterpriseGateway`/`designOauth`, missing/ambiguous resources, unknown/unmatched outgoing identity and dead/unsupported preconditions before credential writes.
- S: Prepare failure may precede durable journaling but permits no credential writes. From verified preparation until verified commit, failure retains journal-backed uncertainty and stops further writes. After verified commit, use distinct cleanup non-success (existing blocked/nonzero CLI result with a specific safe reason); no third resource or persistent block flag.
- F evidence: Oversized/deep serialized journals rejected before parsing; inconsistent images/marker rejected, with valid stale pending hints accepted.
- F evidence: Exercise the source-owned boundary after lookups and root races through injected OS IO; assert forbidden native mutations, not callback promises.
- F evidence: Preserve exact opaque/presence/unrelated bytes, large integers and cache preimages at the owned-resource boundaries.
- S evidence: A2 → B → A, refreshed/dead same-alias and refusal cases; parameterize checkpoint, prepare, each resource write/readback, combined verification, commit and clear failures with exact durable images, counts and forbidden later calls.
- S evidence: Exercise command USE, not only save/direct backend, with held-lock competition through final outcome and release/reacquisition/cleanup on failures; reuse component variants without a blind cross-product.

Each child owns future baseline, behavioral RED→GREEN, focused/full verification, exact command/results and isolated-harness cleanup evidence. No tests run in this amendment; `tasks.md` maps work units and `apply-progress.md` owns measured cumulative budgets and unchanged native authority.

### Current G-M → G-C Planning Amendment

Human approval covers documentation only; `tasks.md` owns cumulative caps/allocation and `apply-progress.md` records authority/readiness. The following refines G without reopening completed E/C/A validation or permitting production activation.

| Child | Required source and evidence boundary |
|---|---|
| G-M | Narrowly extend C custody and guarded backend: preserve command-initial absence/existence, including an existing empty envelope. Initial confirmed missing creates once; observed existing then missing never creates. Validate initial reads. Source-owned guards execute immediately before each actual create/update, not an arbitrary factory callback plus boolean promise or test wrapper; prove through a plain external store. Preserve E/C validation, no update fallback, persistent-reference/data-only semantics and before-capture/after-verification checks. |
| G-C | Depend on G-M; own command wiring, lock/routing lifetimes and safe diagnostics. Pending journal refuses with exit 4 before capture (design 19; specification requires recovery refusal but gives no numeric exit). Absent/malformed/denied manager-only list performs no Claude capture, create or ACL setup. Keep whole command tests/helpers together. |
| G-C proof | Exercise first enrollment → manual B → second enrollment, same-identity success, collision, duplicate identity, third alias and dead credentials; assert exact snapshot preimages and safe output. Compete for the lock during capture, mutation, readback and final check. Factory/capture/create/update/readback throws must safely exit, release/reacquire the lock and assert directory cleanup. Test process check 1, every pre-mutation check and after verification with precise zero/pre/post-write counts. Use phase-based readback failure fixtures, not an assumed second read that can fail before mutation; reuse component routing/custody variants without a blind cross-product. |

The native adapter may perform lookup between a store-level guard and the actual Security mutation. Future implementation must account for that interval at the source-owned native mutation boundary; a plain-store fake proves only its injected boundary, never the native interval or guaranteed process exclusion. No transaction framework/refactor is authorized. Each child carries its own tests/evidence/rollback; remove dependent G-C first. Whole G requires both children and integration proof, not a G-M-only pass. Runtime evidence remains future isolated fakes/disposable lock directories; no native ACL/G2/G5, full-host scan, credentials or default activation is authorized.

### U3B3 planning-only boundary clarification

The additional user-authorized planning-only pass separates former P into E envelope validation → C custody/persistence, followed by unchanged A creation policy → G enrollment guards. E is pure data admission; C depends on E and owns the existing data-store boundary; A/G reuse both. The retained implementation remains partial, not a validated factory or held-lock composition. `tasks.md` owns cumulative allocation/readiness; no runtime objective, implementation authorization, migration, dependency or source file is introduced. Reuse the synchronous native/stdlib design, not a transaction framework.

| Boundary | Required completion contract, not a claim about current code |
|---|---|
| E: serialized admission | Private Codable DTOs are serialization only, not trust authority. Bound envelope bytes/depth before recursive parsing and bound each embedded raw value; reuse existing bounded/scoped JSON admission and duplicate-key validation. Reject invalid UTF-8/JSON, nested duplicates, malformed presence tags/value combinations, invalid aliases, more than two snapshots, duplicate identities, mismatched declared versus captured identity/usability, and invalid marker/state/version. Preserve opaque raw values/large numbers and missing/null/value distinctions; never reconstruct tokens. |
| E: journal refusal | Absent/null journal represents no pending journal; any non-null journal blocks save/use as recovery-required (malformed state also refuses). Decode cannot silently discard pending recovery data. Do not implement journal writing, switching, or recovery in U3B3; those remain U4/U5. |
| C: custody | Validate the initial existing envelope with E before replacement. Only an initial confirmed missing manager item permits create; denied/cancelled/locked/ambiguous/corrupt reads refuse. Once existence is observed, update-time missing/throw refuses with NO create/retry/delete/re-add. Readback must match bytes and E-decoded state; mismatch/throw cannot report success or an authenticated login. Missing active Claude resources never authorize manager creation. |
| A: creation policy | Manager service stays `AIControl-claude-logins.v1`, account is effective UID, explicitly isolated/local and nonsynchronizing. Existing `SecTrustedApplicationCreateFromPath(approvedBinaryPath, ...)` then `SecAccessCreate(..., [application], ...)` supply `kSecAttrAccess`; inject these OS calls, validate statuses AND non-nil outputs, and fail before item creation if either fails. An arbitrary NSObject tests injection only, not approved-binary ACL creation. |
| A: updates | Reuse the existing unique persistent-reference selection and `SecItemUpdate` with ONLY `kSecValueData`; never change ACL/identity attributes through update or delete/re-add. The factory must align manager service/account with policy; caller-supplied attribute dictionaries cannot establish approval. |
| G: constructor/factory | Constructors retain dependencies without Claude capture or storage mutation. Reuse the current command/backend factory as the command-scoped composition point; a save operation retains one acquired `ManagerFileLock` through all reads, identity decisions, save/readback and final process verification, releasing on every success/throw. Make acquisition errors reach safe CLI handling. No lock per isolated backend method, global lock singleton, or new framework. |
| G: ordering | After lock acquisition, validate W5 routing/hash/default resolver/conflicts before any Claude credential/config read or write; resolve resources only from the validated route. Load/validate manager state and refuse unresolved journal before capture; capture actual current identity under the SAME lock, perform existing collision/capacity/manual-B rules, then persist and verify. State discovered in approved roots must still satisfy all unsupported-account/provider rejection rules before mutation. |
| G: process checks | Require quiescence before capture, immediately before EACH actual manager create/update and after verification. Wire checks at mutation boundaries, not merely around a multi-step custody call. Pre-mutation guard failure has zero credential/manager-state writes; post-mutation failure stops further writes and success reporting but must not claim zero prior writes. There is no U3B3 compensating unjournaled credential rollback. |
| G: list | List reads manager state only: never capture Claude, consult active credential/config roots, or create a manager item when absent. Return empty for absent manager state; malformed/denied state gets a safe refusal. Avoid write-oriented factory setup on this read path; no mutation/ACL-construction side effects hidden in constructors. |

Reuse existing Swift Testing fixtures in `ClaudeLoginManagerTests.swift`, with per-boundary RED→GREEN/full verification, failure-order oracles, cleanup and rollback as specified in `tasks.md`. Tests exercise actual custody/CLI behavior through injected external storage/OS boundaries, not fake verification flags. Local CLI human principal and UID/approved-binary custody remain the trust boundary; Claude alone owns authentication, re-login and token validity. Diagnostics contain only aliases/safe states, never credentials or identity values.

Native G2 approved-binary ACL/signing compatibility and denied behavior require separately authorized isolated native evidence; synthetic attributes or successful CRUD cannot establish them. `UnavailableClaudeLoginBackend` remains the public default until all native protections are verified and separately approved. No new field or flag is presumed to represent that approval. U4/U5 and live G5 remain unchanged and excluded from this amendment.

### Integrated Saved-Alias UI Bridge — Planning Only

Current source confirms mock `ControlStore`/`ControlView` and no UI-safe projection API; guarded `use`/`recover` are implemented and synthetically verified, while public production remains unavailable. The responsibility division above supersedes the earlier CLI-stub assessment, not its retained evidence history.

| Boundary | Planned contract |
|---|---|
| App/store | In existing `AIControlCore.swift`, load saved aliases and project only non-secret manager status. Keep credentials/identity/opaque snapshots inside the core backend; do not parse CLI stdout or duplicate transaction logic in views. |
| Selection | Depend on complete G-M/G-C and U4/U5; expose their shared guarded use/recovery result through a narrow app boundary in existing `ClaudeLoginManager.swift`. UI work owns adaptation only, never unfinished backend requirements or their cost. |
| Execution | Keep the UI responsive without weakening command-scoped lock lifetime; serialize selection/recovery, disable duplicate actions and discard stale load completions. Do not spawn a login/logout shell or manage OpenCode tasks. |
| Display | Loading/empty/unavailable/error/recovery-required/re-login-needed/in-progress/success are distinct. Marker means persisted hint; applied means verified storage application, not authenticated. Pre-write failure preserves app selection; uncertain writes retain last-known context with recovery warning, not false restored-state success. |
| Existing mock controls | Remove misleading Claude usage/readiness/reset/freshness claims from the saved-alias path and clarify mixed mock/provider copy. No arbitrary Codex/provider redesign. Hide Claude's in-memory Undo; only guarded backend recovery can restore uncertain writes. |
| Interaction | Native labeled controls, keyboard selection, visible focus, non-color status, existing semantic styling/themes; no visual redesign or new token system. Empty/dead states explain manual enrollment/re-login. Reload never means credential refresh or automatic retry. |

Open safety validation gate: the broad stopped-host/launch-prevention contract above remains enforced pending reconciliation with the desired open idle OpenCode client. Current native roles rely on exact trusted paths/ancestry or uncertainty, not automatic OpenCode name detection; they do not prove request quiescence. User-owned cancellation/resubmission is separate from storage-write safety. No invented attestation, flag or API permits bypass. Controlled proof must address writer activity/refresh, check-write races and refusal before any guard relaxation or live activation; inability to prove safety leaves the product acceptance blocked for human decision.

The reported five-hour-backoff → official CLI logout/login → Esc twice → resubmit success is observation only, not verified mechanism/account attribution or concurrency evidence. Fresh-session G5 remains required but cannot alone establish open-client acceptance. Native ACL/G2/signing/denied and G5/live work each retain separate authorization; public production remains `UnavailableClaudeLoginBackend` until approved gates. Doubles may prove bridge contracts first, never production usability.

UI evidence belongs in existing `Tests/AIControlCoreTests/ControlStoreTests.swift` (observable state) and `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` (shared boundary), using current Swift Testing. Future authorized RED→GREEN covers saved-not-mock aliases, success/failure/recovery/dead/unavailable states, duplicate/stale operations, secret absence and no CLI login/logout/OpenCode interaction. Native keyboard/theme/status acceptance is separately reported; no render-only test substitutes for behavior or real safety evidence. Rollback removes only bridge/store/view adaptation and its owning tests/docs, retaining CLI, G/U4/U5 and failure history. Forecast and stop condition are in `tasks.md`; no tests or UI implementation run in this amendment.

## File Changes

| Path | Action |
|---|---|
| `Sources/AIControl/AIControlMain.swift` | Modify: dispatch before GUI |
| `Sources/AIControlCore/ClaudeLoginManager.swift` | Planned new: CLI/coordinator/contracts |
| `Sources/AIControlCore/ClaudeLoginIO.swift` | Planned new: native adapters |
| `Sources/AIControlCore/ScopedJSON.swift` | Planned new: lossless editor |
| `Tests/AIControlCoreTests/ClaudeLoginManagerTests.swift` | Planned new: manager behavior |

`Package.swift` and `scripts/test` stay unchanged; native imports suffice. The UI bridge adds planned edits only to existing `Sources/AIControlCore/AIControlCore.swift` and `Tests/AIControlCoreTests/ControlStoreTests.swift`, plus the existing manager/test paths above; UI tests own safe observable state, never credentials.

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
| App → command-scoped backend | Applicable: reuse native guards without new routing, shell, subprocess or VCS automation. UI-A must prove manager-only list has no capture/create/ACL setup, unsafe use/recover refuse without writes, and cancellation cannot shorten lock custody; safe typed outcomes contain no secrets. Plan missing-adapter RED at this boundary; existing native/CLI guards remain characterization. Other matrix rows remain explicit N/A as above. |

## Migration / Rollout

No migration. G1–G4 precede separately authorized G5 live A→B→A fresh-session acceptance; G5 includes refresh/checkpoint, re-login-needed, identity agreement, rollback. No live completion before G5; no credential access or runtime tests now.

## Open Questions

Current decisions are the UI joint/child budget proposal and explicit synthetic-first 4.7 disposition above; neither is implementation consent. U5 settlement/review is complete per supplied parent authority, not reopened here. G2, G5 and OpenCode-open acceptance remain independently unresolved; all earlier failure history is retained.
