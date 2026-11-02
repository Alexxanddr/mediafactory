# arr-mcp

Official image: `ghcr.io/bardesss/arr-mcp:latest`.
Streamable HTTP endpoint: `http://arr-mcp.extra-tools.svc:6060/mcp`.
Health endpoint: `/healthz`; check its JSON status because repair mode also returns 200.
The internal Gateway HTTPRoute exposes the authenticated configuration UI.

The SOPS Secret `arr-mcp` contains the bootstrap `config.yaml`, MCPHub token
(`mcp-token`), and generated UI password (`ui-password`, username `admin`).
Retrieve credentials privately through Kubernetes, never through documentation.
Set `ARR_MCP_PORT=6060` and disable Kubernetes Service links to prevent the
Service-generated `ARR_MCP_PORT` URL from overriding the numeric port.
No other environment variables are required: the image defaults to port 6060
and `ARR_MCP_CONFIG_DIR=/config`.

The init container seeds configuration only on an empty Longhorn volume.
Later UI changes, logs and write audit records persist in `/config` without
being overwritten by Flux. After provisioning, edit configuration through the
UI; changing the bootstrap Secret alone does not update the persisted file.
Storage uses a 1Gi retained volume with one replica.

Migrated services: Sonarr, Radarr, Prowlarr, Bazarr, Plex, Seerr (the previous
Overseerr configuration), and qBittorrent. Tracearr is unsupported; use its
separate integration. Read and write permissions preserve the previous Yarr
scope. Every write requires arr-mcp's preview/confirmation handshake and user
authorization for the requested operation.

## MCPHub registration and verification

Configure a private server named `arr-mcp`, owner `admin`, transport
`streamable-http`, URL `http://arr-mcp.extra-tools.svc:6060/mcp`, and header
`Authorization: Bearer <arr-mcp Secret mcp-token>`. Disable keep-alive.
Preserve all unrelated servers and settings.

Deploy through Flux:

```sh
git push origin master
KUBECONFIG=~/.kube/talos flux reconcile source git flux-system -n flux-system
KUBECONFIG=~/.kube/talos flux reconcile kustomization apps -n flux-system
KUBECONFIG=~/.kube/talos kubectl -n extra-tools rollout status deployment/arr-mcp --timeout=120s
```

From MCPHub, GET `/healthz`, initialize an authenticated MCP session, list tools
and call `stack_health`. Check every configured service, then verify the same
catalog through MCPHub before removing Yarr. Do not test writes on media files.

To create the registration through MCPHub's API, run inside its pod after
privately supplying `MCPHUB_ADMIN_TOKEN` (dashboard login JWT) and `ARR_MCP_TOKEN`
(the `arr-mcp` Secret's `mcp-token`). Values must never be pasted into commands
or documentation:

```sh
node --input-type=module <<'JS'
const response = await fetch('http://localhost:3000/api/servers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'x-auth-token': process.env.MCPHUB_ADMIN_TOKEN },
  body: JSON.stringify({ name: 'arr-mcp', config: {
    enabled: true, owner: 'admin', visibility: 'private',
    type: 'streamable-http', url: 'http://arr-mcp.extra-tools.svc:6060/mcp',
    enableKeepAlive: false,
    headers: { Authorization: 'Bearer ' + process.env.ARR_MCP_TOKEN }
  } })
});
if (!response.ok) throw new Error('MCPHub registration failed: ' + response.status);
console.log('arr-mcp registered');
JS
```

For the migration, `PUT /api/servers/yarr` with `{newName: "arr-mcp", config}`
renames the existing entry instead, preserving its identity and private owner.
MCPHub prefixes published tools, for example `arr-mcp-stack_health`.
