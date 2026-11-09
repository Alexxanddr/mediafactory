# Dedicated Plex ingress over WireGuard

This stack is prepared, not active. Its Flux Kustomization starts with `spec.suspend: true` until OCI is usable. No existing Plex listener, storage, GPU configuration, private HTTPRoute or main Traefik listener is removed.

```text
Plex client -> OCI HAProxy TCP/443 -> WireGuard -> 10.10.0.2:8443
                                                  |
                                           dedicated Traefik
                                                  |
                                      HTTPS Plex Service:32400
```

OCI infrastructure, HAProxy, the VPS WireGuard peer, host firewall and public DNS belong in the separate `vps-oci` repository. This repository owns only the Kubernetes half and the existing CrowdSec integration. The public hostname is encrypted in the Certificate and IngressRoute.

## Isolation

- Namespace `traefik-plex` permits the `NET_ADMIN` init container. Plex stays in `multimedia-factory`; none of its namespace security settings are widened.
- The init container creates a kernel WireGuard interface in the pod's network namespace, configures a /32 peer route, installs IPv4/IPv6 firewall rules, and exits. It does not run the image's VPN server entrypoint, install packages, load host modules or require `/dev/net/tun`. Talos must provide kernel WireGuard support; startup fails closed otherwise.
- Init retries replace an existing `wg0`, so a partially completed initialization does not permanently block recovery. The network namespace and interface survive successful init termination.
- Traefik runs as UID/GID 65532 with a read-only root filesystem, no capabilities and no privilege escalation. The WireGuard key volume is mounted only into the init container. Its service account has namespaced RBAC only; it cannot discover private routes or secrets in `system-addon` or `multimedia-factory`. Like other secrets in its own namespace, the WireGuard Secret remains readable through that namespace's provider RBAC; this is one dedicated trust boundary, not separate credentials isolation between containers.
- The HTTPS listener binds only to `10.10.0.2:8443`, with PROXY protocol trusted only from `10.10.0.1/32`. Neither an ingress Service, hostPort nor hostNetwork is enabled. Client-supplied forwarded headers are not trusted by Traefik or the CrowdSec plugin.
- Dashboard, Kubernetes Ingress and Gateway providers, GatewayClass and IngressClass creation are disabled. The CRD provider watches only `traefik-plex` and requires the `traefik-plex` route annotation. The main controller's default class filter ignores that class; verify the live provider settings at cutover.
- `plex-backend` is an `ExternalName` Service to the existing Plex ClusterIP Service. It avoids cross-namespace Kubernetes discovery permissions. The ServersTransport preserves the existing BackendTLSPolicy hostname and verifies the Plex HTTPS certificate with the system CA store; there is no `insecureSkipVerify` bypass.
- The only extra Service is `traefik-plex-health`, exposing `/ping` on 8080 for kubelet/Uptime Kuma. It does not expose the dashboard or Plex routing listener.
- One replica and `Recreate` avoid competing WireGuard peers. Pod replacement interrupts active streams; this is not high availability. Liveness verifies Traefik, not a recent WireGuard handshake; test the actual remote path separately.

## Firewall and CNI

The observed Talos CNI is Flannel without a NetworkPolicy controller. The pod-local iptables firewall is therefore the current enforcement boundary; NetworkPolicy resources alone do not provide isolation on this cluster. No cluster-wide CNI migration is included.

The init container resolves the existing Plex, LAPI and DNS ClusterIPs and reads the Kubernetes API Service address before applying the firewall. It permits only:

- incoming peer traffic to `wg0` TCP/8443;
- outer WireGuard UDP to/from the configured OCI endpoint;
- the local health listener on the ordinary pod interface;
- DNS to the configured cluster resolver;
- Plex TCP/32400, LAPI TCP/8080 and the API Service's HTTPS port;
- replies to established connections;
- public TCP/443 for Traefik's plugin loader, after rejecting private/link-local destinations.

IPv6 forwarding and non-loopback traffic in this pod are blocked. The tunnel has no default route, LAN route or IP forwarding. MTU starts at `eth0 MTU - 80`, capped at 1420; validate PMTU with real playback rather than treating this as a universal guarantee. The configuration expects a reserved public **IPv4 literal** for the OCI endpoint, avoiding DNS endpoint rotation.

Public HTTPS egress remains a deliberate allowance for loading plugin `v1.4.5` at startup; it is not a destination-specific Internet allowlist. `abortOnPluginFailure` prevents startup without the configured plugin. A prebuilt/local plugin image would be the next step if public HTTPS egress must also be eliminated.

`networkpolicy.yaml` documents the equivalent intended CNI rules and staged Plex ingress restriction. It includes the observed Service IPs and API endpoint; refresh these before introducing an enforcing CNI or after recreating Services. It preserves known internal Plex consumers (main Traefik, Homepage, Tracearr and Uptime Kuma), not arbitrary LAN/NodePort clients. It is **not enforced by current Flannel**, and it does not by itself close Plex's existing direct exposure. Do not claim Plex is isolated until the NodePort/router mapping is removed and the real paths have been checked.

The firewall caches backend ClusterIPs until pod recreation. Bump `deployment.podAnnotations.plex-edge/config-revision` whenever updating the WireGuard Secret, script or service-address assumptions; the init container does not rerun merely because a mounted Secret or ConfigMap changes.

## CrowdSec and logs

The existing LAPI receives a distinct `BOUNCER_KEY_traefik_plex` from its SOPS Secret and environment. The same key is mounted from a separate Secret into the new Traefik. Existing credentials are retained.

The existing agent acquires `traefik-plex-*` logs in namespace `traefik-plex`. Its old main-Traefik acquisition namespace is corrected to `system-addon`. Stream mode polls every 15 seconds with `updateMaxFailure: 0`: loss of decision synchronization blocks requests after the plugin observes the failure. Verify the precise startup/outage behavior during cutover. A new ban prevents subsequent HTTP requests; it need not terminate a stream that is already open.

Access logs use JSON with headers and query parameters dropped to avoid logging Plex tokens. TLS requires at least TLS 1.2 and strict SNI. CrowdSec is HTTP remediation, not protection against volumetric attacks on the VPS or home uplink.

## Complete the OCI handoff

1. Keep the Flux Kustomization suspended while configuring OCI.
2. Edit `secret.enc.yaml` with SOPS. The pod's private/public key pair is already generated and encrypted. Replace `VPS_PUBLIC_KEY` with the VPS peer's public key and `VPS_ENDPOINT` with its reserved IPv4 address plus `:51820`. Never copy the VPS private key here.
3. Read the pod's public key for the OCI peer configuration without printing the private key:

   ```sh
   sops --decrypt flux/networking/traefik-plex/secret.enc.yaml |
     python3 -c 'import sys,yaml; print(next(d for d in yaml.safe_load_all(sys.stdin) if d["metadata"]["name"] == "traefik-plex-wireguard")["stringData"]["public-key"])'
   ```

4. Configure the VPS as `10.10.0.1/32`, with the pod public key and `AllowedIPs = 10.10.0.2/32`. HAProxy must connect to `10.10.0.2:8443` in TCP mode using `send-proxy-v2`. The pod originates the tunnel with a 25-second keepalive; no inbound home router rule is required.
5. Replace both documentation-only `192.0.2.1/32` peer entries in `networkpolicy.yaml` with the real reserved public /32. Keep UDP port 51820 aligned in both repositories. Bump the config revision.
6. Create the public DNS A record in DNS-only mode. Before creating it, check whether the same hostname is already managed by `mediafactory/terraform` through the `services` map and Cloudflare Tunnel. Remove/migrate that ownership deliberately; two Terraform states must not own one DNS record. A Cloudflare Access login page must not sit in front of native Plex clients.
7. Verify infrastructure readiness: the existing Traefik CRDs, cert-manager, ClusterIssuer `letsencrypt-production`, Plex and CrowdSec. Flux depends on infrastructure/apps; the HelmRelease also depends directly on the existing Traefik, cert-manager and CrowdSec HelmReleases. The new chart skips CRD installation/upgrades. Certificate and HelmRelease readiness are checked by the dedicated Flux Kustomization.
8. Change `spec.suspend` to `false` **in Git**, commit/publish and let Flux reconcile. Do not install the release manually. Confirm the Certificate is Ready, the WireGuard handshake works and remote Plex playback succeeds before closing the old path.
9. At final cutover, change the existing Plex HelmRelease Service from `NodePort` to `ClusterIP`, remove `nodePort` and `externalTrafficPolicy`, and remove the home router TCP/32400 mapping. This is intentionally deferred until OCI is functional. Preserve the private Plex HTTPRoute and BackendTLSPolicy.
10. In Plex, configure the encrypted public hostname as `https://<public-hostname>:443` in Custom server access URLs, require secure connections after testing the actual clients, disable automatic UPnP/NAT-PMP mapping and retain account 2FA. Do not overwrite Plex's persisted Preferences file from Git while the server is running.

## Validation and acceptance

The official chart `42.3.1` rejects the `latest` image tag. This infrastructure release explicitly uses its matching `v3.7.17` image with `Always` pull policy and Keel annotations; no unsupported chart values are invented. The init image uses the official LinuxServer moving `latest` tag. Re-check chart/image/plugin compatibility during upgrades.

Local checks require Helm, SOPS, Python 3 with PyYAML, the Age key and an unpacked official chart:

```sh
python3 tests/plex-edge.py --chart /path/to/traefik-42.3.1
```

Tests render the chart, check namespace/capability/listener isolation, verify matching encrypted bouncer keys and TLS identities, and execute the firewall script with stubbed network tools and dummy inputs. They do not create interfaces, contact OCI or change iptables. These checks do not replace a real Talos startup test.

After GitOps activation, explicitly use the Talos kubeconfig for every command:

```sh
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex get helmrelease,pods,certificate
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex logs deployment/traefik-plex -c wireguard
KUBECONFIG=~/.kube/talos kubectl -n traefik-plex logs deployment/traefik-plex -c traefik
```

Verify a fresh handshake from the VPS with `wg show`, successful direct remote playback over mobile data without Plex Relay, seeking/transcoding and WebSocket behavior. Confirm the original public client IP in Traefik logs and create a short-lived CrowdSec test ban using the existing LAPI's `cscli`. Then check that subsequent requests are blocked and delete the test ban.

Attempt the private virtual-host names through the new public IP: they must not be served. Verify the VPS cannot open new tunnel connections to anything except TCP/8443, and the new proxy cannot reach other cluster/LAN services outside its explicit API/DNS/LAPI exceptions. Verify Uptime Kuma discovers the health Service in the dashboard and status page after activation. Recreate the pod and test automatic recovery. Finally scan the old home Plex port on IPv4 and IPv6 after removing its mapping.

References: [Traefik chart](https://github.com/traefik/traefik-helm-chart), [LinuxServer WireGuard image](https://github.com/linuxserver/docker-wireguard), [CrowdSec plugin](https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin/tree/v1.4.5), [WireGuard quick start](https://www.wireguard.com/quickstart/).
