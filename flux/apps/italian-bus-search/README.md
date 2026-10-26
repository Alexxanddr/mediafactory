# Italian Bus and Rail Search

The service runs `ghcr.io/alexxanddr/italian-travel-search:latest` in
`extra-tools` and is intentionally cluster-internal. MCPHub connects to:

```text
http://italian-bus-search.extra-tools.svc:3000/mcp
```

The retained local volume stores only the two compact timetable caches. The
init container refreshes both authorized Italian NAP distributions before the
application starts; the runtime receives only `TRENITALIA_NETEX_PATH` and
`ITALO_NETEX_PATH`. No credentials or public HTTPRoute are required.

Before the first reconciliation, create the local-volume directory on
`k3s-server`:

```sh
sudo install -d -o 1000 -g 1000 /var/lib/rancher/k3s/storage/italian-bus-search
```

Replace MCPHub's existing `italian-bus-search` stdio definition with:

```json
{
  "enabled": true,
  "owner": "admin",
  "type": "streamable-http",
  "url": "http://italian-bus-search.extra-tools.svc:3000/mcp",
  "visibility": "private",
  "enableKeepAlive": false
}
```

Verify the service and MCP transport after Flux reconciliation:

```sh
KUBECONFIG=~/.kube/k3s kubectl get pod,service,pvc -n extra-tools -l app.kubernetes.io/name=italian-bus-search
KUBECONFIG=~/.kube/k3s kubectl exec -n extra-tools deploy/mcphub -- node -e "fetch('http://italian-bus-search.extra-tools.svc:3000/health').then(async r => { console.log(r.status, await r.text()); process.exit(r.ok ? 0 : 1) })"
```

Finally reconnect the server in MCPHub and confirm that it discovers all eight
tools, then call `list_train_providers` and a real `search_train_journeys`.
