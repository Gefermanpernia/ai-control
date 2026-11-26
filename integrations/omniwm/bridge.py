#!/usr/bin/python3
"""Loopback-only AI Control adapter. No third-party dependencies."""
import argparse
import copy
import threading
from datetime import datetime
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import time
from urllib.parse import urlsplit
from http.server import BaseHTTPRequestHandler, HTTPServer

AIC = '/Applications/AI Control.app/Contents/Resources/aic'
ALIAS = re.compile(r'[a-z][a-z0-9_-]{0,31}', re.ASCII)
TOOLS = ('claude', 'codex')
TOGGLES = ('refresh', 'auto-switch-claude', 'auto-switch-codex', 'background-refresh')
APPLE_EPOCH = 978307200  # Foundation reference date (2001-01-01) in Unix seconds


def epoch(value):
    """Return Unix seconds for an ISO-8601 string or Foundation reference-date number, else None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return int(value + APPLE_EPOCH)
    if isinstance(value, str):
        try:
            return int(datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp())
        except ValueError:
            return None
    return None


def annotate(value):
    """Add <key>Epoch next to every resetsAt/fetchedAt so the widget can format dates."""
    if isinstance(value, list):
        for item in value:
            annotate(item)
    elif isinstance(value, dict):
        for key in ('resetsAt', 'fetchedAt'):
            if key in value:
                value[key + 'Epoch'] = epoch(value[key])
        for item in list(value.values()):
            annotate(item)
    return value


def command(path, body):
    """Map a validated POST body to an aic argv list, or None when invalid."""
    if not isinstance(body, dict):
        return None
    prefix = ['codex'] if body.get('tool') == 'codex' else []
    alias = lambda key: isinstance(body.get(key), str) and ALIAS.fullmatch(body[key]) is not None
    if path == '/use' and set(body) == {'tool', 'name'} and body['tool'] in TOOLS and alias('name'):
        return prefix + ['use', body['name']]
    if (path == '/rename' and set(body) == {'tool', 'name', 'newName'} and body['tool'] in TOOLS
            and alias('name') and alias('newName') and body['name'] != body['newName']):
        return prefix + ['rename', body['name'], body['newName']]
    if (path == '/move' and set(body) == {'tool', 'name', 'direction'} and body['tool'] in TOOLS
            and alias('name') and body['direction'] in ('up', 'down')):
        return ['auto-switch', 'move', body['tool'], body['name'], body['direction']]
    if path == '/settings' and set(body) == {'key', 'value'}:
        key, value = body['key'], body['value']
        if key in TOGGLES and value in ('on', 'off'):
            return ['settings', 'set', key, value]
        if isinstance(value, int) and not isinstance(value, bool):
            if key == 'refresh-interval' and 300 <= value <= 86400:
                return ['settings', 'set', key, str(value)]
            if key == 'auto-switch-threshold' and 50 <= value <= 100:
                return ['settings', 'set', key, str(value)]
    return None


def origin_form(target):
    """Reduce an RFC 9112 absolute-form target for a loopback host to its path and query.

    Other absolute-form targets become an unknown route, so they get 404.
    """
    parts = urlsplit(target)
    if not (parts.scheme or parts.netloc):
        return target
    if parts.scheme != 'http' or parts.hostname not in ('127.0.0.1', 'localhost'):
        return '<foreign>'
    return parts.path + ('?' + parts.query if parts.query else '')


def load_token(path):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.parent.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Token directory must be owned by this user and private (0700)')
    try:
        fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, 'w') as stream:
            stream.write(secrets.token_urlsafe(32))
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('Token must be an owned regular 0600 file')
        token = stream.read(256).strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', token):
        raise ValueError('Invalid token file')
    return token


def make_server(port, token, aic=AIC, clock=time.time, start_refresh=None):
    lock = threading.RLock()
    good = {}
    errors = {}
    fetched = None
    refreshing = False
    rename_generation = 0

    def run_aic(args):
        result = subprocess.run([aic] + args, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=60, check=True)
        if len(result.stdout) > 4 * 1024 * 1024:
            raise ValueError('Output limit')
        return result.stdout

    def read_status(usage=False):
        value = json.loads(run_aic(['status', '--json'] + (['--usage'] if usage else [])))
        if not isinstance(value, dict):
            raise ValueError('Invalid snapshot')
        return annotate(value)

    def refresh():
        nonlocal fetched, refreshing
        try:
            with lock:
                generation = rename_generation
            value = read_status(True)
            with lock:
                # A concurrent rename may make this result's names obsolete.
                if generation != rename_generation:
                    return
                stamp = clock()
                for tool in TOOLS:
                    for login in value.get(tool, {}).get('logins', []):
                        key = (tool, login['name'])
                        if login.get('usage') and not login.get('usageError'):
                            good[key] = (copy.deepcopy(login['usage']), stamp)
                        errors[key] = login.get('usageError')
                fetched = stamp
        except (subprocess.SubprocessError, OSError, ValueError):
            pass  # Keep last good data; never let a usage failure break fast status.
        finally:
            with lock:
                refreshing = False

    def launch(job):
        threading.Thread(target=job, daemon=True).start()

    def periodic_threshold():
        """Seconds between usage fetches on plain polls, or None when AI Control's refresh is off."""
        settings = server.cached.get('settings') if isinstance(server.cached, dict) else None
        refresh_settings = settings.get('refresh') if isinstance(settings, dict) else None
        if not isinstance(refresh_settings, dict) or refresh_settings.get('enabled') is not True:
            return None
        interval = refresh_settings.get('intervalSeconds')
        if isinstance(interval, bool) or not isinstance(interval, int):
            interval = 300
        return max(300, interval)

    def snapshot(force=False, threshold=None):
        """threshold: 'periodic' for plain polls, a number of seconds for explicit requests."""
        nonlocal refreshing
        with lock:
            if force or clock() >= server.cache_until:
                server.cached = read_status()
                server.cache_until = clock() + 5
            if threshold == 'periodic':
                threshold = periodic_threshold()
            if threshold is not None and not refreshing and (fetched is None or clock() - fetched > threshold):
                refreshing = True
                (start_refresh or launch)(refresh)
            value = copy.deepcopy(server.cached)
            for tool in TOOLS:
                for login in value.get(tool, {}).get('logins', []):
                    key = (tool, login['name'])
                    login.pop('usage', None)
                    login.pop('usageStale', None)
                    if key in good and clock() - good[key][1] <= 3600:
                        login['usage'] = copy.deepcopy(good[key][0])
                        login['usageError'] = None
                        login['usageStale'] = bool(errors.get(key))
                    elif key in errors:
                        login['usageError'] = errors[key]
            value['usageFetchedAtEpoch'] = fetched
            value['usageRefreshing'] = refreshing
            return value

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(125)

        def __getattr__(self, name):
            if name.startswith('do_'):
                return self.handle_request
            raise AttributeError(name)

        def log_message(self, *args):
            pass

        def reply(self, code, value):
            body = json.dumps(value, allow_nan=False).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            # Do not log arbitrary paths, queries, bodies or authorization headers.
            path = '/status' if self.path == '/status?usage=1' else self.path
            route = path if path in ('/status', '/use', '/rename', '/move', '/settings') else '<unknown>'
            print(self.command, route, code, flush=True)


        def dispatch(self):
            nonlocal rename_generation
            self.path = origin_form(self.path)
            supplied = self.headers.get('Authorization', '').encode('utf-8')
            if not hmac.compare_digest(supplied, ('Bearer ' + token).encode('ascii')):
                return self.reply(401, {})
            if self.command == 'GET' and self.path in ('/status', '/status?usage=1'):
                return self.reply(200, snapshot(threshold=60 if self.path.endswith('?usage=1') else 'periodic'))
            if self.command == 'POST' and self.path in ('/use', '/rename', '/move', '/settings'):
                length = self.headers.get('Content-Length', '')
                if self.headers.get('Transfer-Encoding') or not length.isdigit() or not 0 < int(length) <= 4096:
                    return self.reply(400, {'ok': False, 'message': 'Invalid request'})
                try:
                    body = json.loads(self.rfile.read(int(length)))
                    argv = command(self.path, body)
                except (ValueError, TypeError):
                    argv = None
                if argv is None:
                    return self.reply(400, {'ok': False, 'message': 'Invalid request'})
                run_aic(argv)
                with lock:
                    if self.path == '/rename':
                        rename_generation += 1
                        old = (body['tool'], body['name'])
                        new = (body['tool'], body['newName'])
                        for cache in (good, errors):
                            if old in cache:
                                cache[new] = cache.pop(old)
                    self.server.cache_until = 0
                return self.reply(200, {'ok': True, 'message': 'Done', 'snapshot': snapshot(force=True)})
            return self.reply(404, {})

        def handle_request(self):
            self.connection.settimeout(125)
            try:
                self.dispatch()
            except (subprocess.SubprocessError, OSError, ValueError):
                self.reply(502, {'ok': False, 'message': 'AI Control unavailable'})

        do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = handle_request

    # No host argument exists: configuration cannot widen the bind address.
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.cache_until = 0
    server.cached = None
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=47820)
    parser.add_argument('--token-file', type=Path, default=Path.home() / 'Library/Application Support/aic-omniwm-bridge/token')
    # Deliberately named test-only; LaunchAgent never passes this.
    parser.add_argument('--test-aic', default=AIC, help=argparse.SUPPRESS)
    args = parser.parse_args()
    make_server(args.port, load_token(args.token_file), args.test_aic).serve_forever()


if __name__ == '__main__':
    main()
