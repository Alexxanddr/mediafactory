# Shared Kubernetes VPN gateway

Flux installs the upstream chart in `vpn-gateway` after cert-manager is ready.
Add `pass-to-vpn: "true"` to a compatible Pod or Deployment in its existing
application namespace. Admission injects the guard and the controller provisions
that namespace's transport Secret on demand. The original `vpn-apps` namespace
also remains available. Automatic enrollment excludes the gateway and system
namespaces. Namespace Pod Security enforcement and existing NetworkPolicies
still apply. The `extra-tools` namespace permits the VPN guard through its
Pod Security enforcement profile. Audit and warnings use `restricted`.
The guard accepts TCP ingress from the cluster Pod CIDR and the local kubelet
on declared container ports. This preserves ClusterIP Service access and
network probes. The guard allows underlay replies only on those connections.
Applications initiate Internet connections through the VPN.

The gateway and its admission endpoint use internal ClusterIP Services. Uptime
Kuma checks TCP reachability of the admission Service and polls Gluetun's HTTP
health endpoint on the gateway Service. The HTTP monitor reflects provider VPN
health. The client overlay uses UDP port 1194.

The chart revision and runtime image digest are pinned. Update them together
through Git, following the upstream verification procedure. The provider profile
is stored in `secret.enc.yaml` and decrypted by Flux using SOPS. Use a distinct
WireGuard identity for any other concurrently running gateway.

See the [upstream application contract and operations guide](https://github.com/Alexxanddr/k8s-vpn-gateway#application-contract).
