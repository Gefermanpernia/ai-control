# Provider Usage Identity Specification

## Purpose

Present provider-supported usage metadata only when it is safely attributable to a registered non-secret account identity.

## Requirements

### Requirement: Verified Provider Usage Attribution

The system MUST accept usage metadata only from a provider-supported surface and only when a verified non-secret stable provider account identifier matches the registered account. It MUST NOT inspect credentials or infer identity or usage from labels.

#### Scenario: Present verified usage
- GIVEN provider-supported metadata includes a verified identifier matching the selected account
- WHEN usage is displayed
- THEN the metadata is attributed to that account

#### Scenario: Reject label-based attribution
- GIVEN metadata has only a display label or an unmatched identifier
- WHEN usage is evaluated
- THEN it is not attributed as that account's usage

### Requirement: Freshness and Degradation States

The system MUST represent usage as `available`, `unavailable`, `stale`, `aggregate-only`, or `unverified identity`, with explicit freshness for `available` data. It MUST NOT present unavailable, stale, aggregate-only, or unverified-identity data as current or precise per-account usage.

#### Scenario: Display current verified metadata
- GIVEN matching metadata is within its declared freshness boundary
- WHEN usage is displayed
- THEN its state is `available` with freshness information

#### Scenario: Degrade uncertain metadata
- GIVEN metadata is missing, expired, aggregate-only, or lacks verified identity
- WHEN usage is displayed
- THEN the corresponding degraded state is shown without false precision

### Requirement: Independent Usage Gate

The usage capability MUST remain disabled until the usage-identity gate passes. Its gate MUST be independent of account-selection gating; selection MAY remain available only when its own gates pass.

#### Scenario: Block unverified usage independently
- GIVEN the usage-identity gate has not passed and selection gates have passed
- WHEN the user requests usage
- THEN usage remains disabled while selection eligibility is unchanged
