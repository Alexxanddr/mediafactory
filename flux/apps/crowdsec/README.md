# CrowdSec

CrowdSec reads the two Traefik containers' CRI logs and stores alerts and
community decisions in the shared PostgreSQL instance. Both Traefik bouncers
consume the LAPI decision stream. Scenario remediation flags remain upstream
defaults; detection-only scenarios do not automatically ban clients.

## Client addresses and log rotation

The private HTTPS entrypoint and its bouncer trust forwarded headers from the
Talos node's pod subnet (`10.244.0.0/24`), where the Cloudflare Tunnel connectors
run. Direct clients retain their connection IP. The bouncer uses Traefik's
sanitized `X-Forwarded-For`; do not switch it to an unsanitized custom header.

Traefik logs only `Cf-Connecting-Ip` among request headers. The local
`aa-cloudflare-client-ip` parser accepts that header only from the trusted pod
subnet, validates IPv4/IPv6, and restores `source_ip` before GeoIP enrichment
and private-address whitelisting. The dedicated Plex ingress has no trusted
forwarding proxies and uses the connection IP.

The pod subnet is a trust boundary: workloads in it must be trusted. Review all
three locations (Traefik entrypoint, middleware, parser) when changing the
cluster network or introducing untrusted workloads.

Acquisition matches only the Traefik containers, excluding sidecars, and enables
`poll_without_inotify` to follow kubelet's symlink targets across log rotation.

## Verification

```sh
KUBECONFIG=~/.kube/talos kubectl -n crowdsec-system exec deploy/crowdsec-lapi -- cscli bouncers list
KUBECONFIG=~/.kube/talos kubectl -n crowdsec-system exec deploy/crowdsec-lapi -- cscli metrics
python3 flux/apps/crowdsec/test_client_ip.py
```

The parser test uses `cscli explain` with synthetic logs; it creates no alerts or
decisions. It covers IPv4, IPv6, untrusted peers, missing headers and invalid IPs.
Validate actual blocking with a temporary decision on a reserved documentation
IP and remove it afterwards; never ban the engine's public IP for a test.

Old agent registrations with no heartbeat can remain when their heartbeat is
NULL or historical alerts still refer to them. Inspect them before removal.
Preserve the base `traefik` bouncer credential: it is used to register running
instances. The console's historical Self-Report warning can be marked solved
only after confirming there are no self-bans and client attribution is correct.

References: [file acquisition](https://docs.crowdsec.net/docs/log_processor/data_sources/file/),
[Traefik integration](https://docs.crowdsec.net/u/bouncers/traefik/).
