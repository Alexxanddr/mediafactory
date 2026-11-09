# Dedicated Plex ingress over Tailscale

The dedicated Flux entrypoint is enabled for pod enrollment after tailnet policy/auth-key configuration. Public OCI exposure is a separate step and remains unverified until the VPS relay and end-to-end tests succeed. Existing Plex NodePort, storage, GPU and private routes are unchanged.

```text
Client -> OCI HAProxy TCP/443 -> private Tailscale TCP/8443
                                -> userspace Tailscale sidecar / TCP Serve
                                -> 127.0.0.1:8443 dedicated Traefik
                                -> HTTPS existing Plex Service:32400
```

The public hostname, TLS certificate and backend TLS identity remain SOPS-encrypted. TLS terminates on Traefik. Tailscale Serve is configured for raw TCP forwarding, without TLS termination, HTTP proxying or Funnel. Plex clients need no Tailscale installation.

## Security boundaries

- The existing main Traefik, its Gateway and private virtual hosts are separate. Both providers watch only `traefik-plex`. The Gateway provider selects its dedicated GatewayClass label and exact Gateway; the main Traefik selects only its existing class/Gateway. Namespace-local RBAC protects Secrets and application resources; the only cluster-wide access is namespace/GatewayClass metadata and the dedicated GatewayClass status.
- The Traefik listener binds only to loopback. Tailscale Serve forwards only TCP/8443. No ingress Service, hostPort or hostNetwork exposes the application on the ordinary cluster network.
- HAProxy still sends PROXY protocol v2. The Tailscale TCP forwarder preserves its bytes; Traefik trusts PROXY protocol from `127.0.0.1/32`, the local sidecar, instead of the retired WireGuard peer address. Verify the real client address end-to-end before cutover. Client forwarded headers are not trusted by the CrowdSec bouncer.
- The sidecar and Traefik run without capabilities as UID/GID 65532, with read-only root filesystems. No TUN device, kernel VPN interface, subnet routes, exit node or Tailscale SSH is configured in the pod.
- Flannel on this cluster does not enforce NetworkPolicy. A short init container therefore retains `NET_ADMIN` solely to install the pod-local firewall; it does not configure a VPN. The dedicated namespace remains privileged for this init container only. Do not remove this firewall until another mechanism really enforces egress isolation.
- The pod firewall permits only cluster DNS, API HTTPS, Plex HTTPS, CrowdSec LAPI, health endpoints, established replies and public HTTPS/UDP for Tailscale control/DERP/direct/STUN traffic and the plugin loader. Private/link-local egress is rejected after the explicit service exceptions. IPv6 non-loopback traffic is blocked. Public HTTPS/UDP is intentionally not a destination-specific Internet allowlist.
- `NetworkPolicy` remains a second declarative layer for a future enforcing CNI; review its observed ClusterIPs/API address and the ConfigMap service addresses before changing the CNI. Plex ingress policy preserves known private consumers, but is not enforced by Flannel. Close the existing direct NodePort/router path explicitly at cutover.
- `plex-backend` is an ExternalName Service to the existing Plex Service, avoiding cross-namespace API permissions. HTTPRoute uses a namespace-local TraefikService adapter because the Gateway provider does not support ExternalName backends directly. The adapter keeps the current verified Plex TLS hostname through ServersTransport and system CA trust; no insecure certificate bypass is enabled.
- Stream-mode CrowdSec uses its existing LAPI/agent and a distinct bouncer key. Query parameters and headers are dropped from JSON access logs to protect Plex tokens. Remote plugin load failure aborts startup. Strict SNI and TLS 1.2 minimum remain configured.

## Identity, state and policy

`secret.enc.yaml` contains the encrypted scoped OAuth enrollment credential and bouncer key. The initially empty `traefik-plex-state` Secret is deliberately runtime-owned: Flux uses `ssa: IfNotPresent` and `prune: Disabled` so reconciliation cannot erase Tailscale identity. Do not export its live contents into Git. Named Secret get/update/patch access is granted to the sidecar's service account. The main provider also reads namespace-local Secrets; containers in this pod share a trust boundary.

`TS_AUTH_ONCE=true` and the persisted Kubernetes state retain the device identity across pod replacement. The temporary local socket/state directory is an emptyDir; long-term state is in the Kubernetes Secret. A lost state Secret triggers automatic OAuth enrollment. Remove a stale same-hostname device deliberately before planned identity replacement to avoid a duplicate DNS name. Keep one replica and `Recreate` to avoid simultaneous consumers of one identity. Updates still interrupt active streams; this is not high availability.

The authoritative policy source is `vps-oci/tailscale/policy.json`:

- administrators own `tag:plex-vps` and `tag:plex-ingress`;
- only `tag:plex-vps` may connect to `tag:plex-ingress`, TCP/8443;
- tests deny SSH, health ports and direct Plex on the ingress node, and deny reverse access from ingress to the VPS;
- no wildcard grants, subnet advertisements or Funnel permissions.

Tailscale grants are additive. A default allow-all rule would defeat this restriction. The current empty tailnet was inspected before preparing the replacement policy; review existing users/devices again before applying a policy to a different tailnet.

## Activation

1. Store a tag-scoped OAuth enrollment credential in `TS_AUTHKEY` in this directory's SOPS Secret, with `?ephemeral=false&preauthorized=true` appended. The credential must have only `auth_keys` scope and permission to assign `tag:plex-ingress`; its creator is the tailnet administrator. The sidecar generates auth keys automatically, including after loss of runtime identity. It has no repository/module/state dependency on the VPS implementation. Keep the existing `TS_AUTH_ONCE=true` and persistent identity Secret.
2. Set `TS_AUTHKEY` in this directory's SOPS Secret, bump `plex-edge/config-revision` and publish the reviewed Git changes. The official Traefik chart rejects `latest`: its image remains `v3.7.17` with chart `42.3.1`. Tailscale uses the official `latest` image with `Always` pull policy and its own health readiness probe.
3. Unsuspend the dedicated Kustomization in Git when enrollment is ready. Flux waits for the existing infrastructure/apps; the HelmRelease depends directly on Traefik CRDs, cert-manager and CrowdSec. Certificate/HelmRelease readiness is checked before declaring the new stack ready.
4. The relay resolves this peer's stable short hostname `plex-ingress` through Tailscale DNS. No peer IP, Terraform state or generated file is shared between repositories.
5. Deploy the independent VPS implementation, enable the OCI public ingress rules and configure public DNS in DNS-only mode. The DNS record remains in the existing mediafactory Cloudflare state: `terraform/plex-remote.tf` moves the old tunnel-map address to a dedicated A record. The ignored `services` input excludes Plex. The provider replaces the old CNAME when changing type to A; perform that cutover only after testing the new endpoint, and do not create a second owner in vps-oci.
6. Require a **direct** Tailscale connection with `tailscale ping`/`tailscale status` and measure actual streaming throughput. DERP fallback can establish connectivity but is not acceptance for sustained media streaming. Userspace processing and E2 Micro bandwidth can also limit throughput.
7. Verify public TLS, correct client IP, native Plex playback over mobile data without Plex Relay, seek/transcoding and a short-lived CrowdSec ban. An active HTTP stream need not stop immediately when a new ban is added.
8. Verify that private virtual hosts, other tailnet nodes and cluster/LAN services outside the explicit exceptions cannot be reached through this ingress.
9. After successful cutover, change the existing Plex Service from NodePort to ClusterIP, remove its nodePort/externalTrafficPolicy values and remove the router's 32400 forwarding rule. Keep the private Plex HTTPRoute/BackendTLSPolicy.
10. Set Custom server access URLs to `https://<encrypted-public-hostname>:443`, test Secure connections Required on the actual clients, disable automatic UPnP/NAT-PMP mapping and retain account 2FA. Do not overwrite Plex's live Preferences file from Git.

Only the VPS exposes public ports: TCP/443 for clients and optional UDP/41641 for better direct Tailscale connectivity. No port forwarding is needed on the home router. Tailscale control traffic requires outbound HTTPS and UDP; no public DNS proxy or third-party HTTP authentication page may intercept native Plex clients.

## Validation

Run the offline checks with Helm, SOPS, Python/PyYAML and an unpacked official chart:

```sh
python3 tests/plex-edge.py --chart /path/to/traefik-42.3.1
```

Tests render the chart, verify RBAC/capabilities/listener isolation, encrypted TLS/bouncer contracts, runtime state preservation, Serve's exact TCP-only configuration and firewall rules using stubbed network tools. They do not modify real interfaces or firewalls.

After activation, use the Talos kubeconfig explicitly:

```sh
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex get helmrelease,pods,certificate
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex logs deployment/traefik-plex -c firewall
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex logs deployment/traefik-plex -c tailscale
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex exec deployment/traefik-plex -c tailscale -- tailscale --socket=/var/run/tailscale/tailscaled.sock status
```

Health probes only prove local process/enrollment readiness, not the complete public streaming path. Verify the Uptime Kuma health monitor and status-page membership after reconciliation. Restart the pod and confirm identity/route recovery before retiring the old path.

References: [Tailscale container parameters](https://tailscale.com/docs/features/containers/docker/docker-params), [Tailscale sidecar](https://tailscale.com/docs/solutions/connect-kubernetes-pods-to-tailnet-using-sidecar), [grants](https://tailscale.com/docs/reference/syntax/grants), [Traefik chart](https://github.com/traefik/traefik-helm-chart).

## Gateway API and the existing certificate manager

The existing cert-manager and `letsencrypt-production` ClusterIssuer issue the explicit `plex-remote` Certificate. The dedicated Gateway references that Secret; HTTPRoute attaches only to its HTTPS listener. No second cert-manager or issuer is installed, and the Gateway has no competing certificate-shim annotation.

The dedicated Traefik must not receive cluster-wide Secret access merely to enable Gateway API. Chart-generated RBAC is disabled; the custom Role grants namespaced reads and runtime-state updates, while a narrow ClusterRole allows GatewayClass/namespace discovery and updates only this class's status. The private controller is filtered before this new class is introduced.

## Live validation (2026-11-09)

The certificate and HelmRelease are Ready. Public DNS resolves to the OCI VPS;
HTTPS returns 200 with normal certificate validation. HAProxy PROXY v2 preserves
the real client IP. Tailscale ping confirms a direct peer connection.
Authenticated media range requests returned 206 for an 8 MiB initial range and
a 1 MiB seek range (approximately 34 and 18 Mbit/s in this short sample).
A synthetic documentation IP returned 200, then 403 after a temporary CrowdSec
decision, then 200 after removal. The dedicated bouncer polls LAPI successfully.

Stream mode checks cached decisions at request admission; it does not inspect
video chunks or require a synchronous LAPI request per segment. No captcha,
AppSec inspection or rate-limit middleware is configured on this route.
`updateMaxFailure: 0` deliberately fails closed when decision refresh fails:
new playback/seek requests may then be blocked. Existing transfers and future
segment requests have different admission points. This test does not establish
native TV/mobile compatibility, transcoding, long-duration throughput or
identity recovery after restart. Keep the old NodePort/router path until those
acceptance checks pass.
