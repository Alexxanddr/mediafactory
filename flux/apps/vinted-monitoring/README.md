# Vinted Monitoring

This module deploys Vinted Monitoring through Talos/Flux. MCPHub is registered privately and the Hermes skills are installed.
Telegram credentials remain a separate configuration step. The service uses the public
`ghcr.io/alexxanddr/vinted-monitoring:latest` image, one replica and Recreate.
It runs as UID/GID 10001 in `extra-tools` and exposes only an internal MCP API:

```text
http://vinted-monitoring.extra-tools.svc:8000/mcp
```

## Named Longhorn storage

| Resource | Name | Configuration |
| --- | --- | --- |
| Longhorn Volume | `vinted-monitoring` | 1 GiB, V1, one replica, recurring backup group |
| PersistentVolume | `vinted-monitoring` | `longhorn-static`, ext4, RWO, Retain |
| PersistentVolumeClaim | `vinted-monitoring-longhorn` | `extra-tools`, explicitly bound to the named PV |

The CSI `volumeHandle` is `vinted-monitoring`, matching the readable Longhorn
volume name. SQLite, its WAL and its ownership lock live under `/data`.
Do not scale the workload, share this PVC or use NFS for this state. One
storage replica is not redundancy, and Retain is not a backup. The recurring
backup labels follow the existing application convention; verify actual
backup completion after deployment.

## Secret configuration

`secret.enc.yaml` contains a newly generated MCP bearer token encrypted by
SOPS. Telegram fields are intentionally empty: immediate search can run, but
creating watches is rejected until both are configured. No existing bot or
chat destination was assumed or copied.

Before enabling monitoring, edit privately:

```sh
sops flux/apps/vinted-monitoring/secret.enc.yaml
```

Set `VM_TELEGRAM_TOKEN` and `VM_TELEGRAM_CHAT_ID` together. Keep
`VM_HTTP_TOKEN` consistent with the private MCPHub Authorization header.
Never paste these values into documentation, shell history or tool calls.
After subsequent secret changes, restart the workload through the authorized
GitOps workflow because environment variables are loaded at process startup.

## MCPHub and Hermes

MCPHub has a private Streamable HTTP server named `vinted-monitoring`, using
the endpoint above and `Authorization: Bearer <VM_HTTP_TOKEN>` from its private
settings. The token was transferred in memory without printing it. On a new
installation, add this entry through the installed version's supported server
management API or UI; do not replace the other server entries.
The NetworkPolicy permits only MCPHub and Uptime Kuma ingress on port 8000,
following the other internal MCP services. There is no HTTPRoute or public
status-page enrollment. Egress is not isolated by this policy, so the service
can reach Vinted and Telegram over HTTPS.

Discover the server's eight tools after registration: `search_items`,
`create_watch`, `list_watches`, `update_watch`, `pause_watch`, `resume_watch`,
`delete_watch`, `monitoring_status`. Verify first with `list_watches` and
`monitoring_status`; a live search and a real Telegram delivery are separate,
explicitly authorized tests. Watch baselines are initially silent, query
changes reset the baseline, and existing queued messages survive edits,
pause and deletion. No price-drop alerts or reliable listing-time filter
exists.

Hermes discovery and live tool calls were verified through its existing gateway
connection: it loaded `vinted-monitoring` and the homelab reference, called
`list_watches` and `monitoring_status`, then searched once for five newest
ThinkCentre i5 listings under EUR 150. Five results were returned; no watch was
created and no Telegram message was sent. Empty watch/backlog state and a false
local request-suspension flag were observed. The flag does not describe a
Vinted account status.

The local sources in `skills/hermes-skills` and persistent installed copies
were updated through commit/push, external `/tmp` backups and `hermes skills
update <skill> --force`. The dedicated Vinted skill was installed from that
source repository; installed file hashes were verified against the sources.
For future changes, preserve that complete workflow. Keep Telegram bot and
destination configuration in SOPS; they remain intentionally empty.

## Verification after an authorized rollout

```sh
KUBECONFIG=~/.kube/talos kubectl -n extra-tools rollout status deployment/vinted-monitoring
KUBECONFIG=~/.kube/talos kubectl -n extra-tools get pvc vinted-monitoring-longhorn
KUBECONFIG=~/.kube/talos kubectl get pv vinted-monitoring
KUBECONFIG=~/.kube/talos kubectl -n longhorn-system get volumes.longhorn.io vinted-monitoring
KUBECONFIG=~/.kube/talos kubectl -n extra-tools port-forward service/vinted-monitoring 18000:8000
# In a separate terminal:
curl --fail http://127.0.0.1:18000/health/ready
```

For MCP checks use MCPHub (the NetworkPolicy may affect pod-network access;
port-forward is for local process-health diagnostics). `/health/live` checks
the HTTP process; `/health/ready` checks the polling task, not Vinted freshness
or Telegram delivery. Uptime Kuma monitors process availability. Inspect
`monitoring_status` separately for scan age, incomplete baseline, suspension,
backlog and delivery errors. No freshness alert is implied by the HTTP monitor.
