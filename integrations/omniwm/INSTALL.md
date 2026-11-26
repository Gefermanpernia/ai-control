# AI Control in the OmniWM workspace bar

[OmniWM](https://omniwm.app) 0.8.0 can hide the macOS menu bar, which hides AI Control's
menu-bar item too. This integration puts AI Control in OmniWM's workspace bar instead: a
bar chip shows the selected Claude account and its usage, and its popout mirrors the AI
Control popover.

- Switch the Claude or Codex account with one click. The change shows at once and the
  row says "Working…" until `aic` finishes.
- Every usage window per account, with its reset time, email and available resets.
- Rename an account, and move it up or down in the automatic switching order.
- Settings: refresh, automatic switching for Claude and Codex, "Switch at" (50–100 %),
  refresh interval and background refresh.

Adding an account needs a browser sign-in, so it stays in the AI Control app.

## How it works

OmniWM bar widgets are Luau and cannot run programs, so the widget talks to a small bridge:

```
OmniWM widget (widgets/aic) --HTTP, bearer token--> bridge.py (127.0.0.1:47820) --argv--> aic
```

- `bridge.py` is stdlib-only Python 3.9 (`/usr/bin/python3`), started by a LaunchAgent.
  It binds 127.0.0.1 only, has no host option, checks the token in constant time, runs
  `aic` with argument lists (never a shell) and validates every request before running
  anything.
- The token lives in `~/Library/Application Support/aic-omniwm-bridge/token` (0600, folder
  0700). It is a local switch capability, not an AI provider credential. OmniWM stores
  widget options as plain text, so `shell.toml` holding it must stay private (0600).
- Account names must match `^[a-z][a-z0-9_-]{0,31}$`, the rule `aic use` and `aic rename`
  enforce for Claude and Codex. The widget shows other names without a click target; rename
  them to lowercase in the AI Control app.

### When usage is fetched

Usage calls reach Anthropic and OpenAI, so the bridge follows AI Control's own setting:

| "Refresh usage every" | Usage is fetched |
| --- | --- |
| Off | Only when you open the popout or press ↻, at most once a minute |
| On | Also on polls, once usage is older than the configured interval (minimum 5 min) |

The widget asks the bridge for status every 30 seconds. That call runs `aic status --json`
locally (about 0.1 s) and contacts no provider; it keeps the chip right when you switch
accounts elsewhere.

## Install

Requirements: macOS, AI Control at `/Applications/AI Control.app`, OmniWM 0.8.0 with the
workspace bar enabled. Run from this folder, in zsh or bash. Back up
`~/.config/omniwm/settings.toml` and any existing `~/.config/omniwm/shell/shell.toml` first.
Never edit the managed `~/.config/omniwm/shell/default/` folder.

1. Copy the bridge, the widget and the LaunchAgent:

   ```sh
   B="$HOME/Library/Application Support/aic-omniwm-bridge"
   W="$HOME/.config/omniwm/shell/widgets/aic"
   mkdir -p "$B" "$W" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
   chmod 700 "$B"
   install -m 600 bridge.py "$B/bridge.py"
   cp widgets/aic/init.luau widgets/aic/settings.toml "$W/"
   sed "s|@HOME@|$HOME|g" com.ai-control.omniwm-bridge.plist.template \
     > "$HOME/Library/LaunchAgents/com.ai-control.omniwm-bridge.plist"
   chmod 600 "$HOME/Library/LaunchAgents/com.ai-control.omniwm-bridge.plist"
   ```

2. Create the token without printing it:

   ```sh
   /usr/bin/python3 -I -c 'import runpy,pathlib; p=pathlib.Path.home()/"Library/Application Support/aic-omniwm-bridge"; runpy.run_path(str(p/"bridge.py"))["load_token"](p/"token")'
   ```

3. Place the widget in the bar. In `~/.config/omniwm/shell/shell.toml`, keep your selected
   profile and add `"aic"` to one lane of it. Arrays replace the profile's defaults, so copy
   the current lane and insert `"aic"`; for the default profile's right-hand lane:

   ```toml
   profile = "default"
   profiles.default.trailing = ["media", "notifications", "volume", "wifi", "battery-details", "control-center", "system-stats", "aic", "clock"]

   [profiles.default.widgets.aic]
   port = 47820
   token = "AIC_BRIDGE_TOKEN_PLACEHOLDER"
   ```

   If the file already has these keys, edit them in place instead of adding duplicates. Then
   write the token into the placeholder without printing it:

   ```sh
   /usr/bin/python3 -I -c 'from pathlib import Path; p=Path.home()/".config/omniwm/shell/shell.toml"; t=(Path.home()/"Library/Application Support/aic-omniwm-bridge/token").read_text().strip(); s=p.read_text(); assert s.count("AIC_BRIDGE_TOKEN_PLACEHOLDER")==1; p.write_text(s.replace("AIC_BRIDGE_TOKEN_PLACEHOLDER",t)); p.chmod(0o600)'
   ```

4. Start the bridge and check it:

   ```sh
   plutil -lint "$HOME/Library/LaunchAgents/com.ai-control.omniwm-bridge.plist"
   launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ai-control.omniwm-bridge.plist"
   curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat "$HOME/Library/Application Support/aic-omniwm-bridge/token")" http://127.0.0.1:47820/status
   ```

   Expect `200`. To use another port, change `port` in `shell.toml` and append
   `<string>--port</string><string>NEW_PORT</string>` to the plist's ProgramArguments.

5. Approve the network prompt. The widget's `settings.toml` declares `127.0.0.1`; on its
   first request OmniWM asks for consent in **Settings › Network & Permissions**. Approve it,
   then press ↻ in the popout. No `shellPermissions.programs` entry is needed.

OmniWM reloads widgets when their files or `shell.toml` change.

## Troubleshooting

- **Diagnostics:** widget lines appear in OmniWM's log:
  `log show --last 10m --predicate 'process == "OmniWM" AND eventMessage CONTAINS "aic"'`.
  A yellow marker on the chip is OmniWM's widget-error indicator; the log names the line.
- **Bridge log:** `~/Library/Logs/aic-omniwm-bridge.log` lists only method, known route and
  status, never bodies or tokens.
- **"Uppercase name — switch it in the AI Control app":** rename that account to lowercase
  in AI Control.
- **"Usage could not be loaded.":** reported by `aic` itself; the AI Control popover shows
  the same message.

## Bridge API

Every endpoint requires `Authorization: Bearer <token>`. POST bodies are JSON objects with
exactly the keys listed; anything else returns 400 without running `aic`. Absolute-form
request targets (`GET http://127.0.0.1:47820/status`) are accepted for loopback hosts only.

| Endpoint | Body | Runs |
| --- | --- | --- |
| `GET /status` | — | `aic status --json` (cached 5 s) merged with cached usage; starts a background usage refresh only when AI Control's refresh is on and usage is older than its interval |
| `GET /status?usage=1` | — | Same reply; starts a background usage refresh when usage is older than 60 s or never loaded |
| `POST /use` | `tool`, `name` | `aic [codex] use <name>` |
| `POST /rename` | `tool`, `name`, `newName` | `aic [codex] rename <name> <newName>` |
| `POST /move` | `tool`, `name`, `direction` (`up`/`down`) | `aic auto-switch move <tool> <name> <direction>` |
| `POST /settings` | `key`, `value` | `aic settings set <key> <value>`: `refresh`, `auto-switch-claude`, `auto-switch-codex`, `background-refresh` take `on`/`off`; `refresh-interval` 300–86400; `auto-switch-threshold` 50–100 |

A successful POST replies `{"ok": true, "message": "Done", "snapshot": <fresh status>}` and
never runs `--usage`; `/rename` moves cached usage to the new name. A failing fast status
returns 502.

Snapshots add `usageFetchedAtEpoch` (Unix seconds or null), `usageRefreshing`, and
`resetsAtEpoch`/`fetchedAtEpoch` next to every `resetsAt`/`fetchedAt`. One usage refresh
runs at a time. When the latest run reports an error for a login, its last good usage (up to
3600 s old) is kept with `usageStale: true` and `usageError: null`; older usage is dropped.

## Tests

- `/usr/bin/python3 -I bridge_test.py` — bridge unit tests with a fake `aic`.
- `/usr/bin/python3 -I e2e/run_e2e.py` — end-to-end run: the real widget under an OmniWM
  emulator, the real bridge, and a stateful fake `aic` that validates like the real one.
  Needs [Lune](https://lune-org.github.io/docs) (`brew install lune`) and OmniWM's managed
  look library copied to `e2e/vendor/default/lib/` (not committed; GPL-2.0, from
  `~/.config/omniwm/shell/default/lib/look.luau` and `skin.luau`).

The emulator encodes OmniWM 0.8.0 behaviour observed on a real install: HTTP JSON arrives as
readonly tables; the popout opens when `onClick` is `ui.popout` or the element has
`popout = true`, not when a handler calls `ui.popout`; and widgets must not read `ctx.data`
from timers or HTTP callbacks ("ctx.data is only readable by its own instance").

## Uninstall

```sh
launchctl bootout "gui/$(id -u)/com.ai-control.omniwm-bridge"
rm "$HOME/Library/LaunchAgents/com.ai-control.omniwm-bridge.plist"
rm -r "$HOME/.config/omniwm/shell/widgets/aic"
rm -r "$HOME/Library/Application Support/aic-omniwm-bridge"
```

Then remove `"aic"` from the lane and the `[profiles.default.widgets.aic]` table in
`shell.toml`, and reset the widget in **Settings › Network & Permissions** if you like.
