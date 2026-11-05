# Shared Kubernetes VPN gateway

Flux installs the upstream chart in `vpn-gateway` after cert-manager is ready.
Only workloads in `vpn-apps` are eligible for opt-in admission. Add
`pass-to-vpn: "true"` and follow the upstream application security requirements.
Both namespaces allow the chart's network components to use `NET_ADMIN` and
`/dev/net/tun`. Limit workload creation there to trusted operators.

The gateway and its admission endpoint use internal ClusterIP Services. Uptime
Kuma checks TCP reachability of the admission Service. Kubernetes readiness and
Flux HelmRelease status track the gateway, whose overlay Service uses UDP.

The chart revision and runtime image digest are pinned. Update them together
through Git, following the upstream verification procedure. The provider profile
is stored in `secret.enc.yaml` and decrypted by Flux using SOPS. Use a distinct
WireGuard identity for any other concurrently running gateway.

See the [upstream application contract and operations guide](https://github.com/Alexxanddr/k8s-vpn-gateway#application-contract).
