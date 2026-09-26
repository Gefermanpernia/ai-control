# AI Control

Switch between your own Claude Code and OpenAI Codex CLI accounts with one click,
without signing in again.

AI Control is a small macOS menu-bar app and command-line tool. It keeps a saved
copy of each account's login and swaps the live login when you pick another
account. Logins never leave your Mac: they go into your login Keychain, and AI
Control never sends them anywhere.

> **Unofficial.** AI Control is not affiliated with or endorsed by Anthropic or
> OpenAI. It only works with accounts you own. Use it according to each
> provider's terms.

## What it does

| | Claude Code | Codex CLI |
|---|---|---|
| Switch accounts | Menu bar or `aic use <name>` | Menu bar or `aic codex use <name>` |
| Add an account without opening the CLI | Menu bar **+** or `aic login <name> [email]` | Menu bar **+** or `aic codex login <name>` |
| Rename an account | Right-click a row, or `aic rename` | Right-click a row, or `aic codex rename` |
| Usage per account | 5-hour and weekly limits | 5-hour and weekly limits, plus resets available |
| Open sessions after a switch | Keep working; no restart needed | Keep working; no restart needed |
| Saved accounts | Up to 10 | Up to 10 |

## Requirements

- macOS 13 or later on Apple silicon
- Swift 5.7+ (Xcode or the Command Line Tools)
- Claude Code installed with the native installer (`~/.local/bin/claude`)
- Codex CLI signed in with ChatGPT, storing its login in `~/.codex/auth.json`

## Install

```sh
git clone https://github.com/Gefermanpernia/ai-control.git
cd ai-control
swift build
ln -s "$PWD/scripts/aic" ~/.local/bin/aic   # any directory on your PATH works
```

`aic` runs the build in `.build/debug`, so run `swift build` again after pulling
changes. The first time AI Control touches the Keychain, macOS may ask for
permission; choose **Always Allow**.

## Usage

```sh
aic                        # open the menu-bar app
aic login work you@example.com   # sign in to a Claude account and save it as "work"
aic use work               # switch Claude Code to "work"
aic list                   # saved Claude logins
aic rename work job        # rename a saved login
aic usage                  # usage of every saved Claude and Codex login

aic codex login home       # sign in to a Codex account and save it as "home"
aic codex use home         # switch Codex to "home"
aic codex list             # saved Codex logins; the live one is marked "in use"
```

Already signed in? Save the current login with `aic save <name>` (Claude) or
`aic codex save <name>` (Codex). Names use lowercase letters, digits, `-` and `_`.

### Two rules that keep saved logins valid

1. **Never log out** with `/logout`, `claude auth logout` or `codex logout`.
   Logging out revokes the login, and its saved copy stops working.
2. **Add Codex accounts with `aic codex login`**, not `codex login`. Codex revokes
   whatever login is in `auth.json` before signing in; `aic codex login` saves it
   and moves it aside first. Claude's `claude auth login` keeps the previous
   login valid, so `aic login` simply runs it.

## How it works

**Claude Code** keeps its login in the Keychain item `Claude Code-credentials`
and the account profile in `~/.claude.json`. A switch:

- re-saves the outgoing login first, because Claude refreshes tokens in place;
- writes the target login through `/usr/bin/security`, the same tool Claude uses,
  so the item's access list never changes;
- replaces only the account-owned keys in `~/.claude.json` and leaves every other
  setting untouched;
- records each step in a journal, so an interrupted switch can be undone with
  `aic recover`.

Before touching anything, AI Control checks that the installed Claude Code stores
its login the way reviewed builds do, and refuses configuration overrides,
alternate authentication and legacy credential files.

**Codex CLI** keeps everything in `~/.codex/auth.json`. A switch re-saves the
outgoing login (Codex rotates refresh tokens), then replaces the file in one
atomic rename, only if Codex has not changed it meanwhile. Each saved login is
matched to its account from the file itself, so a login can never be saved under
the wrong name.

**Usage** is fetched only when you open the menu (at most every 30 seconds) or
press reload, from the same endpoints the CLIs use. The live account uses its
live login; other accounts use their saved login. A saved login whose access has
expired is renewed by the official CLI itself in a throwaway directory — a
temporary `CLAUDE_CONFIG_DIR` (with its own Keychain item) or `CODEX_HOME` —
with one tiny request; the rotated login is saved before the directory is
removed. Your live login and settings are never touched.

Anything uncertain — an unknown build, an unsaved live login, a concurrent
change — stops the switch before it writes anything.

## Limitations

- Development build only: unsigned, run from `.build/debug`.
- Claude Code must come from the native installer; other installs are refused.
- Codex logins stored in the Keychain instead of `auth.json` are not supported.
- AI Control proves which account a login belongs to, not that the provider will
  still accept it: a revoked login shows up the next time the CLI uses it.

## Development

```sh
./scripts/test                          # full test suite
./scripts/test --filter CodexLoginTests # one suite
```

Tests use synthetic logins and temporary directories; they never read real
credentials. Design notes and specifications live in `openspec/`.

## License

MIT. See [LICENSE](LICENSE).
