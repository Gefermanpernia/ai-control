"""Local end-to-end run: real bridge + stateful fake aic + real widget under an OmniWM emulator.

Usage: python3 -I e2e/run_e2e.py   (from aic-omniwm/). Needs `lune` on PATH and the managed
OmniWM look library copied to e2e/vendor/default/lib/{look,skin}.luau (not committed).
Exit code is the harness exit code (0 = every scenario passed).
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

STATE = {
    'claude': {'selected': 'gerardo', 'logins': [
        {'name': 'geferman', 'windows': [{'label': 'Week', 'usedPercent': 6, 'resetsAt': '2026-11-27T18:00:00Z'}]},
        {'name': 'gerardo', 'windows': [{'label': 'Week', 'usedPercent': 37, 'resetsAt': '2026-11-27T18:00:00Z'}]},
        {'name': 'prime', 'usageError': 'Usage could not be loaded.', 'windows': []},
    ]},
    'codex': {'inUse': 'gerardo', 'logins': [
        {'name': 'gerardo', 'email': 'gerardo@example.com', 'resets': 4, 'windows': [
            {'label': '5h', 'usedPercent': 0, 'resetsAt': '2026-11-26T06:38:00Z'},
            {'label': 'Week', 'usedPercent': 0, 'resetsAt': '2026-12-03T01:38:00Z'}]},
        {'name': 'prime', 'email': 'prime@example.com', 'resets': 1, 'windows': [
            {'label': 'Week', 'usedPercent': 77, 'resetsAt': '2026-11-27T23:04:00Z'}]},
        {'name': 'spare', 'email': 'spare@example.com', 'windows': [
            {'label': 'Week', 'usedPercent': 12, 'resetsAt': '2026-11-28T10:00:00Z'}]},
    ]},
    'settings': {'version': 1, 'refresh': {'enabled': False, 'intervalSeconds': 300},
                 'autoSwitch': {'claude': True, 'codex': False, 'thresholdPercent': 100, 'background': True,
                                'claudeOrder': [], 'codexOrder': []}},
}


def main():
    if not shutil.which('lune'):
        print('lune not found on PATH')
        return 2
    if not (HERE / 'vendor/default/lib/skin.luau').is_file():
        print('missing e2e/vendor/default/lib/{look,skin}.luau (copy from ~/.config/omniwm/shell/default/lib)')
        return 2
    spec = importlib.util.spec_from_file_location('bridge', ROOT / 'bridge.py')
    bridge = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bridge)
    work = Path(tempfile.mkdtemp(prefix='aic-e2e-'))
    state = work / 'state.json'
    state.write_text(json.dumps(STATE))
    log = work / 'argv.jsonl'
    log.write_text('')
    fake = work / 'aic'
    fake.write_text((HERE / 'fake_aic.py').read_text())
    fake.chmod(0o700)
    os.environ['AIC_FAKE_STATE'] = str(state)
    os.environ['AIC_FAKE_LOG'] = str(log)
    token = bridge.load_token(work / 'private' / 'token')
    server = bridge.make_server(0, token, str(fake))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ, AIC_E2E_PORT=str(server.server_port), AIC_E2E_TOKEN=token,
                   AIC_E2E_WIDGET=str(ROOT / 'widgets/aic/init.luau'), AIC_E2E_VENDOR=str(HERE / 'vendor'))
        return subprocess.run(['lune', 'run', str(HERE / 'e2e.luau')], env=env, cwd=str(work)).returncode
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    sys.exit(main())
