# Subito Monitoring

Deploys [Subito Monitoring](https://github.com/Alexxanddr/subito-monitoring) through
Talos/Flux as one non-root replica with Recreate. The public image is
`ghcr.io/alexxanddr/subito-monitoring:latest`, pulled on every start. The service
is cluster-internal in `extra-tools`; no dashboard, public route or external
database is required.

## State and credentials

Longhorn Volume and PV: `subito-monitoring`, 1 GiB, V1/ext4/RWO, Retain. PVC:
`subito-monitoring-longhorn`, explicitly bound to that PV. SQLite, WAL and its
ownership lock live under `/data`. Do not share Vinted/Hermes state, scale replicas
or use NFS. One storage replica is not redundancy; Retain is not a backup.
Recurring backup labels follow the existing application convention; verify backup
completion independently.

`secret.enc.yaml` contains `SM_HTTP_TOKEN`, `SM_TELEGRAM_TOKEN` and
`SM_TELEGRAM_CHAT_ID`. Telegram uses the same administrator-approved bot and
destination as Vinted; the MCP token is independently generated. Never print
values or pass them as MCP arguments. The pod-template checksum follows the
encrypted Secret. Rotate the shared Telegram credential consistently across its
consumers. Subito only sends messages and never calls getUpdates.

`SM_UPSTREAM_ENABLED=true` enables the authorized marketplace integration. The
service uses plain curl with TLS verification and bounded requests; any new
401/403/challenge durably suspends access. Price/Market filtering is local and
coverage is bounded; health probes do not prove successful scans or delivery.
Keel and Uptime Kuma follow existing application annotations; no public status
page is enabled. Inspect authenticated monitoring_status for freshness/backlog.

## MCPHub registration

Upstream endpoint: `http://subito-monitoring.extra-tools.svc:8000/mcp`.
MCPHub uses `type: streamable-http`, private visibility/owner `admin`, and an
Authorization Bearer header containing the private `SM_HTTP_TOKEN`. The ingress
policy permits only MCPHub and Uptime Kuma in the same namespace. Egress remains
available for DNS/Subito/Telegram.

The installed MCPHub management interface supports `POST /api/servers` with
`{"name":"subito-monitoring","config":{"type":"streamable-http","url":"http://subito-monitoring.extra-tools.svc:8000/mcp","headers":{"Authorization":"Bearer <private token>"},"visibility":"private","owner":"admin"}}`.
Authenticate through the installed version's supported admin login; keep both the
admin credential and the generated JWT private. For maintenance, send a private
JSON file through its actual management endpoint without printing its content:

```sh
curl --fail --request POST "$MCPHUB_ADMIN_URL/api/servers" \
  --header "x-auth-token: $MCPHUB_ADMIN_JWT" \
  --header 'Content-Type: application/json' --data-binary @"$PRIVATE_SERVER_REQUEST"
```

This adds one server; never replace the whole catalog. Verify the supported auth
mechanism/schema against the running version before executing maintenance commands.
The live catalog, not this README, establishes actual registration.

## Acceptance and maintenance

```sh
KUBECONFIG=~/.kube/talos kubectl -n extra-tools rollout status deployment/subito-monitoring
KUBECONFIG=~/.kube/talos kubectl -n extra-tools get pvc subito-monitoring-longhorn
KUBECONFIG=~/.kube/talos kubectl get pv subito-monitoring
KUBECONFIG=~/.kube/talos kubectl -n longhorn-system get volumes.longhorn.io subito-monitoring
KUBECONFIG=~/.kube/talos kubectl -n extra-tools port-forward service/subito-monitoring 18000:8000
# Separate terminal:
curl --fail http://127.0.0.1:18000/health/ready
```

Require all eight tools through MCPHub: search_items, create_watch, list_watches,
update_watch, pause_watch, resume_watch, delete_watch, monitoring_status. First
Hermes checks are read-only list/status, then a bounded authorized search. Do not
create watches or send Telegram as connection tests. The initial baseline is
silent; pending deliveries survive edits/pause/deletion; delivery is at least once.
Back up SQLite consistently and retain the volume across upgrades.

Hermes source changes belong in `skills/hermes-skills`, followed by author-correct
commit/push, backups outside indexed skills, `hermes skills update <skill> --force`
and verification of persistent installed files. See the source project for the
complete public configuration, backup/restore and integration limits.
