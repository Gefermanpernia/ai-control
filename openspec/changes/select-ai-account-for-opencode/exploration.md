## Exploration: Select AI Account for OpenCode

### Current State
AI Control is a mock-only SwiftUI menu-bar application. `ControlStore` owns in-memory sample accounts and selection state; there is no persistence, provider integration, or OpenCode adapter yet.

The corrected product boundary is narrow: show three Claude and two OpenAI identities with provider-supported usage, then select which identity a future, independently started ordinary `opencode` process will use. AI Control does not launch OpenCode, manage conversations or models, or handle credential values. A running OpenCode process is unaffected; the user exits or restarts it manually and decides whether to continue an existing conversation.

Verified OpenCode behavior separates configuration from data: credentials are resolved from `${XDG_DATA_HOME}/opencode/auth.json`, while configuration can be resolved through the normal XDG configuration path or `OPENCODE_CONFIG_DIR`. Fully isolating `HOME`/XDG therefore selects a credential store but also produces an empty OpenCode experience unless normal configuration is deliberately preserved. No documented native OpenCode account-profile selector was found for switching multiple credentials of one provider from an AI Control selection.

Selection persistence and selection consumption are distinct problems. AI Control can atomically persist a non-secret account identifier, but an ordinary terminal invocation of `opencode` will ignore that identifier unless a supported hook, shell environment setup, PATH-precedence shim, or mutation of an OpenCode-resolved path bridges it into process startup.

#### Capability Status

| Capability | Status | Evidence / boundary |
| --- | --- | --- |
| Persist a non-secret selected account | Verified platform capability | A small record can be atomically replaced in AI Control's Application Support directory; exact crash-durability semantics need implementation tests. |
| Affect only future OpenCode processes | Verified process behavior | Environment and resolved paths are fixed per process; existing processes remain unchanged. |
| Keep normal OpenCode configuration while changing its data root | Verified from OpenCode source | Configuration and data roots resolve independently. |
| Make an ordinary `opencode` command consume the selector | Required spike | OpenCode has no verified native selector hook; a PATH shim is the least invasive candidate. |
| Show Claude usage for each selected identity | Required spike | Claude exposes rate-limit data after an API response, but availability through `opencode-anthropic-login-via-cli@1.6.1` and per-model detail are unverified. |
| Show OpenAI usage for each selected identity | Required spike | Codex App Server documents account/rate-limit surfaces; compatibility with OpenCode-owned identities and the no-credential boundary is unverified. |
| Pass credentials through `OPENCODE_AUTH_CONTENT` | Unsupported | It contains credential JSON and violates the requirement that AI Control never receive or expose credential values. |
| Transparently switch accounts without any startup integration | Unsupported assumption | Persisting a selector alone cannot alter how an unrelated process resolves credentials. |
| Provision, import, refresh, or repair provider credentials | Deferred/out of scope | Credentials remain owned by provider tooling and the installed OpenCode plugin. |

#### Atomic Persistence Comparison

| Mechanism | Advantages | Limitations | Assessment |
| --- | --- | --- | --- |
| Atomically replaced JSON selector in Application Support | Non-secret, inspectable, schema-versionable, easy for Swift and a shim to read; rename gives readers either the old or new complete record | Explicit `fsync`/directory durability and permissions require tests; account registry changes need validation | Recommended |
| Atomically replaced symlink to an account context | Very small read path; rename can switch the target atomically | Couples persistence to filesystem layout, complicates validation and migration, and risks accidental traversal into credential-owned paths | Not preferred |
| `UserDefaults` / CFPreferences | Native and simple for the app | Cross-process visibility and write timing are less explicit; poor contract for a separately implemented command shim | Reject for the integration boundary |

The recommended record contains only a schema version, stable account ID, provider, and monotonically increasing selection revision. It must never contain tokens, auth JSON, session material, or provider responses. Write a sibling temporary file with restrictive permissions, validate it, atomically rename it over the selector, and define whether crash durability requires file and parent-directory sync. The reader must fail closed on missing, malformed, unknown, or unauthorized selections.

### Affected Areas
- `Sources/AIControlCore/AIControlCore.swift` — replace mock-only selection with stable account identities, a persistence boundary, and provider-neutral usage state.
- `Sources/AIControl/AIControlMain.swift` — present verified identities, usage availability, selection status, and actionable unsupported/error states without exposing secrets.
- `Tests/AIControlCoreTests/ControlStoreTests.swift` — cover atomic selection semantics, future-process-only behavior at the boundary, invalid selectors, and unavailable usage.
- `Package.swift` — may need new executable or library boundaries only if the PATH shim spike proves viable; do not add them before that result.
- `docs/design/provider-capability-evidence.md` — later reconcile evidence with the corrected no-process-management scope.
- `docs/design/provider-integration-architecture.md` — later replace managed-launch assumptions; it is not authoritative for this change as written.
- `docs/design/release-and-distribution.md` — later document shim installation, upgrades, rollback, and credential-boundary guarantees if selected.

### Approaches
1. **Atomic selector plus PATH-precedence OpenCode shim** — AI Control writes only the selected stable account ID. A narrowly scoped `opencode` shim reads it at process start, validates the mapped provider-owned data root, preserves normal OpenCode configuration, and `exec`s the real binary.
   - Pros: Preserves the user's ordinary `opencode` command and existing configuration; selection affects only future processes; no credential values pass through AI Control; rollback can remove the shim and selector.
   - Cons: Command resolution, recursion prevention, shell command hashing, upgrades, permissions, account-root mapping, and compatibility with OpenCode `1.18.27` require proof. The shim becomes startup-critical and must fail closed with a clear recovery path.
   - Effort: Medium

2. **Explicit shell environment or per-account launcher command** — require the user to source an environment or invoke a distinct command that sets the chosen `XDG_DATA_HOME` while retaining normal configuration.
   - Pros: Simple and explicit; avoids intercepting every `opencode` invocation; easy to test and remove.
   - Cons: Does not satisfy transparent selection followed by an ordinary `opencode` command unless the shell is modified; shell state can become stale across terminals and conflicts with the requested application-centered workflow.
   - Effort: Low

3. **Mutate or symlink OpenCode's live credential/data root** — switch a path OpenCode already resolves so no command shim is needed.
   - Pros: Ordinary OpenCode launches naturally consume the active path.
   - Cons: The data root includes more than account selection, so switching it can couple credentials, sessions, logs, caches, and migrations. Moving or linking provider-owned credential stores raises corruption, race, rollback, and ownership risks. This is incompatible with the current safety boundary without much stronger upstream guarantees.
   - Effort: High

### Recommendation
Proceed with a spike-first proposal for **an atomically replaced non-secret selector plus a minimal PATH-precedence shim**. Keep the durable selector contract separate from the OpenCode startup adapter so provider usage collection and UI work cannot gain access to credentials.

The spike must prove, before production design is accepted:

1. An ordinary interactive `opencode` resolves through the shim in supported shells without recursion or stale command-cache surprises.
2. The shim changes only the OpenCode data/credential context and preserves the existing OpenCode configuration, Claude plugin, Gentle AI integration, skills, project working directory, TTY ownership, signals, and exit status.
3. Missing, malformed, unknown, or inaccessible selections fail closed and explain how to run the real OpenCode safely.
4. Selection writes are atomic under concurrent readers and recover predictably from interruption.
5. Account registration maps stable non-secret IDs to provider-owned stores without AI Control reading credential files.
6. Claude and OpenAI usage adapters return only supported non-secret usage and identity metadata, with unavailable/stale states when the provider surface cannot prove the requested data.

Do not base the proposal on `OPENCODE_AUTH_CONTENT`, live credential-root mutation, automatic process relaunch, or guaranteed per-model usage. Those are either prohibited, unsafe, or not yet evidenced.

### Risks
- A shim installed at the wrong PATH position would silently not run; installed incorrectly, it could recurse or shadow OpenCode unexpectedly.
- OpenCode may change its internal data-root/auth resolution in later versions, so compatibility must be version-gated and observable.
- A data-root switch may still affect sessions, logs, caches, or migrations unless the spike proves the exact retained/isolation boundary.
- Provider usage surfaces may be absent until after a request, stale, aggregate-only, or unavailable for some identities; the UI must not fabricate precision.
- Labels and account-root mappings can drift from provider identity. Selection must use stable IDs and expose an explicit unverified/error state rather than guessing.
- Existing design documents encode managed-launch assumptions and could mislead implementation unless reconciled after the proposal.

### Ready for Proposal
Yes, with a **bounded feasibility spike as the first proposal phase**. The proposal should commit to the non-secret selector and credential boundary, while treating the PATH shim, account-root mapping, and both providers' usage adapters as acceptance-gated capabilities rather than completed design facts.
