"""Deterministic loopback tests; synthetic fixtures retained in .test-run-* ."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('bridge', ROOT / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
run = Path(tempfile.mkdtemp(dir=str(ROOT), prefix='.test-run-'))
state = run / 'state.json'
log = run / 'argv.jsonl'
fake = run / 'fake-aic'
state.write_text(json.dumps({'claude': {'selected': 'a', 'logins': [{'name': 'a'}, {'name': 'b'}]}, 'codex': {'inUse': 'a', 'logins': [{'name': 'a'}, {'name': 'b'}]}, 'settings': {}}))
fake.write_text('#!' + sys.executable + '\n' + '''import json,sys
from pathlib import Path
p=Path(__file__).parent
s=json.loads((p/'state.json').read_text())
a=sys.argv[1:]
with (p/'argv.jsonl').open('a') as f: f.write(json.dumps(a)+'\\n')
if a[0]=='status':
 if s.get('fastFail') and '--usage' not in a: sys.exit(1)
 if '--usage' in a:
  if s.get('fail'): sys.exit(1)
  for tool in ('claude','codex'):
   for login in s[tool]['logins']:
    if login['name']==s.get('error'): login['usageError']='unavailable'
    else: login['usage']={'fetchedAt':0,'windows':[{'usedPercent':25,'resetsAt':0}]}
 print(json.dumps(s))
else:
 tool='codex' if a[0]=='codex' else 'claude'
 if a[0]=='codex': a=a[1:]
 if a[0]=='use': s[tool]['inUse' if tool=='codex' else 'selected']=a[1]
 if a[0]=='rename':
  for login in s[tool]['logins']:
   if login['name']==a[1]: login['name']=a[2]
 if a[0]=='auto-switch':
  rows=s[a[2]]['logins']; i=next(i for i,l in enumerate(rows) if l['name']==a[3]); j=max(0,i-1) if a[4]=='up' else min(len(rows)-1,i+1); rows[i],rows[j]=rows[j],rows[i]
 if a[0]=='settings': s['settings'][a[2]]=a[3]
 (p/'state.json').write_text(json.dumps(s))
''')
fake.chmod(0o700)
token_path = run / 'private' / 'token'
token = bridge.load_token(token_path)
assert token_path.stat().st_mode & 0o777 == 0o600
assert bridge.load_token(token_path) == token
for target, bad, good in [(token_path,0o644,0o600),(token_path.parent,0o755,0o700)]:
    target.chmod(bad)
    try:
        bridge.load_token(token_path)
        raise AssertionError('permissive token accepted')
    except ValueError:
        pass
    target.chmod(good)
now = [10000]
jobs = []
server = bridge.make_server(0, token, str(fake), clock=lambda: now[0], start_refresh=jobs.append)
assert server.server_address[0] == '127.0.0.1'
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
url = 'http://127.0.0.1:' + str(server.server_port)
def request(path, value=None, auth=token, method=None):
    req = urllib.request.Request(url+path, data=None if value is None else json.dumps(value).encode(), headers={} if auth is None else {'Authorization':'Bearer '+auth}, method=method)
    try: response = urllib.request.urlopen(req)
    except urllib.error.HTTPError as error: response = error
    return response.code, json.loads(response.read())
def calls(): return [json.loads(line) for line in log.read_text().splitlines()]
def row(snapshot): return snapshot['claude']['logins'][0]
def configure(**kw):
    s=json.loads(state.read_text()); s.update(kw); state.write_text(json.dumps(s))
try:
    assert request('/status',auth=None)[0]==401
    assert request('/status',auth='wrong')[0]==401
    snap=request('/status')[1]
    assert calls()==[['status','--json']], 'fast GET ran usage in-request'
    assert snap['usageFetchedAtEpoch'] is None and not snap['usageRefreshing'] and not jobs, 'S12: refresh off, plain GET fetched usage'
    request('/status'); assert not jobs, 'S12: refresh off, plain GET fetched usage'
    snap=request('/status?usage=1')[1]; assert len(jobs)==1 and snap['usageRefreshing'], 'popout open (?usage=1) must fetch'
    request('/status?usage=1'); assert len(jobs)==1 and len(calls())==1, 'single flight / fast cache'
    jobs.pop()()
    snap=request('/status')[1]
    assert row(snap)['usage']['windows'][0]['resetsAtEpoch']==978307200
    assert snap['usageFetchedAtEpoch']==10000 and not snap['usageRefreshing']
    now[0]+=5; request('/status'); assert calls()[-1]==['status','--json'] and len(calls())==3
    now[0]=10301; request('/status'); assert not jobs, 'S12: refresh off, periodic usage fetch'
    configure(settings={'refresh': {'enabled': True, 'intervalSeconds': 600}})
    now[0]=10600; request('/status'); assert not jobs, 'S12: refresh on, before interval (600 s)'
    now[0]+=1; request('/status'); assert len(jobs)==1, 'S12: refresh on, fetch after interval'
    jobs.pop()()
    configure(settings={})
    now[0]+=60; request('/status?usage=1'); assert not jobs, '60 boundary'
    now[0]+=1; snap=request('/status?usage=1')[1]; assert len(jobs)==1 and snap['usageRefreshing']
    configure(error='a'); jobs.pop()()
    snap=request('/status')[1]
    assert row(snap)['usageStale'] and row(snap)['usageError'] is None, 'keep good usage on login error'
    now[0]=14201; snap=request('/status')[1]  # last good usage fetched at 10601 (+3600)
    assert 'usage' in row(snap), 'keep through 3600 seconds'
    now[0]+=1; snap=request('/status')[1]
    assert not row(snap).get('usage'), 'drop after 3600 seconds'
    configure(error=None); request('/status?usage=1'); jobs.pop()()
    before=len([c for c in calls() if '--usage' in c])
    valid=[('/use',{'tool':'claude','name':'b'},['use','b']),('/use',{'tool':'codex','name':'b'},['codex','use','b']),('/rename',{'tool':'claude','name':'a','newName':'work'},['rename','a','work']),('/move',{'tool':'claude','name':'b','direction':'up'},['auto-switch','move','claude','b','up']),('/settings',{'key':'refresh','value':'on'},['settings','set','refresh','on'])]
    for path,body,argv in valid:
        code,reply=request(path,body); assert code==200 and reply['ok']
        assert calls()[-2:]==[argv,['status','--json']]
        snap=reply['snapshot']
        if path=='/use': assert snap[body['tool']]['selected' if body['tool']=='claude' else 'inUse']=='b'
        if path=='/rename': assert row(snap)['name']=='work' and row(snap)['usage']['windows']
        if path=='/move': assert row(snap)['name']=='b'
        if path=='/settings': assert snap['settings']['refresh']=='on'
    assert len([c for c in calls() if '--usage' in c])==before
    before=calls()
    invalid=[('/use',{'tool':t,'name':n}) for t,n in [('other','a'),('claude','A'),('claude','a;rm'),('codex','a'*33)]]
    invalid += [('/rename',{'tool':'claude','name':'a','newName':'a'}),('/rename',{'tool':'claude','name':'a','newName':'B'}),('/move',{'tool':'claude','name':'a','direction':'sideways'}),('/settings',{'key':'refresh-interval','value':299}),('/settings',{'key':'refresh-interval','value':'600'}),('/settings',{'key':'auto-switch-threshold','value':True}),('/settings',{'key':'auto-switch-threshold','value':101}),('/settings',{'key':'unknown','value':'on'}),('/settings',['refresh','on']),('/use',{'tool':'claude','name':'a','extra':1})]
    for path,body in invalid: assert request(path,body)[0]==400
    assert request('/use',{'tool':'claude','name':'a'*5000})[0]==400
    assert calls()==before, 'invalid request executed'
    # Keep the complete settings/management argv matrix, independent of account existence.
    for path, body, expected in [
        ('/rename', {'tool':'codex','name':'a','newName':'prime'}, ['codex','rename','a','prime']),
        ('/move', {'tool':'codex','name':'prime','direction':'down'}, ['auto-switch','move','codex','prime','down']),
        ('/settings', {'key':'refresh-interval','value':600}, ['settings','set','refresh-interval','600']),
        ('/settings', {'key':'auto-switch-threshold','value':90}, ['settings','set','auto-switch-threshold','90']),
        ('/settings', {'key':'auto-switch-claude','value':'on'}, ['settings','set','auto-switch-claude','on'])]:
        assert request(path,body)[0]==200
        assert calls()[-2:]==[expected,['status','--json']]
    for method in ('PUT','BREW'): assert request('/status',method=method)[0]==404
    assert request('/status',method='BREW',auth=None)[0]==401
    # RFC 9112 absolute-form request targets (sent by some HTTP clients) for loopback hosts only.
    import http.client
    def raw(target):
        conn = http.client.HTTPConnection('127.0.0.1', server.server_port)
        conn.request('GET', target, headers={'Authorization': 'Bearer ' + token})
        response = conn.getresponse(); body = response.read(); conn.close()
        return response.status, body
    assert raw('http://127.0.0.1:%d/status' % server.server_port)[0] == 200, 'absolute-form /status rejected'
    assert raw('http://127.0.0.1:%d/status?usage=1' % server.server_port)[0] == 200, 'absolute-form ?usage=1 rejected'
    assert raw('http://example.com/status')[0] == 404, 'non-loopback absolute-form accepted'
    assert raw('http://127.0.0.1.evil/status')[0] == 404, 'lookalike host accepted'
    assert request('/missing')[0]==404
    configure(fail=True); now[0]+=301; request('/status?usage=1'); jobs.pop()()
    snap=request('/status?usage=1')[1]; assert snap['usageRefreshing'] and row(snap).get('usage') and snap['usageFetchedAtEpoch']==14202, 'failed usage preserves cache and permits retry'
    assert len(jobs)==1; jobs.pop()()
    configure(fastFail=True); now[0]+=5; assert request('/status')[0]==502
    assert bridge.epoch('2026-11-26T01:00:00Z')==1795654800
    assert bridge.epoch(0)==978307200 and bridge.epoch(True) is None and bridge.epoch('nope') is None
    import plistlib
    template=(ROOT/'com.ai-control.omniwm-bridge.plist.template').read_text()
    assert '/Users/' not in template, 'plist template must not hard-code a home directory'
    plist=plistlib.loads(template.replace('@HOME@', '/Users/example').encode())
    assert plist['Label']=='com.ai-control.omniwm-bridge'
    assert plist['ProgramArguments']==['/usr/bin/python3', '/Users/example/Library/Application Support/aic-omniwm-bridge/bridge.py']
    assert plist['KeepAlive'] and plist['RunAtLoad']
    assert plist['StandardOutPath']==plist['StandardErrorPath']=='/Users/example/Library/Logs/aic-omniwm-bridge.log'
    result=subprocess.run([sys.executable,'-I',str(ROOT/'bridge.py'),'--host','0.0.0.0'],capture_output=True)
    assert result.returncode==2
    print('PASS: S5/S8 fast cache, usage thresholds/single-flight/merge/stale/expiry, metadata, fresh POST snapshots/rename, auth/validation/argv/loopback/token permissions/dates/502')
finally:
    server.shutdown(); server.server_close(); thread.join()
