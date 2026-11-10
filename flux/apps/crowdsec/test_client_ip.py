"""Exercise the installed parser without sending alerts or creating decisions."""
import datetime
import json
import os
import subprocess
import sys

config = sys.argv[1] if len(sys.argv) > 1 else '/etc/crowdsec/config.yaml'
env = dict(os.environ, KUBECONFIG=os.path.expanduser('~/.kube/talos'))
pod = subprocess.check_output(
    ['kubectl', '-n', 'crowdsec-system', 'get', 'pods', '-l',
     'type=agent', '-o', 'json'], env=env, text=True)
pod = next(p['metadata']['name'] for p in json.loads(pod)['items']
           if p['status']['phase'] == 'Running')
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
cases = [
    ('10.244.0.87', '198.51.100.77', True),
    ('10.244.0.87', '2001:db8::77', True),
    ('198.51.100.88', '198.51.100.77', False),
    ('10.244.0.87', None, False),
    ('10.244.0.87', 'invalid', False),
]
for peer, header, restored in cases:
    log = dict(ClientHost=peer, ClientAddr=f'{peer}:1234', RequestAddr='example.invalid:443',
               RouterName='test@kubernetescrd', RequestMethod='GET', RequestPath='/',
               RequestProtocol='HTTP/1.1', DownstreamStatus=200, DownstreamContentSize=0,
               Duration=1000000, time=now)
    if header is not None:
        log['request_Cf-Connecting-Ip'] = header
    result = subprocess.run(
        ['kubectl', '-n', 'crowdsec-system', 'exec', '-i', pod, '-c', 'crowdsec-agent',
         '--', 'cscli', '-c', config, 'explain', '--type', 'containerd',
         '--labels', 'program:traefik', '-f', '-', '-v'],
        input=f'{now} stdout F {json.dumps(log)}\n', text=True,
        capture_output=True, env=env, check=True)
    output = result.stdout + result.stderr
    changed = f'update evt.Meta.source_ip : {peer} -> {header}' in output
    assert changed == restored, output
    assert 'crowdsecurity/traefik-logs' in output, output
    print(f'PASS peer={peer}, header={header}, restored={restored}')
