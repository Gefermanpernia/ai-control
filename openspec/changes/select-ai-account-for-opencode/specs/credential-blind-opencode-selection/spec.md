# Credential-Blind Selection Specification

## Requirements

### Requirement: Non-Secret Selection State

The system MUST persist only schema version, provider, stable account ID, monotonic revision, and a separate non-secret authentication-context reference; it MUST validate selection and access.

#### Scenario: Persist selection
- GIVEN an authorized registered account and a higher revision
- WHEN the user selects that account
- THEN only the permitted non-secret selection state is persisted

#### Scenario: Reject invalid state
- GIVEN malformed, unknown, unauthorized, inaccessible, partial, or non-monotonic state
- WHEN selection is read or updated
- THEN the operation fails closed with a non-secret actionable error

### Requirement: Credential-Blind Boundary

AI Control and the startup adapter MUST NOT read, copy, mutate, refresh, expose, or log credentials. Authentication remains outside both.

#### Scenario: No credential exposure
- GIVEN a supported selected identity
- WHEN a future invocation starts
- THEN neither component receives or emits credential values

#### Scenario: Reject secret input
- GIVEN selection input or an attempted path contains credential material
- WHEN either component processes it
- THEN it fails closed without persisting or logging the material

### Requirement: Shared State and Isolated Authentication

The system MUST isolate only authentication contexts. Conversations, sessions, projects, configuration, plugins, skills, Gentle AI, cache, state, logs, MCP auth, worktrees, snapshots, plans, tool output, working directory, and child-tool environment MUST remain shared and unchanged.

#### Scenario: Preserve shared experience
- GIVEN a selected account changes between launches
- WHEN each supported invocation runs
- THEN the listed state remains shared and unchanged

#### Scenario: Reject non-auth drift
- GIVEN a proposed binding changes a listed non-auth surface or child-tool environment
- WHEN support is evaluated
- THEN production selection remains disabled

### Requirement: Future Bare Invocation Binding

The system MUST affect only future verified supported bare `opencode` invocations; existing processes retain identity. A supported invocation MUST bind the selected account and transfer control, or fail closed with a non-secret actionable error. AI Control MUST NOT launch, close, restart, supervise, or proxy OpenCode.

#### Scenario: Bind future invocation
- GIVEN verified supported bare-command resolution and valid selection
- WHEN the user invokes `opencode`
- THEN OpenCode starts with the selected identity and control transfers to it

#### Scenario: Preserve process
- GIVEN OpenCode is already running under account A
- WHEN account B is selected
- THEN the running process remains bound to account A

### Requirement: Fail-Closed Support Contract

The system MUST fail closed for unknown/incompatible versions, bypass, shadowing, recursion, unresolved resolution, or unproven authentication isolation.

#### Scenario: Refuse unsupported execution
- GIVEN a bypass, shadowed adapter, recursion, or incompatible version
- WHEN an invocation is evaluated
- THEN it does not start through selection and reports the reason without secrets

### Requirement: Concurrent Identity and Claude Stability

Concurrent supported processes MAY use distinct selected identities while sharing one session history; they MUST NOT cross-switch. Claude refresh and 401, 429, or 529 recovery MUST retain the selected identity and MUST NOT automatically fall back to another account.

#### Scenario: Concurrent isolation
- GIVEN processes start with different valid selections
- WHEN both access shared session history
- THEN each retains its selected identity without changing the other

#### Scenario: Stable Claude recovery
- GIVEN a selected Claude identity receives a refresh or 401, 429, or 529 response
- WHEN recovery occurs
- THEN it remains selected or fails closed without alternate-account fallback

### Requirement: Production Gates and Rollback

Production selection MUST remain disabled until auth-boundary and Anthropic kill gates plus startup-adapter and selector-durability gates pass. Rollback MUST restore direct OpenCode resolution without touching credentials.

#### Scenario: Block before gates pass
- GIVEN any required gate is unproven or fails
- WHEN production selection is requested
- THEN it remains disabled

#### Scenario: Roll back safely
- GIVEN selection integration is enabled
- WHEN rollback is requested
- THEN direct OpenCode resolution is restored and credentials are unchanged
