# Italian Bus and Rail Search

The service runs `ghcr.io/alexxanddr/italian-travel-search:latest` in
`extra-tools` and is intentionally cluster-internal. MCPHub connects to:

```text
http://italian-travel-search.extra-tools.svc:3000/mcp
```

Stations, journey times, availability and prices come from live Trenitalia
and Italo booking APIs. No timetable download, init container, dataset
environment variables or volume mounts are needed. The existing retained
PV/PVC manifests remain for rollback; do not delete the old volume or data.
No credentials or public HTTPRoute are required.

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
KUBECONFIG=~/.kube/k3s kubectl get pod,service,pvc -n extra-tools -l app.kubernetes.io/name=italian-travel-search
KUBECONFIG=~/.kube/k3s kubectl port-forward -n extra-tools service/italian-travel-search 3099:3000
# In another local terminal:
curl --fail http://127.0.0.1:3099/health
HTTP_BASE_URL=http://127.0.0.1:3099 SMOKE_DATE=YYYY-MM-DD node scripts/live-smoke.mjs
```

Finally reconnect the server in MCPHub and confirm that it discovers all eight
tools, then call `list_train_providers` and a real `search_train_journeys`.
