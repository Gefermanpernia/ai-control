---
schema: gentle-ai.sdd-research/v1
change: select-ai-account-for-opencode
revision: 4
mode: interactive
source_lock:
  retrieved_at: 2026-09-04
  capability:
    schemaName: gentle-ai.sdd-research-capability
    schemaVersion: 1
    grants:
      - documentation
      - open-web
  requested_source_classes:
    - documentation
    - open-web
  denied_source_classes: []
outcome: done
proposal_ready: false
next_recommended: sdd-explore
---

# Research: Claude Account Selection for OpenCode

## Executive Summary

The research request is complete, but the selected product approach is not proposal-ready.

`opencode-anthropic-login-via-cli@1.6.1` can discover a main Claude Code credential and CCS instance credentials, enroll one of them into OpenCode, refresh OAuth tokens, and replace OpenCode's Anthropic fetch implementation. It does not expose a stable non-secret runtime selector that AI Control can update. Its recovery path can also switch to another discovered identity and overwrite OpenCode's single `anthropic` auth record.

More importantly, Anthropic's current Claude Code legal and compliance documentation says subscription OAuth is intended for native Anthropic applications and ordinary use of the unmodified Claude Code binary. It explicitly says third-party developers may not route requests through Free, Pro, or Max credentials. The pinned plugin rewrites OpenCode requests to carry Claude Code identity, tool naming, billing metadata, and classifier-compatible text. That behavior is outside the documented permitted boundary.

The SDD proposal must therefore remain blocked unless Anthropic grants written permission for this integration or product discovery selects a supported boundary, such as Anthropic API-key authentication or unmodified Claude Code.

## Research Questions

| ID | Question | Result |
| --- | --- | --- |
| Q1 | Does the pinned plugin expose a stable non-secret selector for the main Claude context or one CCS context? | No. Contexts are exposed as one-time OpenCode enrollment methods. No documented or source-visible startup/runtime selector is consumed by request handling. |
| Q2 | Can AI Control change the active Claude identity without reading or writing token material? | Not with the unmodified plugin. OpenCode stores one OAuth record under `anthropic`; switching that record requires OAuth material, while external credential discovery is not selector-bound. |
| Q3 | Does request handling remain bound to the selected identity through refresh and provider errors? | No. Refresh can fall back to CLI credentials, and selected `401`, `429`, or `529` responses can trigger another discovered main/CCS credential and overwrite OpenCode auth before retrying. |
| Q4 | Can ordinary manually launched OpenCode retain shared sessions, configuration, plugins, skills, and tooling? | Installing the plugin globally preserves ordinary OpenCode launch behavior, but stock `1.6.1` provides no persistent selector for those launches. Redirecting `HOME` or the XDG data root is rejected because it changes unrelated OpenCode state and child environments. |
| Q5 | Can account usage be attributed reliably to the identity selected in AI Control? | No. The plugin exposes no stable selected-identity metadata, and automatic fallback can change the billing identity during a request. Identity-correct usage attribution cannot be claimed. |
| Q6 | What security and operational behavior enters the trust boundary? | The plugin reads Keychain/filesystem credentials, executes local commands, scans the Claude binary, performs an npm registry update check, patches request/response bodies, refreshes and persists OAuth tokens, and writes debug logs enabled by default unless disabled. |
| Q7 | Is routing Claude subscription credentials from OpenCode through this plugin permitted by current Anthropic documentation? | No documented permission was found. Current Anthropic guidance explicitly prohibits third-party developers from routing requests through Free, Pro, or Max credentials and reserves subscription OAuth for native applications and unmodified Claude Code. |
| Q8 | What supported paths remain available? | Anthropic API-key authentication is the documented third-party integration path. Unmodified Claude Code may use the end user's subscription credentials. Written Anthropic authorization could alter the policy conclusion but is not currently available. |

## Admission

- Capability declaration: `{"schemaName":"gentle-ai.sdd-research-capability","schemaVersion":1,"grants":["documentation","open-web"]}`
- Requested source classes: `documentation`, `open-web`
- Observed grants: `documentation`, `open-web`
- Denied classes: none
- Admission result: admitted for exactly the requested source classes
- Prohibited access retained: no Keychain contents, credential files, live sessions, secrets, tokens, or environment values were inspected

## Sources

### S01 — npm package metadata for `1.6.1`

- Class: `open-web`
- Publisher: npm
- URL: https://registry.npmjs.org/opencode-anthropic-login-via-cli/1.6.1
- Accessed at: `2026-09-04`
- Evidence: npm publishes version `1.6.1`, tarball integrity metadata, and `gitHead` `d6ebb6e0a4813ac53248749d7cc5384da2a224d0`.

### S02 — Pinned plugin commit and repository package metadata

- Class: `open-web`
- Publisher: plugin maintainer / GitHub
- URLs:
  - https://api.github.com/repos/cemalturkcan/opencode-anthropic-login-via-cli/commits/d6ebb6e0a4813ac53248749d7cc5384da2a224d0
  - https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/package.json
- Accessed at: `2026-09-04`
- Evidence: the verified commit is dated `2026-04-22`; the repository `package.json` at that commit says `1.4.0`, despite npm associating the commit with published version `1.6.1`.

### S03 — Plugin documentation

- Class: `documentation`
- Publisher: plugin maintainer
- URL: https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/README.md
- Accessed at: `2026-09-04`
- Evidence: the plugin reads the main Claude credential from macOS Keychain or `~/.claude/.credentials.json`, discovers CCS instances below `~/.ccs/instances/`, patches requests, and describes contexts as Connect Provider authentication methods. It documents no persistent context selector.

### S04 — Plugin initialization and auth methods

- Class: `open-web`
- Publisher: plugin maintainer
- URL: https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/index.ts
- Accessed at: `2026-09-04`
- Evidence: initialization starts Claude binary introspection and CCS discovery. Main and CCS credentials become authentication methods; their callbacks return OAuth material to OpenCode. The Anthropic loader returns an empty API key and a custom fetch function backed by OpenCode's dynamic auth getter.

### S05 — Plugin credential discovery

- Class: `open-web`
- Publisher: plugin maintainer
- URL: https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/credentials.ts
- Accessed at: `2026-09-04`
- Evidence: macOS uses `security find-generic-password` for the fixed `Claude Code-credentials` service; Linux and Windows use a fixed home-relative credential file; CCS directories are discovered and sorted by last use. Alternate selection searches the main credential and discovered CCS snapshots. No external selector constrains the search.

### S06 — Plugin fetch, refresh, and fallback

- Class: `open-web`
- Publisher: plugin maintainer
- URL: https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/fetch.ts
- Accessed at: `2026-09-04`
- Evidence: every request rereads OpenCode auth, refresh writes rotated OAuth material through `client.auth.set`, and selected `401`/`429`/`529` failures can choose another discovered credential, persist it as `anthropic`, and retry. Process-global refresh state coordinates only within one plugin process.

### S07 — Plugin request transformation

- Class: `open-web`
- Publisher: plugin maintainer
- URLs:
  - https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/transforms.ts
  - https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/cch.ts
- Accessed at: `2026-09-04`
- Evidence: the plugin removes OpenCode identity and links, prepends Claude Agent SDK identity, prefixes tool names to resemble Claude Code, inserts Claude Code billing metadata, and rewrites a prompt phrase documented in source as an Anthropic third-party classifier fingerprint.

### S08 — Plugin introspection and logging

- Class: `open-web`
- Publisher: plugin maintainer
- URLs:
  - https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/introspection.ts
  - https://github.com/cemalturkcan/opencode-anthropic-login-via-cli/blob/d6ebb6e0a4813ac53248749d7cc5384da2a224d0/src/logger.ts
- Accessed at: `2026-09-04`
- Evidence: startup executes the Claude CLI and local inspection commands, scans the Claude binary for headers/scopes, and asynchronously queries npm for the latest Claude CLI version. Debug logging is on unless `CLAUDE_AUTH_DEBUG=0`; values matching the plugin's redaction rules are replaced before file output.

### S09 — OpenCode `v1.18.27` immutable tag

- Class: `open-web`
- Publisher: OpenCode maintainers / GitHub
- URLs:
  - https://api.github.com/repos/anomalyco/opencode/git/ref/tags/v1.18.27
  - https://api.github.com/repos/anomalyco/opencode/commits/4b7e19e315cca414121ba1d61523fef74bb3ae8b
- Accessed at: `2026-09-04`
- Evidence: tag `v1.18.27` resolves to release commit `4b7e19e315cca414121ba1d61523fef74bb3ae8b`; `b04697366f05419e9bd7a92f841813dd976161c9` is its parent, not the release tag target.

### S10 — OpenCode auth persistence

- Class: `open-web`
- Publisher: OpenCode maintainers
- URL: https://github.com/anomalyco/opencode/blob/4b7e19e315cca414121ba1d61523fef74bb3ae8b/packages/opencode/src/auth/index.ts
- Accessed at: `2026-09-04`
- Evidence: OpenCode stores authentication at `Global.Path.data/auth.json`, keyed by provider. OAuth records contain access and refresh secrets plus expiration and optional account metadata; file writes use mode `0600`.

### S11 — OpenCode provider auth-loader invocation

- Class: `open-web`
- Publisher: OpenCode maintainers
- URL: https://github.com/anomalyco/opencode/blob/4b7e19e315cca414121ba1d61523fef74bb3ae8b/packages/opencode/src/provider/provider.ts
- Accessed at: `2026-09-04`
- Evidence: when provider auth exists, OpenCode invokes matching plugin auth loaders with a getter backed by current provider auth and merges returned provider options. This permits the plugin's fetch wrapper to observe later OpenCode auth changes.

### S12 — Anthropic Claude Code legal and compliance guidance

- Class: `documentation`
- Publisher: Anthropic
- URL: https://code.claude.com/docs/en/legal-and-compliance
- Accessed at: `2026-09-04`
- Evidence: OAuth is intended for subscription purchasers using Claude Code and other native Anthropic applications. Third-party developers must use API-key authentication and may not route requests through Free, Pro, or Max credentials. End users may sign in with subscriptions to the unmodified Claude Code binary. Anthropic reserves enforcement rights without notice.

### S13 — Anthropic Consumer Terms

- Class: `documentation`
- Publisher: Anthropic
- URL: https://www.anthropic.com/legal/consumer-terms
- Effective: `2025-10-08`
- Accessed at: `2026-09-04`
- Evidence: except through an Anthropic API key or where explicitly permitted, automated or non-human access is prohibited; bypassing protective measures is also prohibited.

### S14 — Anthropic Commercial Terms

- Class: `documentation`
- Publisher: Anthropic
- URL: https://www.anthropic.com/legal/commercial-terms
- Effective: `2025-06-17`
- Accessed at: `2026-09-04`
- Evidence: commercial customers may use supported services to power products, but may not reverse engineer or duplicate the services and remain subject to service-specific terms and usage policies. This does not override the Claude Code authentication restriction in S12.

## Validated Claims

| ID | Claim | Sources |
| --- | --- | --- |
| C01 | npm version `1.6.1` identifies pinned commit `d6ebb6e0a4813ac53248749d7cc5384da2a224d0`, while that commit's repository package manifest says `1.4.0`; the mismatch must remain visible in supply-chain records. | S01, S02 |
| C02 | The plugin discovers the main Claude context and CCS contexts, but exposes them as OpenCode enrollment methods rather than a persistent runtime selector. | S03, S04, S05 |
| C03 | OpenCode maintains one auth record per provider ID. A successful plugin enrollment becomes the current `anthropic` OAuth record, not one member of a simultaneously selectable profile collection. | S04, S10, S11 |
| C04 | AI Control cannot switch stock plugin `1.6.1` by changing only a stable non-secret selector because neither plugin initialization nor request handling consumes such a selector. | S04, S05, S06 |
| C05 | Directly replacing OpenCode's `anthropic` record would require access/refresh material and would violate the credential-blind AI Control boundary. | S06, S10 |
| C06 | The pinned plugin does not preserve strict identity selection: refresh fallback and selected `401`/`429`/`529` recovery can persist and retry with another discovered identity. | S05, S06 |
| C07 | Identity-correct usage attribution is not supportable while fallback may change the account and the plugin emits no stable selected-account metadata contract. | S05, S06 |
| C08 | The plugin's trust boundary includes credential-store reads, process execution, binary inspection, network update checks, OAuth mutation, request/response transformation, and debug-file output. | S05, S06, S07, S08 |
| C09 | The plugin deliberately removes OpenCode identity and rewrites request fingerprints, tool names, and billing metadata so requests resemble Claude Code traffic. | S07 |
| C10 | Anthropic's current published guidance prohibits third-party developers from routing requests through Free, Pro, or Max credentials and limits subscription use to native applications or the unmodified Claude Code binary. | S12, S13 |
| C11 | The requested OpenCode-plugin subscription architecture conflicts with C10 because it is a third-party OpenCode integration that transforms requests to emulate Claude Code rather than running the unmodified Claude Code binary. | S07, S12, S13 |
| C12 | Anthropic API-key authentication is the documented supported route for third-party products; unmodified Claude Code is the documented subscription route for end users. | S12, S14 |
| C13 | Research is complete and auditable, but proposal readiness is false because a policy conflict and missing selector primitive invalidate the selected approach. | S01-S14 |

## Contradictions

- The earlier pre-proposal state allowed a kill-gated fork or adapter around this plugin. Current Anthropic guidance is stricter: a technically successful selector does not resolve the prohibition on third-party routing of subscription credentials.
- The plugin README says it lets OpenCode use Claude Pro/Max subscriptions, while Anthropic's authoritative legal/compliance documentation says third-party developers may not route requests through those credentials.
- The plugin presents main and CCS contexts separately during provider connection, but runtime state collapses to one OpenCode `anthropic` auth record and may later switch automatically.
- The plugin description says it talks to Anthropic the same way Claude Code does. Source shows this is achieved by rewriting client identity and classifier-visible request details, not by executing an unmodified Claude Code binary.
- Prior context sometimes identified OpenCode commit `b04697366f05419e9bd7a92f841813dd976161c9` as version `1.18.27`. The immutable tag actually resolves to release commit `4b7e19e315cca414121ba1d61523fef74bb3ae8b`; the former is its parent.

## Uncertainty and Freshness

- Anthropic's legal and compliance page can change without versioned source control. The policy conclusion is current as accessed on `2026-09-04`; it must be refreshed before any later architecture decision.
- This research is technical and policy evidence, not legal advice. Written Anthropic authorization or counsel-confirmed contractual terms could change the permitted-use conclusion.
- Plugin behavior is limited to npm `1.6.1` as associated with commit `d6ebb6e0a4813ac53248749d7cc5384da2a224d0`. The npm/repository version mismatch prevents treating the repository manifest alone as publication proof.
- Source review did not execute the plugin or inspect local credentials. Runtime behavior must not be claimed beyond the reviewed control flow.
- A minimal selector extension appears technically possible, but it was not designed or validated because the policy gate fails first. Technical feasibility does not imply authorization.

## Non-Authoritative Product Choices

- Prefer Anthropic API-key authentication for OpenCode. Tradeoff: it follows the documented third-party path but uses API billing rather than Pro/Max subscription allowance.
- Use unmodified Claude Code for subscription-backed work. Tradeoff: it preserves the documented subscription boundary but does not satisfy the requirement to use ordinary OpenCode with the same sessions and plugin surface.
- Request written authorization from Anthropic for the OpenCode integration. Tradeoff: it could preserve the intended product experience, but timing and approval are uncertain and implementation must remain blocked meanwhile.
- Keep OpenAI deferred. No Claude policy conclusion should be generalized to OpenAI's distinct authentication contract.

## Readiness

- Evidence outcome: `done`
- Unsupported claims admitted as facts: none
- Proposal ready: `false`
- Production ready: `false`
- Blocking reasons:
  - Anthropic's current guidance prohibits the selected third-party subscription-credential routing architecture.
  - Stock plugin `1.6.1` has no stable non-secret context selector.
  - Plugin fallback can silently change the selected billing identity.
  - Stable identity-aligned usage attribution is unavailable.
- Next recommended: orchestrator-owned `sdd-explore` to select a supported product boundary or record written Anthropic authorization
