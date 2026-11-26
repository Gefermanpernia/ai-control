#!/usr/bin/python3
"""Stateful stand-in for AI Control's `aic` CLI used by the local e2e run.

State lives in the JSON file named by AIC_FAKE_STATE. Argument validation mirrors the
real CLI (ai-control Sources/AIControlCore): saved-login names must match
^[a-z][a-z0-9_-]{0,31}$ for `use` and `rename`, for Claude and for Codex
(CodexLogin.swift:239), even though the app itself can create other names.
Every invocation is appended to AIC_FAKE_LOG as a JSON argv list.
"""
import json
import os
import re
import sys

ALIAS = re.compile(r'\A[a-z][a-z0-9_-]{0,31}\Z')
TOGGLES = {'refresh': ('refresh', 'enabled'), 'auto-switch-claude': ('autoSwitch', 'claude'),
           'auto-switch-codex': ('autoSwitch', 'codex'), 'background-refresh': ('autoSwitch', 'background')}


def load():
    with open(os.environ['AIC_FAKE_STATE']) as stream:
        return json.load(stream)


def save(state):
    with open(os.environ['AIC_FAKE_STATE'], 'w') as stream:
        json.dump(state, stream, indent=1)


def fail(message, code=2):
    print(message)
    sys.exit(code)


def names(state, tool):
    return [login['name'] for login in state[tool]['logins']]


def status(state, usage):
    out = {'claude': {'available': True, 'installed': True, 'selected': state['claude']['selected'], 'logins': []},
           'codex': {'available': True, 'installed': True, 'inUse': state['codex']['inUse'], 'logins': []},
           'monitors': [], 'settings': state['settings'], 'version': 1}
    for tool in ('claude', 'codex'):
        for login in state[tool]['logins']:
            item = {'name': login['name'], 'usage': None, 'usageError': None}
            if tool == 'claude':
                item['needsLogin'] = False
            else:
                item['email'] = login.get('email')
            if usage:
                if login.get('usageError'):
                    item['usageError'] = login['usageError']
                else:
                    item['usage'] = {'windows': login['windows'], 'resetsAvailable': login.get('resets'),
                                     'fetchedAt': '2026-11-26T01:00:00Z'}
            out[tool]['logins'].append(item)
    return out


def rename(state, tool, old, new):
    if not (ALIAS.match(old) and ALIAS.match(new)):
        fail('Usage: AIControl claude-login save <alias> | list | use <alias> | rename <alias> <new-alias> | recover')
    if old not in names(state, tool):
        fail('No saved login named %s.' % old, 1)
    if new in names(state, tool):
        fail('A saved login named %s already exists.' % new, 1)
    for login in state[tool]['logins']:
        if login['name'] == old:
            login['name'] = new
    key = 'selected' if tool == 'claude' else 'inUse'
    if state[tool][key] == old:
        state[tool][key] = new
    order = state['settings']['autoSwitch'][tool + 'Order']
    state['settings']['autoSwitch'][tool + 'Order'] = [new if n == old else n for n in order]
    print('Renamed %s to %s.' % (old, new))


def use(state, tool, name):
    if not ALIAS.match(name):
        fail('Usage: AIControl codex-login save <alias> | list | use <alias> | rename <alias> <new-alias>')
    if name not in names(state, tool):
        fail('No saved login named %s.' % name, 1)
    state[tool]['selected' if tool == 'claude' else 'inUse'] = name
    print('Switched %s to %s.' % ('Claude' if tool == 'claude' else 'Codex', name))


def move(state, tool, name, direction):
    auto = state['settings']['autoSwitch']
    order = [n for n in auto[tool + 'Order'] if n in names(state, tool)]
    order += sorted(n for n in names(state, tool) if n not in order)
    if name not in order:
        fail('No saved login named %s.' % name, 1)
    index = order.index(name)
    other = index - 1 if direction == 'up' else index + 1
    if 0 <= other < len(order):
        order[index], order[other] = order[other], order[index]
    auto[tool + 'Order'] = order
    print('Saved.')


def settings_set(state, key, value):
    if key in TOGGLES and value in ('on', 'off'):
        group, field = TOGGLES[key]
        state['settings'][group][field] = value == 'on'
    elif key == 'refresh-interval' and value.isdigit() and int(value) >= 300:
        state['settings']['refresh']['intervalSeconds'] = int(value)
    elif key == 'auto-switch-threshold' and value.isdigit() and 50 <= int(value) <= 100:
        state['settings']['autoSwitch']['thresholdPercent'] = int(value)
    else:
        fail('Usage: aic settings [set <key> <value>]')
    print('Saved.')


def main(argv):
    with open(os.environ['AIC_FAKE_LOG'], 'a') as stream:
        stream.write(json.dumps(argv) + '\n')
    state = load()
    tool = 'claude'
    if argv[:1] == ['codex']:
        tool, argv = 'codex', argv[1:]
    if argv[:2] == ['status', '--json'] and tool == 'claude':
        print(json.dumps(status(state, '--usage' in argv[2:])))
        return
    if len(argv) == 2 and argv[0] == 'use':
        use(state, tool, argv[1])
    elif len(argv) == 3 and argv[0] == 'rename':
        rename(state, tool, argv[1], argv[2])
    elif tool == 'claude' and len(argv) == 5 and argv[:2] == ['auto-switch', 'move'] and argv[2] in ('claude', 'codex') \
            and argv[4] in ('up', 'down'):
        move(state, argv[2], argv[3], argv[4])
    elif tool == 'claude' and len(argv) == 4 and argv[:2] == ['settings', 'set']:
        settings_set(state, argv[2], argv[3])
    else:
        fail('Usage: aic ...')
    save(state)


if __name__ == '__main__':
    main(sys.argv[1:])
