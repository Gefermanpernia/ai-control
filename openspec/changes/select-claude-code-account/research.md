---
schema: gentle-ai.sdd-research/v1
change: select-claude-code-account
revision: 3
mode: interactive
source_lock:
  evaluated_at: 2026-09-04
  capability:
    required_schema: gentle-ai.sdd-research-capability/v1
    declaration_supplied: true
    observed_grants:
      - documentation
      - open-web
  requested_source_classes:
    - documentation
    - open-web
  admitted_source_classes:
    - documentation
    - open-web
  denied_source_classes: []
outcome: done
proposal_ready: false
next_recommended: orchestrator-product-discovery-on-negative-evidence
---

# Research: Select Claude Code Account

## Executive Summary

Anthropic documents one supported non-secret mechanism for running independent Claude Code login contexts: set `CLAUDE_CONFIG_DIR` to a different configuration directory for each process. The documentation explicitly describes this as useful for running multiple accounts side by side. On macOS, Claude Code keys its Keychain entry to the selected directory, and its file fallback is stored under that directory. Three provider-owned contexts can therefore remain independently logged in without AI Control reading, copying, rewriting, or injecting credentials.

That evidence does **not** satisfy the complete product contract. `CLAUDE_CONFIG_DIR` selects an entire configuration root rather than a stable provider-issued account identifier. Anthropic documents higher-precedence credential sources, including provider variables, bearer tokens, API keys, helpers, OAuth-token variables, and named profiles. Consequently, a process launched with a valid configuration directory can authenticate through a credential other than that directory's `/login` credential. Current documentation does not offer a strict “this root and no other credential source” mode while preserving the inherited environment unchanged.

`claude auth status` is a supported JSON command with exit code 0 when logged in and 1 when not, but Anthropic does not publish a stable JSON field contract for account identity. Interactive `/status` can show login method, organization, email, and expired-login information, but it is not documented as an external machine-readable identity interface. Likewise, `/usage` and status-line JSON expose useful usage and reset information, but no documented payload binds that usage to a stable verified account identity. AI Control therefore cannot truthfully promise verified account selection, stale-selector detection without fallback, or identity-bound fresh usage under the approved one-variable, credential-blind boundary.

The research outcome is `done` because all selected questions have current official evidence and explicit negative findings. Proposal readiness remains false pending orchestrator-owned product decisions that narrow the product promises or change the constraints.

## Research Questions

| ID | Answer | Outcome | Confidence | Evidence |
| --- | --- | --- | --- | --- |
| Q1 | Use a distinct `CLAUDE_CONFIG_DIR` in each Claude Code process launch. No documented CLI flag selects a subscription account by ID; the supported selector is the configuration root. | Supported with limitation | High | S1, S2, S3 |
| Q2 | Yes. Anthropic explicitly describes `CLAUDE_CONFIG_DIR` as useful for multiple accounts side by side and documents directory-keyed macOS Keychain entries plus directory-local credential-file fallback. Each context must be logged in through Anthropic's own flow. | Supported | High | S1, S2, S10 |
| Q3 | The selected root's credentials, user settings, sessions, plugins, user assets, generated memory, caches, logs, and usage data must be isolated by default. Repository-scoped `.claude/` assets and `.mcp.json` remain tied to the unchanged working tree and can be shared when they contain no identity-bound values. `~/.claude.json` and Gentle AI assets require conservative handling described below. | Partially supported classification with explicit unknowns | Medium | S2, S3, S4, S5, S11, S12, S13 |
| Q4 | The selector can be supplied in the launch environment of one process without changing `HOME`, the global shell, or the working directory. Shell environment changes are documented to affect the next launch. This supports future-process selection, but Anthropic does not guarantee that every setting or identity input is immutable for the lifetime of a running session. | Supported for process launch; broader snapshot guarantee unsupported | High / Medium | S2, S3, S5 |
| Q5 | `claude auth status` reports JSON and login validity by exit status. `/status` shows richer human-readable account and expiry information. Neither source documents a stable machine-readable account identifier or strict no-fallback validation, and credential precedence can authenticate from outside the selected root. | Login check supported; required identity/no-fallback guarantee unsupported | High | S1, S6 |
| Q6 | `claude auth status` requires v2.1.41+. `CLAUDE_CODE_PROJECT_DIR_NAME` requires v2.1.234+ if used. No introduction version or long-term storage compatibility guarantee is documented for `CLAUDE_CONFIG_DIR`, and transcript formats are explicitly internal and change between versions. Unknown or unparsable versions must therefore be a product-level fail-closed gate. | Limited version gates supported | High | S5, S9, S14 |
| Q7 | `/usage` provides plan bars and reset/activity data; status-line JSON provides rate-limit percentages and `resets_at` values after the first API response for eligible sessions. `/usage` may show cached values up to 60 minutes old. No documented source binds those values to a stable identity in the same payload. | Usage available; verified identity-bound freshness unsupported | High | S7, S8 |
| Q8 | The recommended native install manages `~/.local/bin/claude` as a symlink into `~/.local/share/claude/versions/`; `claude --version` verifies the installation. A separately named adapter can execute an explicitly resolved launcher without recursive `PATH` lookup. Other installation methods do not share that fixed path, so an adapter must register or resolve an absolute non-self path and fail closed when it cannot. | Supported for native install; conditional for other installers | High | S9, S10 |

## Admission

- Required capability schema: `gentle-ai.sdd-research-capability/v1`
- Requested source classes: `documentation`, `open-web`
- Supplied declaration: exact schema with both requested grants
- Admitted grants: `documentation`, `open-web`
- Admission result: passed before source access
- Source policy: current first-party Anthropic documentation and first-party changelog only; no community wrapper or credential manager was used to establish support
- Security boundary observed: no Keychain entry, credential file/value, environment value, authenticated session, local identity, local usage record, login/logout flow, or provider state was accessed or mutated

## Sources

### S1 — Authentication

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/authentication
- Accessed: 2026-09-04
- Excerpt: “If you've set the `CLAUDE_CONFIG_DIR` environment variable, Claude Code keeps the `.credentials.json` file under that directory … and keys the macOS Keychain entry to that directory too, so a session with a different `CLAUDE_CONFIG_DIR` reads a different entry.”
- Excerpt: Authentication precedence places cloud-provider credentials, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `apiKeyHelper`, `CLAUDE_CODE_OAUTH_TOKEN`, and named/federation profiles ahead of the subscription OAuth credential from `/login`.

### S2 — Environment variables

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/env-vars
- Accessed: 2026-09-04
- Excerpt: “`CLAUDE_CONFIG_DIR`: Override the configuration directory (default: `~/.claude`). All settings, session history, and plugins are stored under this path. … Useful for running multiple accounts side by side.”
- Excerpt: Shell environment variables are read at startup and changes take effect the next time `claude` launches; project and local settings cannot set variables that choose Claude Code's own storage location.

### S3 — Claude Code settings

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/settings
- Accessed: 2026-09-04
- Excerpt: User settings are stored in `~/.claude/settings.json`; shared project and project-local settings are stored in `.claude/settings.json` and `.claude/settings.local.json` in the project.
- Excerpt: Claude Code also keeps `~/.claude.json`, which holds sign-in session data, MCP configurations, per-project state such as trust decisions, and global configuration keys.

### S4 — Explore the `.claude` directory

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/claude-directory
- Accessed: 2026-09-04
- Excerpt: “If you set `CLAUDE_CONFIG_DIR`, every `~/.claude` path on this page lives under that directory instead.”
- Excerpt: Project `.claude/` contains committed settings, skills, commands, hooks, and other project assets; the global directory contains personal settings, projects, memory, skills, commands, agents, workflows, and generated state.

### S5 — Manage sessions

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/sessions
- Accessed: 2026-09-04
- Excerpt: Transcripts default to `~/.claude/projects/<project>/<session-id>.jsonl`; setting `CLAUDE_CONFIG_DIR` moves storage off `~/.claude`.
- Excerpt: Transcript entry format is internal and changes between versions. `CLAUDE_CODE_PROJECT_DIR_NAME` is read once at startup, requires `CLAUDE_CONFIG_DIR`, and requires v2.1.234+.

### S6 — CLI reference

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/cli-reference
- Accessed: 2026-09-04
- Excerpt: “`claude auth status`: Show authentication status as JSON. Use `--text` for human-readable output. Exits with code 0 if logged in, 1 if not.”
- Excerpt: The CLI reference documents no flag that selects a Claude subscription account by provider-issued account ID.

### S7 — Manage costs effectively

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/costs
- Accessed: 2026-09-04
- Excerpt: Pro and Max subscribers see plan usage bars, activity statistics, and a usage breakdown in `/usage`; the local breakdown is approximate and excludes other devices and claude.ai.
- Excerpt: When the usage request fails, `/usage` can show the last bars loaded on the machine within the past 60 minutes and labels them “Showing last-known usage.”

### S8 — Customize your status line

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/statusline
- Accessed: 2026-09-04
- Excerpt: Status-line commands receive JSON on stdin. Eligible sessions can receive `rate_limits.five_hour` and `rate_limits.seven_day` percentages and Unix `resets_at` timestamps after the first API response.
- Excerpt: The documented schema contains session, workspace, model, version, cost, context, and rate-limit fields, but no account, email, organization, or credential-source identity field.

### S9 — Advanced setup

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/setup
- Accessed: 2026-09-04
- Excerpt: Native installations manage `~/.local/bin/claude` as a symlink into `~/.local/share/claude/versions/`; `claude --version` prints the installed version.
- Excerpt: Claude Code can be installed natively, through Homebrew, WinGet, Linux package managers, or npm, so the native path is not universal.

### S10 — Legal and compliance

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/legal-and-compliance
- Accessed: 2026-09-04
- Excerpt: The Claude Code binary must be installed and run as published by Anthropic and must not have built-in authentication methods removed, disabled, or restricted.
- Excerpt: Each end user must authenticate with their own credential through Anthropic's flow; third-party developers may not collect, store, or intermediate Claude.ai credentials or session tokens.

### S11 — Extend Claude with skills

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/skills
- Accessed: 2026-09-04
- Excerpt: Personal skills live at `~/.claude/skills/`; project skills live at `.claude/skills/`. Existing `.claude/commands/` files remain supported as the same command mechanism.
- Excerpt: A personal or project skill entry may be a symlink to an external directory, while skills synced from claude.ai are account-enabled and downloaded beneath the user root.

### S12 — Hooks reference

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/hooks
- Accessed: 2026-09-04
- Excerpt: Hooks can be defined in user settings, project settings, project-local settings, managed policy, plugins, skills, and subagents; repository hooks can be committed, while user and local hooks remain machine-local.

### S13 — Connect Claude Code to tools via MCP

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/mcp
- Accessed: 2026-09-04
- Excerpt: Project MCP servers are stored in `.mcp.json`; user and local-scope server definitions are stored in `~/.claude.json`.
- Excerpt: Project configuration can reference environment variables for secrets; remote-server OAuth sign-ins and endpoint-specific state are not equivalent to shareable configuration.

### S14 — Claude Code changelog

- Class: `open-web`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/changelog
- Accessed: 2026-09-04
- Excerpt: v2.1.41 added `claude auth login`, `claude auth status`, and `claude auth logout`.
- Excerpt: v2.1.234 added `CLAUDE_CODE_PROJECT_DIR_NAME` for hosts that provide each session with its own configuration directory.

## Validated Claims

| ID | Claim | Sources | Confidence |
| --- | --- | --- | --- |
| C1 | `CLAUDE_CONFIG_DIR` is the current provider-documented selector for independent local Claude Code configuration/login contexts. | S1, S2 | High |
| C2 | Anthropic explicitly supports using distinct roots to run multiple accounts side by side. | S2 | High |
| C3 | On macOS, each selected directory addresses a different Keychain entry; file fallback credentials are also directory-local. | S1 | High |
| C4 | Three contexts can be logged in independently through provider-owned login flows without AI Control handling credential material. | S1, S2, S10 | High |
| C5 | The selector can be set in one process's launch environment while preserving the working directory and global `HOME`. | S2, S5 | High |
| C6 | Project and local settings cannot set `CLAUDE_CONFIG_DIR`; launch environment, user settings, or managed settings can. A deterministic adapter should use the launch environment. | S2 | High |
| C7 | User settings, session history, plugins, transcripts, generated memory, and other documented `~/.claude` state move under the selected root. | S2, S4, S5 | High |
| C8 | Repository-scoped `.claude/` and `.mcp.json` remain project files resolved from the working tree, not the selected user root. | S3, S4, S11, S12, S13 | High |
| C9 | Repository configuration is shareable only as configuration; it may reference or execute identity-sensitive external values and therefore is not evidence that secrets or OAuth state are shareable. | S12, S13 | High |
| C10 | `~/.claude.json` contains sign-in/session-adjacent state, trust decisions, user/local MCP definitions, and UI state; the reviewed docs do not explicitly map this sibling file to a selected `CLAUDE_CONFIG_DIR`. | S3, S4, S13 | Medium |
| C11 | `claude auth status` supports JSON and binary login validity through exit status, but its stable JSON identity schema is undocumented. | S6, S14 | High |
| C12 | `/status` is richer for a human, including active login method and expired-login context, but is not documented as a machine-readable external identity contract. | S1, S3 | High |
| C13 | Credential precedence permits authentication through sources outside the selected directory and can defeat strict root-to-account binding. | S1 | High |
| C14 | `claude auth status` is available from v2.1.41; optional custom transcript-directory naming is available from v2.1.234. | S5, S14 | High |
| C15 | No official minimum version or stable storage/API compatibility promise was found for the `CLAUDE_CONFIG_DIR` multi-account behavior. | S2, S5, S14 | Medium |
| C16 | Status-line JSON exposes machine-readable usage-window percentages and reset timestamps, but no account identity; `/usage` may use a cache up to 60 minutes old. | S7, S8 | High |
| C17 | The native launcher path is documented, but no single absolute path covers every supported installer. | S9 | High |
| C18 | A product integration must execute the unmodified Anthropic binary and keep credential collection/intermediation outside its boundary. | S10 | High |

## State Classification

### Account-specific or isolated by default

- The macOS Keychain entry selected by `CLAUDE_CONFIG_DIR` and any `.credentials.json` fallback.
- Everything generated beneath each selected user root, including user settings, session transcripts, auto memory, plugins, plugin data, user-level skills/commands/hooks, caches, debug logs, usage reports, and other runtime state. Some entries may be semantically reusable, but Anthropic does not declare the whole root safe to merge across identities.
- Skills synced from claude.ai and remote MCP OAuth state, because their lifecycle depends on the authenticated account or endpoint.
- `~/.claude.json` until Anthropic explicitly documents how the sibling global file is relocated or partitioned by `CLAUDE_CONFIG_DIR`. It contains sign-in/session-adjacent and trust state and must not be copied, linked, merged, or inspected by AI Control.

### Shareable only through explicit project or managed scope

- Project `CLAUDE.md`, `.claude/settings.json`, project skills, commands, hooks, agents, rules, workflows, and `.mcp.json`, because they remain in the unchanged working tree and are documented as repository-shareable.
- Managed policy deployed independently of an account root, subject to the organization's own identity and policy controls.
- Shareability applies to definitions, not embedded secrets. Project MCP and hook definitions can consume environment values or execute code; they require ordinary workspace trust and security review.

### Conditional or not provider-classifiable

- Personal skills may point to an external directory through a documented symlink, but that is a deliberate user configuration choice, not evidence that all user-root state can be shared. AI Control should not create or rewrite these links.
- Gentle AI is not an Anthropic-defined asset class. Project-resident Gentle AI assets follow project scope; assets placed beneath a selected Claude user root are isolated with that root; external installations are outside Anthropic's documented account-state model and need their own evidence before any sharing claim.
- `.claude/settings.local.json` is a personal project file containing local overrides and approvals. It remains in the shared working tree across account launches, but should not be treated as provider identity state or silently rewritten per account.

## Contradictions and Tensions

1. Anthropic explicitly advertises `CLAUDE_CONFIG_DIR` for multiple accounts and documents directory-keyed credentials, while separate documentation identifies `~/.claude.json` as holding sign-in/session-adjacent state without explicitly stating how that sibling file relocates. The documented multi-account guarantee is accepted; the undocumented sibling-file boundary remains isolated/unknown rather than presumed shareable.
2. Directory-keyed `/login` credentials suggest deterministic context selection, but documented credential precedence allows environment credentials, helpers, profiles, and provider selection to override them. A configuration root is therefore not a strict exclusive account selector under an arbitrary inherited environment.
3. Status-line JSON offers current rate-limit percentages and reset timestamps, while `/usage` can show up-to-60-minute cached bars. Neither source includes a stable account identity, so freshness alone cannot prove attribution.
4. The launch environment supports per-process root selection, but Claude Code hot-reloads many settings and credential helpers. “Future launches use the selected root” is supported; “all identity and configuration are permanently snapshotted at startup” is not.

## Uncertainty and Freshness

- Evidence was accessed on 2026-09-04 from current Anthropic documentation and the first-party changelog. Claude Code updates frequently; all claims must be revalidated before implementation if the docs or supported version range changes.
- No authenticated local command was run, so no undocumented `claude auth status` JSON field was observed or promoted into the contract.
- No stable provider-issued identifier for a `CLAUDE_CONFIG_DIR` root was found. The product's opaque selector would identify an AI Control catalog entry, not an Anthropic account.
- No explicit introduction version for `CLAUDE_CONFIG_DIR` was found. v2.1.41 is only the verified floor for the planned `auth status` check, not proof of every current storage behavior at that version.
- The documentation does not establish a strict no-fallback mode for subscription login when higher-precedence credentials are inherited.
- The status-line schema can provide usage reset timestamps only after a qualifying session's first API response and does not bind them to account identity.
- Direct parsing of transcript files is unsupported because Anthropic explicitly calls the format internal and version-variable.
- Installer-specific launcher paths beyond the native install require separate, current evidence or explicit registration.

## Non-Authoritative Product Choices

The following are decision inputs for the orchestrator, not research conclusions or user consent:

1. Narrow “account selection” to “launch one named Claude configuration context,” display only user-authored labels, and avoid claiming verified Anthropic identity.
2. Decide whether login availability from `claude auth status` is useful despite the inability to prove exclusive root binding under inherited higher-precedence credentials.
3. Keep account-level plan usage unavailable until one provider-supported payload supplies both stable identity and freshness, or remove usage from this change.
4. Decide whether the one-variable environment constraint may be widened to reject or sanitize known higher-precedence authentication variables. This would be a trust-boundary change and still must not expose credential values.
5. Keep session/history continuity inside each selected root; do not promise resume continuity across roots.
6. Choose whether the initial adapter supports only Anthropic's native installation path or requires users to register an absolute Claude binary path for other installers.
7. Define an allowlisted Claude Code version range and fail closed on missing, malformed, older, or unreviewed versions; do not infer compatibility from “latest.”

## Readiness

- Evidence outcome: `done`
- Source classes admitted: `documentation`, `open-web`
- Questions mapped to current official evidence: 8 of 8
- Unsupported guarantees admitted as facts: none
- Proposal ready: `false`
- Blocking product gaps:
  - no documented exclusive account binding for `CLAUDE_CONFIG_DIR` under inherited credential precedence
  - no stable machine-readable account identity contract
  - no guaranteed stale/removed selector detection without fallback
  - no provider-supported payload that binds account-level usage to verified identity and freshness
  - no confirmed product decision narrowing these promises or widening the trust boundary
- Next recommendation: return to orchestrator-owned product discovery, persist the decisions, and invoke proposal work only if the resulting scope remains truthful and supported