# AI Control Style Contract

## Direction: Command Ledger

**Command Ledger** is a compact, native-feeling macOS utility: the calm precision of a system inspector with the speed of a command palette. It maps the requested “clean + premium” mood to **Minimal/Swiss** structure and **Enterprise/Dense** information density. Premium comes from alignment, restrained type, and exact state feedback—not luxury typography or decoration.

The main risk is sterility or dashboard-like density. Mitigate it with short human account names, one clear active-account rail, provider-specific lettermarks, and progressive disclosure for settings.

### Niche semiotics

| Source | Translation |
|---|---|
| Terminal identity switching | A leading selection rail and `⌘` keyboard hints make “which identity is in control” legible immediately. |
| CLI status output | Tabular numerals, terse labels, reset timestamps, and explicit status words. |
| macOS menu extras | Compact popover geometry, grouped rows, native system type, hairline separators, and quiet elevation. |
| Usage limits | A narrow meter supports the text; it never becomes a chart or the only status signal. |

**Distinctive lever:** the **active command rail**—a slim indigo rail aligned with the chosen account—acts like a terminal cursor and makes the current CLI identity scannable across both providers.

## Color system

Components consume semantic aliases only. Primitive values live in the prototype token layer.

| Semantic token | Light | Dark | Purpose |
|---|---:|---:|---|
| `surface-popover` | `#F7F7F8` | `#222326` | Main popover |
| `surface-raised` | `#FFFFFF` | `#2B2D31` | Controls and selected rows |
| `surface-subtle` | `#EEEFF1` | `#303238` | Hover and grouped wells |
| `text-primary` | `#17181A` | `#F4F5F7` | Main copy |
| `text-secondary` | `#5E6268` | `#B8BCC4` | Supporting copy |
| `border-subtle` | `#D4D6DA` | `#44474F` | Dividers and outlines |
| `accent-primary` | `#4457D7` | `#AAB6FF` | Active rail, focus, selected controls |
| `accent-soft` | `#E8EBFF` | `#343A63` | Selected-row background |
| `status-positive` | `#157347` | `#7DD3A4` | Normal status |
| `status-warning` | `#8A5100` | `#FFD07A` | Near-limit status |
| `status-danger` | `#B42318` | `#FF9B92` | Unavailable/error status |

### Verified WCAG contrast pairs

Ratios use the WCAG relative-luminance formula. All body-text pairs exceed 4.5:1.

| Pair | Light ratio | Dark ratio |
|---|---:|---:|
| Primary text / popover | 16.59:1 | 14.40:1 |
| Secondary text / popover | 5.73:1 | 8.25:1 |
| Accent text / accent soft (light); accent / popover (dark) | 6.77:1 | 8.11:1 |
| Positive / popover | 5.49:1 | 8.77:1 |
| Warning / popover | 6.02:1 | 10.89:1 |
| Danger / popover | 6.14:1 | 7.75:1 |
| Text / primary action | 5.85:1 (white on `#4457D7`) | 9.17:1 (`#17181A` on `#AAB6FF`) |

Status always includes a word and symbol in addition to color.

## Typography

- **UI family:** `-apple-system`, `BlinkMacSystemFont`, `"SF Pro Text"`, sans-serif.
- **Data family:** `"SF Mono"`, `ui-monospace`, monospace for usage percentages, reset times, and keyboard hints.
- **Scale:** 11 / 12 / 13 / 15 / 17 pt.
- **Roles:**
  - App title: 15 pt, semibold.
  - Provider heading: 12 pt, semibold, sentence case.
  - Account name: 13 pt, medium.
  - Usage value: 12 pt, medium, tabular numerals.
  - Metadata and status: 11 pt, regular.
- Avoid display faces: they conflict with macOS utility conventions and slow scanning.

## Density and geometry

- **Spacing grid:** 4 pt base; working steps are 4, 8, 12, 16, 20, and 24 pt.
- **Popover:** 400 pt target width; content remains usable down to a 320 pt viewport.
- **Account row:** 60 pt minimum; enough room for two lines without becoming card-like.
- **Radius:** 6 pt controls, 9 pt grouped rows, 14 pt popover. Pills are reserved for compact status labels.
- **Elevation:** one restrained popover shadow and one inset hairline; rows use border/background changes rather than stacked shadows.
- **Borders:** 1 pt semantic hairlines.

## Motion personality

**Crisp confirmation.** State changes use a 140 ms ease-out background/rail transition. Refresh rotates the refresh glyph and gently pulses data once; no spring physics, parallax, or entrance choreography. Under `prefers-reduced-motion: reduce`, all transitions and animations stop while text feedback remains immediate.

## Interaction and state contract

- Independent radio groups select Claude CLI and Codex CLI identities.
- Switching moves the active rail and “Active” label immediately, announces the result, and offers Undo.
- Refresh exposes a textual “Refreshing…” state before restoring a timestamp.
- Unavailable accounts remain visible, explain the state, and cannot be selected.
- Settings use an in-popover back pattern and native-like segmented/toggle controls.
- Every interactive target has visible hover, active, focus-visible, and disabled states.

## Component exemplars

### Account command row

A full-width radio row uses `surface-raised` only when active, an indigo command rail on the leading edge, account name plus status text, a compact meter, and reset timing. Hover uses `surface-subtle`; focus uses a 2 pt accent ring; unavailable rows use reduced emphasis plus an explicit `! Unavailable` label. The row—not a tiny radio—is the target.

### Toolbar icon button

A 28 pt square button with a 6 pt radius and no permanent fill. Hover adds `surface-subtle`; active compresses to the darker surface token; focus-visible uses the accent ring. Refresh swaps its accessible name and spins only while active.

### Segmented appearance control

Three equal radio segments—System, Light, Dark—sit in one bordered well. The selected segment uses `surface-raised`, primary text, and a subtle inset border. Keyboard focus is visible on the segment itself; selection is not indicated by color alone.

## Do

1. Keep both provider names and active identities visible in the primary journey.
2. Use terse, specific system copy: “9% left · Resets in 42 min.”
3. Align percentages, reset times, and meters for fast comparison.
4. Pair every status color with text and, for warnings/errors, a symbol.
5. Prefer one popover depth and shallow progressive disclosure.
6. Preserve native keyboard order, focus rings, and reduced-motion behavior.

## Don’t

1. Don’t turn usage into charts, analytics cards, or KPI tiles.
2. Don’t use gradients, glass cards, glow, grain, or decorative terminal code.
3. Don’t expose, imply, or ask for raw credentials or tokens in the UI.
4. Don’t hide unavailable accounts; explain why they cannot be selected.
5. Don’t use color alone to identify the active account or a limit state.
6. Don’t add onboarding, billing, team management, or speculative destinations.

## Five-second test

The open popover must answer, without interaction: **what app is this, which Claude account is active, which Codex account is active, and whether either is near a limit or unavailable.**

## Prototype verification record

- HTML parsed successfully with Python’s standard HTML parser; inline JavaScript passed `node --check`.
- Browser-tested account switching, independent provider state, Undo, refresh feedback, settings navigation, and System/Light/Dark appearance controls.
- Inspected at a 1440 × 900 desktop viewport and a 320 × 800 emulated narrow viewport; the popover had no horizontal overflow at 320 pt.
- Chrome DevTools snapshot audit scored Accessibility 100 and Best Practices 100; keyboard semantics, disabled states, live regions, and progressbar names were present.
- Browser console was clean when served locally. No dependencies, network calls, storage, or credential data are used.
