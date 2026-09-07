## Exploration: Select Claude Code Account

### Current State
AI Control is a macOS 13+ SwiftUI menu-bar application. The executable target only calls `runAIControl()` in `AIControlCore`; the core target contains the UI, models, and `@MainActor` `ControlStore`, while the test target exercises store transitions through Swift Testing.

The current product is a deterministic mock. `CLIProvider` includes Claude and Codex, `ControlStore` owns hard-coded accounts and in-memory active IDs, and `ControlView` renders both provider sections. Selection updates only in-memory state and supports one-step undo. Refresh simulates latency; usage, availability, settings, and status are not provider-backed. There is no persistence, account discovery, shell integration, command adapter, process launch/supervision, or credential access.

The prior `select-ai-account-for-opencode` research remains authoritative for the rejected route: the third-party Anthropic OpenCode plugin lacks a strict non-secret runtime selector, can change identity during fallback, and conflicts with current Anthropic guidance for subscription credentials. This change must not use, fork, or extend that plugin. OpenAI/OpenCode switching is out of scope.

The approved trust boundary is selection-only:

1. Three Claude accounts are logged in independently through provider-owned Claude Code contexts.
2. AI Control maintains a user-facing catalog and persists only an opaque, non-secret context identifier as the active selection.
3. The user selects one context; AI Control atomically replaces that selector and reports that it applies only to future processes.
4. Later, the user manually invokes a command from the normal project working directory.
5. At process start, a documented Claude mechanism—or a separately installed adapter using that mechanism—snapshots the selector, applies only supported non-secret context configuration, and `exec`s the real, unmodified Claude Code binary.
6. Claude Code resolves and operates its provider-owned login state. AI Control and any adapter remain unable to read, copy, mutate, refresh, expose, log, or inject credential values.
7. Already-running Claude processes retain their startup identity. A selection change cannot affect them.

The selector must be an allowlisted opaque ID, never a credential, arbitrary filesystem path, shell fragment, or free-form environment assignment. A missing, removed, ambiguous, or unsupported context must fail closed rather than falling back to another account.

Auth classification: local native controller and CLI; human principal; first-party local selection state; provider-managed subscription authentication; no token boundary enters AI Control; local/managed hybrid hosting; provider owns authentication, recovery, and entitlement enforcement.

Shared versus account-specific boundaries require provider documentation before implementation:

| Concern | Intended boundary | Unknown requiring evidence |
| --- | --- | --- |
| Credentials and login state | Account-specific and provider-owned; never inspected by AI Control | Supported isolation mechanism and lifecycle for three simultaneous logins |
| Active selection | Shared AI Control state containing only one opaque context ID | Provider-supported identifier format and validation method |
| Claude configuration | Share ordinary non-identity configuration where supported | Whether configuration and credentials share a root and whether selective sharing is supported |
| Project/session history | Preserve across selections where provider-supported and identity-safe | Storage paths, account binding, resume semantics, and cross-context compatibility |
| Skills, commands, and hooks | Shared where documented safe | Path resolution and whether context-root changes isolate these assets |
| Gentle AI assets | Shared installation/configuration where documented safe | Which Claude paths or environment inputs Gentle AI relies upon |
| Cache and runtime state | Account-specific when identity-bearing; otherwise share only with evidence | Exact cache/state ownership and consequences of sharing |
| Working directory | Always inherited unchanged from the user's shell | None expected; verify adapter does not change it |
| Child-process environment | Inherit normally, changing at most one documented context selector | Exact supported variable/flag and whether descendants should inherit it |
| Usage metadata | Display only when provider-supported, identity-matched, and fresh | Supported source, identity binding, timestamps, refresh limits, and failure semantics |

No Claude credential values, Keychain entries, credential files, environment values, or other local credential stores were inspected during this exploration.

### Affected Areas
- `Sources/AIControlCore/AIControlCore.swift` — currently combines provider models, mock data, selection transitions, and the entire SwiftUI surface; Claude-only persisted selector state and truthful status semantics would replace the mock multi-provider behavior.
- `Tests/AIControlCoreTests/ControlStoreTests.swift` — currently covers in-memory selection, undo, provider independence, and simulated refresh; future tests must prove atomic persistence, fail-closed stale/removal behavior, future-process-only semantics at the selection boundary, and absence of cross-account fallback.
- `Sources/AIControl/AIControlMain.swift` — should remain a minimal executable entry point; no Claude launching or supervision belongs here.
- `Package.swift` — may need only target/file organization changes if testable persistence or adapter-support abstractions are introduced; no new dependency is justified by current evidence.
- `scripts/test` — remains the repository-wide verification entry point and should not require behavioral changes.

### Approaches
1. **Documented Claude Code context selection** — Use a provider-documented startup flag, environment variable, or configuration-root selector that lets each login remain provider-owned and independently active.
   - Pros: Smallest trust boundary; keeps the binary and authentication flow unmodified; best chance of preserving normal command behavior.
   - Cons: No such mechanism is established by current evidence; path sharing, identity validation, and three-login behavior remain unknown.
   - Effort: Medium, contingent on external research.

2. **Separately installed command adapter** — A distinct, reversible shell command snapshots AI Control's opaque selector, maps it through a documented non-secret Claude mechanism, and directly `exec`s a resolved real Claude binary without reading provider state.
   - Pros: Deterministic per-process selection; preserves working directory and signals; selection changes cannot retarget an already-executed process; AI Control still does not launch Claude.
   - Cons: Adds installation and PATH/command-resolution risk; cannot proceed unless Approach 1 first establishes a supported selector; must avoid recursion, binary substitution, shell evaluation, and accidental environment widening.
   - Effort: Medium.

3. **macOS user/keychain isolation** — Keep each Claude login in a separate OS user and Keychain/home context, with the human entering the desired context before invoking Claude.
   - Pros: Strong credential and process isolation using OS boundaries; does not require AI Control to handle secrets.
   - Cons: High operational cost; fragments configuration, sessions, caches, skills, Gentle AI assets, and project ergonomics; weak fit for one-click selection and continuity.
   - Effort: High; fallback only.

Redirecting global `HOME`/XDG roots, swapping credential files or symlinks, copying provider state, modifying Keychain records, or relying on the rejected OpenCode plugin are not acceptable approaches. They broaden the trust boundary, risk credential mixing, or violate the confirmed product direction.

### Recommendation
Research Approach 1 before proposal. If Anthropic documents a stable non-secret startup context selector with independent login contexts, prefer direct supported configuration. Introduce Approach 2 only if normal human invocation needs a deterministic bridge to that same documented selector. Keep the adapter separately installed and reversible; it must snapshot one allowlisted context, resolve the real binary without recursion, preserve the working directory, modify only the documented selector input, and `exec` without fallback. Approach 3 remains a high-cost recovery option if provider-level isolation cannot satisfy credential blindness.

The smallest credible future architecture keeps persistence and validation in `AIControlCore`, UI as a projection of selector state, and provider authentication entirely outside the application. Persistence should use atomic replacement, retain the prior selector for rollback, and record no provider secrets or credential-store paths. Account removal should invalidate the active selector explicitly. Concurrent launches should each consume one point-in-time snapshot; selection writes must never mutate a shared provider login root underneath startup or running processes.

Selected external research is required with these precise questions:

1. What current Anthropic-documented flags, environment variables, or configuration-root mechanisms let an unmodified Claude Code binary choose among independent login contexts at process startup?
2. Does the supported mechanism permit three contexts to remain logged in simultaneously without copying, rewriting, refreshing, or exposing credential material?
3. Which exact Claude Code paths are identity-specific versus safely shareable for settings, projects, session history/resume data, skills, commands, hooks, MCP/Gentle AI assets, caches, and logs?
4. Can selection be supplied per process without changing `HOME`, the user's shell globally, or unrelated child-process state, and is it snapshotted at startup?
5. What provider-supported command reports non-secret context identity and login validity without exposing tokens, and can it validate a stale or removed selector without silently choosing another account?
6. What compatibility guarantees or version gates apply to the selector and storage layout, and how should unknown or changed Claude Code versions fail closed?
7. What provider-supported usage endpoint/command, if any, binds usage to a verified account identity and freshness timestamp without credential access by AI Control?
8. For a command adapter, what official binary-location and invocation guidance prevents recursive PATH resolution while continuing to use the unmodified Claude binary?

Required source classes: current official Anthropic Claude Code documentation (authentication, settings, environment, CLI reference, session/history, hooks/skills, troubleshooting, legal/compliance, release notes); official Claude Code source or packaged help/version output only where Anthropic documentation explicitly points to it; Apple documentation only for the OS-isolation fallback. Community wrappers, credential managers, and the rejected OpenCode plugin cannot establish support.

### Risks
- **Concurrency:** A mutable shared root or non-atomic selector could bind simultaneous launches to the wrong account. Snapshot once per launch and atomically persist selection.
- **Credential mixing:** Sharing an undocumented root, cache, session, or symlink may combine identities. Default unknown identity-bearing state to account-specific and fail closed.
- **Rollback:** Undo must restore only the prior non-secret selector. Adapter removal must restore ordinary command resolution without touching Claude state.
- **Command resolution:** PATH shadowing can recurse, invoke the wrong binary, or become a code-execution boundary. Use a separate command name unless installation and real-binary resolution are explicit and reversible.
- **Stale selection/account removal:** A deleted, logged-out, renamed, or inaccessible context must become visibly unavailable; never auto-select another logged-in account.
- **Version compatibility:** Undocumented path behavior can change between Claude Code releases. Unknown selector/storage versions must disable switching rather than guess.
- **Usage attribution:** Usage can be mislabeled after context changes or stale refreshes. Show it only with provider-supported identity and timestamp evidence; otherwise show “Unavailable” or “Stale.”
- **Continuity:** Session/history assets may be account-bound even if technically shareable. Resume must not cross identities unless Anthropic documents it as safe.
- **Scope drift:** Reintroducing Codex/OpenCode or the third-party plugin would invalidate the Claude-first boundary and repeat the prior rejected architecture.

### Ready for Proposal
No. Product scope and trust boundaries are sufficiently defined, but the mechanism connecting a non-secret selector to an unmodified future Claude process is not established. Run selected external research on the eight questions above. A proposal becomes permissible only if official evidence establishes a supported selector and clarifies identity-specific versus shared state; otherwise record that provider-level multi-account selection is unsupported and retain macOS user isolation only as the explicit high-cost fallback.
