# Italian Bus and Rail Search

The service runs `ghcr.io/alexxanddr/italian-travel-search:latest` in
`extra-tools`. MCP remains cluster-internal; the Binario UI is available through
an internal Gateway API route. MCPHub connects to:

```text
http://italian-travel-search.extra-tools.svc:3000/mcp
```

Stations, journey times, availability and prices come from live Trenitalia
and Italo booking APIs. No timetable download, init container, dataset
environment variables or volume mounts are needed. The existing retained
PV/PVC manifests remain for rollback; do not delete the old volume or data.
No credentials or public HTTPRoute are required.

Bus results use the requested Europe/Rome departure day and preserve
Itabus city-wide stop coverage. Actual Albatross stop names/addresses and
rail warnings for excluded urban-transfer fares are exposed through both
HTTP and MCP. Preserve these optional details in client reports.

Configure MCPHub's `italian-travel-search` server with:

```json
{
  "enabled": true,
  "owner": "admin",
  "type": "streamable-http",
  "url": "http://italian-travel-search.extra-tools.svc:3000/mcp",
  "visibility": "private",
  "enableKeepAlive": false
}
```

Verify the service and MCP transport after Flux reconciliation:

```sh
KUBECONFIG=~/.kube/talos kubectl get pod,service,pvc -n extra-tools -l app.kubernetes.io/name=italian-travel-search
KUBECONFIG=~/.kube/talos kubectl port-forward -n extra-tools service/italian-travel-search 3099:3000
# In another local terminal:
curl --fail http://127.0.0.1:3099/health
HTTP_BASE_URL=http://127.0.0.1:3099 SMOKE_DATE=YYYY-MM-DD node scripts/live-smoke.mjs
```

Finally reconnect the server in MCPHub and confirm that it discovers all eight
tools, then call `list_train_providers` and a real `search_train_journeys`.

## Unified frontend image

The existing `italian-travel-search` Deployment serves the Binario frontend,
HTTP API and MCP from one multiarch image (`linux/amd64`, `linux/arm64`) and
one Node process on port 3000. It uses `latest`, `Always` and Keel polling.
Keep one replica: snapshots and rate limits are process-local. No storage,
provider credentials, MCPHub browser credentials or additional service is needed.

## Internal browser access

The SOPS-encrypted HTTPRoute hostname uses the `binario` name in the existing
internal DNS zone. It attaches to `system-addon/traefik-gateway` and forwards
only `/`, `/index.html`, `/assets/*` and the six exact browser discovery/search
paths under `/api/` to the existing ClusterIP Service. Query strings and
snapshot parameters are preserved. `/mcp`, legacy API paths and health/status
endpoints are not routed from this hostname. No Cloudflare Tunnel or public
exposure is added. Internal DNS must resolve this hostname to the gateway,
using the same DNS/TLS setup as other internal applications.

The NetworkPolicy retains MCPHub and Uptime Kuma access and adds only Traefik
pods in `system-addon` on TCP 3000. It restricts network sources, not paths;
the HTTPRoute provides the browser path boundary. Uptime Kuma continues to
check `/health` through internal Service DNS. A healthy process does not prove
provider availability or fare validity.

## Verification and rollout

Validate the full app render with the repository's Flux dry-run command and
run the SOPS/Gitleaks hooks before publication. Reconcile through the existing
GitOps source; do not apply individual manifests directly. Check HTTPRoute
`Accepted`/`ResolvedRefs`, Deployment readiness, root HTML/assets and provider
lists through the internal gateway. Verify that `/mcp` and legacy API routes
return 404 through the browser hostname. These checks do not call providers;
real journey searches remain manual and low volume.

The backend applies a shared rate limit to connections from the gateway;
forwarded client headers are not trusted. Multiple browser users can therefore
share that budget. Existing backend timeout and error handling remain in force.

Routing follows the official [Gateway API HTTPRoute specification](https://gateway-api.sigs.k8s.io/api-types/httproute/).
