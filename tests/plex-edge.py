#!/usr/bin/env python3
"""Offline Helm/SOPS and mocked firewall checks; never connects to Kubernetes."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
EDGE = ROOT / 'flux/networking/traefik-plex'
parser = argparse.ArgumentParser()
parser.add_argument('--chart', type=Path, required=True, help='Unpacked official Traefik 42.3.1 chart')
args = parser.parse_args()


def decrypt(path):
    result = subprocess.run(['sops', '--decrypt', str(path)], check=True, text=True, capture_output=True)
    return list(yaml.safe_load_all(result.stdout))


class PlexEdgeTests(unittest.TestCase):
    def test_helm_isolation(self):
        hr = yaml.safe_load((EDGE / 'helmrelease.yaml').read_text())
        with tempfile.TemporaryDirectory() as directory:
            values = Path(directory) / 'values.yaml'
            values.write_text(yaml.safe_dump(hr['spec']['values']))
            result = subprocess.run(['helm', 'template', 'traefik-plex', str(args.chart), '--namespace', 'traefik-plex', '--skip-crds', '-f', str(values)], check=True, text=True, capture_output=True)
        resources = [d for d in yaml.safe_load_all(result.stdout) if d]
        self.assertTrue(all(d['metadata'].get('namespace') == 'traefik-plex' for d in resources))
        self.assertFalse({'ClusterRole', 'ClusterRoleBinding', 'IngressClass', 'Gateway', 'GatewayClass', 'Service'} & {d['kind'] for d in resources})
        deployment = next(d for d in resources if d['kind'] == 'Deployment')
        self.assertEqual(deployment['spec']['replicas'], 1)
        self.assertEqual(deployment['spec']['strategy']['type'], 'Recreate')
        pod = deployment['spec']['template']['spec']
        main = pod['containers'][0]
        self.assertEqual(main['securityContext']['capabilities'], {'drop': ['ALL']})
        self.assertNotIn('wireguard-key', [m['name'] for m in main['volumeMounts']])
        self.assertEqual(pod['initContainers'][0]['securityContext']['capabilities'], {'drop': ['ALL'], 'add': ['NET_ADMIN']})
        arguments = [a.lower() for a in main['args']]
        self.assertIn('--entrypoints.websecure.address=10.10.0.2:8443/tcp', arguments)
        self.assertIn('--providers.kubernetescrd.namespaces=traefik-plex', arguments)
        self.assertIn('--providers.kubernetescrd.disableclusterscoperesources=true', arguments)
        self.assertIn('--entrypoints.websecure.proxyprotocol.trustedips=10.10.0.1/32', arguments)
        self.assertIn('--experimental.abortonpluginfailure=true', arguments)
        self.assertFalse(any('kubernetesgateway' in a or 'kubernetesingress' in a or 'api.insecure' in a for a in arguments))
        services = list(yaml.safe_load_all((EDGE / 'service.yaml').read_text()))
        health = next(d for d in services if d['metadata']['name'] == 'traefik-plex-health')
        self.assertTrue(all(deployment['spec']['template']['metadata']['labels'].get(k) == v for k, v in health['spec']['selector'].items()))

    def test_encrypted_contract(self):
        secret_docs = decrypt(EDGE / 'secret.enc.yaml')
        def data(d):
            return d.get('stringData') or {k: base64.b64decode(v).decode() for k, v in d['data'].items()}
        by_name = {d['metadata']['name']: data(d) for d in secret_docs}
        crowdsec = next(d for d in decrypt(ROOT / 'flux/apps/crowdsec/secret.enc.yaml') if d['metadata']['name'] == 'crowdsec-keys')
        self.assertEqual(by_name['traefik-plex-bouncer']['BOUNCER_KEY_traefik_plex'], data(crowdsec)['BOUNCER_KEY_traefik_plex'])
        wg = by_name['traefik-plex-wireguard']
        self.assertEqual(len(base64.b64decode(wg['private-key'])), 32)
        self.assertEqual(len(base64.b64decode(wg['public-key'])), 32)
        cert = decrypt(EDGE / 'certificate.enc.yaml')[0]
        route = decrypt(EDGE / 'ingressroute.enc.yaml')[0]
        self.assertEqual(route['spec']['routes'][0]['match'], 'Host(`' + cert['spec']['dnsNames'][0] + '`)')
        self.assertNotIn('example.invalid', cert['spec']['dnsNames'][0])
        self.assertEqual(route['metadata']['annotations']['kubernetes.io/ingress.class'], 'traefik-plex')
        transport = decrypt(EDGE / 'serverstransport.enc.yaml')[0]
        old = decrypt(ROOT / 'flux/apps/plex/backendtlspolicy.enc.yaml')[0]
        self.assertEqual(transport['spec']['serverName'], old['spec']['validation']['hostname'])
        self.assertFalse(transport['spec']['insecureSkipVerify'])
        ks = yaml.safe_load((ROOT / 'flux/clusters/home/traefik-plex.yaml').read_text())
        if wg['VPS_PUBLIC_KEY'].startswith('REPLACE_') or wg['VPS_ENDPOINT'].startswith('192.0.2.'):
            self.assertTrue(ks['spec']['suspend'], 'Incomplete peer configuration must remain suspended')
        for path in EDGE.glob('*.enc.yaml'):
            raw = path.read_text()
            self.assertIn('sops:', raw)
            self.assertNotIn(cert['spec']['dnsNames'][0], raw)
            self.assertNotIn(wg['private-key'], raw)

    def run_firewall(self, endpoint, key='fixture-public-key'):
        script = yaml.safe_load((EDGE / 'configmap.yaml').read_text())['data']['setup.sh']
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            for tool in ['ip', 'wg', 'getent', 'cat', 'iptables-restore', 'ip6tables-restore']:
                code = '#!/bin/sh\n'
                if tool == 'getent':
                    code += 'case "$2" in plex-*) echo "10.97.203.150 fixture";; crowdsec-*) echo "10.104.125.29 fixture";; *) exit 1;; esac\n'
                elif tool == 'cat':
                    code += 'case "$1" in /sys/class/net/eth0/mtu) echo 1450;; *) exec /bin/cat "$@";; esac\n'
                elif tool.endswith('restore'):
                    code += f'/bin/cat > "$CHECK_DIR/{tool}.rules"\n'
                else:
                    code += 'printf "%s\\n" "$*" >> "$CHECK_DIR/mutations"\n'
                executable = scratch / tool
                executable.write_text(code)
                executable.chmod(0o700)
            env = {'PATH': str(scratch) + ':/usr/bin:/bin', 'HOME': directory, 'CHECK_DIR': directory,
                   'VPS_ENDPOINT': endpoint, 'VPS_PUBLIC_KEY': key, 'KUBERNETES_SERVICE_HOST': '10.96.0.1'}
            result = subprocess.run(['/bin/sh', '-s'], input=script, text=True, env=env, capture_output=True, timeout=10)
            rules = (scratch / 'iptables-restore.rules').read_text() if (scratch / 'iptables-restore.rules').exists() else ''
            mutations = (scratch / 'mutations').read_text() if (scratch / 'mutations').exists() else ''
            return result.returncode, rules, mutations

    def test_firewall_rules(self):
        code, rules, mutations = self.run_firewall('8.8.8.8:51820')
        self.assertEqual(code, 0)
        for chain in ['INPUT', 'OUTPUT', 'FORWARD']:
            self.assertIn(':' + chain + ' DROP', rules)
        self.assertIn('-A INPUT -i wg0 -s 10.10.0.1/32 -p tcp --dport 8443 -j ACCEPT', rules)
        self.assertIn('-A INPUT -i wg0 -j DROP', rules)
        self.assertIn('-A OUTPUT -d 10.97.203.150/32 -p tcp --dport 32400 -j ACCEPT', rules)
        self.assertLess(rules.index('-A OUTPUT -d 192.168.0.0/16 -j REJECT'), rules.index('-A OUTPUT -p tcp --dport 443 -j ACCEPT'))
        self.assertIn('allowed-ips 10.10.0.1/32', mutations)
        self.assertIn('link set wg0 mtu 1370 up', mutations)
        self.assertNotIn('0.0.0.0/0', mutations)

    def test_incomplete_or_invalid_peer_fails_before_network_changes(self):
        for endpoint, key in [('192.0.2.1:51820', 'fixture'), ('8.8.8.8:51820', 'REPLACE_WITH_KEY'), ('8.8.8.8;false:51820', 'fixture')]:
            with self.subTest(endpoint=endpoint):
                code, rules, mutations = self.run_firewall(endpoint, key)
                self.assertNotEqual(code, 0)
                self.assertEqual(rules, '')
                self.assertEqual(mutations, '')


unittest.main(argv=['plex-edge.py'])
