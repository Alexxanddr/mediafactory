# Dedicated public Plex ingress

```text
Public client HTTPS/443 -> home router TCP forwarding
                       -> Kubernetes node TCP/30443
                       -> dedicated Traefik TCP/8443 -> Plex HTTPS/32400
```

TLS terminates on this Traefik using the existing cert-manager Certificate and
ClusterIssuer. The dedicated Gateway, HTTPRoute, backend certificate validation
and CrowdSec stream-mode bouncer remain separate from the private Traefik.
There is no OCI relay, HAProxy, VPN sidecar, Tailscale enrollment or PROXY protocol.

## Router and DNS

Forward WAN **TCP/443** to the Kubernetes node's **TCP/30443**. The public Service
`traefik-plex-public` uses `externalTrafficPolicy: Local` to preserve source IPs;
the router must preserve them too. Forward to a node running the ingress pod.
Do not forward to the main Traefik, health port, API/dashboard or Plex port 32400.
No UDP forwarding or public HTTP/80 is required: certificates use DNS-01.

`terraform/plex-remote.tf` owns the DNS-only public CNAME to the existing `router`
hostname in the same Cloudflare zone. UniFi keeps that target updated through its
existing dynamic DNS configuration; Plex follows it automatically. No static
public-IP input or second dynamic DNS updater is needed. Terraform does not
manage the router record. Keep Plex out of the Cloudflare Tunnel `services`
map. Custom server access URLs in Plex must contain the public HTTPS URL on port
443 so native applications discover this path.

Plex uses a ClusterIP Service on TCP/32400. The router forwards WAN TCP/443
to the dedicated Traefik NodePort on TCP/30443. Plex mounts its media volume
read-only.

## Security

- Providers and application RBAC remain namespace-local. A narrow ClusterRole
  provides namespace/GatewayClass discovery and updates only this class's status.
- The main container runs as UID/GID 65532, drops all capabilities, uses a read-only
  root filesystem and RuntimeDefault seccomp, and disallows privilege escalation.
- Flannel currently does not enforce NetworkPolicy. The existing init firewall
  remains necessary; its short-lived netshoot container has only NET_ADMIN.
  The namespace remains privileged solely to admit that init container.
- The firewall permits HTTPS ingress on 8443, internal health on 8080, established
  replies, cluster DNS/API, the exact Plex and CrowdSec services, and public HTTPS
  for plugin downloads. Other private/link-local egress and non-loopback IPv6 are
  blocked. No Tailscale UDP or health/enrollment endpoints remain.
- PROXY protocol is disabled and client-supplied forwarding headers are untrusted.
  Verify the real external source address in the access log after router setup.
- The SOPS Secret contains only the dedicated CrowdSec bouncer credential.
  Namespaced Secret write privileges and the Tailscale OAuth credential are gone.
- CrowdSec refresh failures block new requests. Plugin loading fails closed;
  access logs omit query parameters and headers to avoid exposing Plex tokens.

## Validation

```sh
SOPS_AGE_KEY_FILE=/path/to/age-key python3 tests/plex-edge.py --chart /path/to/traefik-42.3.1
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex get helmrelease,pods,certificate,service
```

Test the node endpoint with the public hostname and normal TLS verification
before changing DNS. After forwarding, verify public HTTPS, source-IP preservation,
authenticated native playback, seek and a temporary CrowdSec ban/removal. A healthy
pod alone does not establish public reachability or sustained streaming capacity.

The deployment remains one replica with Recreate: upgrades interrupt streams.
The Tailscale runtime Secret was protected from pruning; remove that specific
orphan explicitly after the sidecar has stopped. Never delete the TLS or bouncer
Secrets as part of that cleanup.

## Cutover verification — 2026-11-10

Flux reconciled the direct-ingress configuration; the pod is Ready with only
Traefik and the completed firewall init container. Public HTTPS through the
home router returns 200 with a valid certificate; unauthenticated library
access returns 401. Access logs show the real external client IP. Router
configuration was read back as WAN TCP/443 to node TCP/30443.

The OCI VM, boot volume, public IP and dedicated network were removed. Both
Plex OAuth clients, devices, enrollment keys and tag/grant references were
removed from Tailscale. The old runtime Secret and state-write RBAC are gone.
Both retired relay Terraform workspaces have empty state and no-change plans;
account-wide Tailscale settings remain unmanaged without project references.

The five offline tests, Flux render, server-side Deployment/Service dry run,
SOPS and Gitleaks checks passed. Native playback and sustained streaming on
the new direct path still require user validation; no synthetic ban was added
during this cutover.
