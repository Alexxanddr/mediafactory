# Pi-hole DNS pair

Two independent Helm releases provide DNS on separate Talos nodes using TCP and
UDP host port 53. Each release has its own configuration PVC and web Service.
The primary keeps its existing volume and Service names so existing integrations
continue to target it. DHCP remains on the network gateway.

The secondary uses a dedicated 2 GiB Longhorn static volume with `strict-local`
data locality and one replica. Its PV and workload select the same node, so the
secondary does not read configuration data from the primary node. This provides
application redundancy, not redundant storage for either individual instance.
The existing primary volume is preserved without a storage migration.

## Configuration synchronization

The secondary runs `ghcr.io/lovelaze/nebula-sync:latest` as a sidecar. It has no
listening port or web UI and does not require an additional Service or HTTPRoute.
The Helm release's Keel annotations cover both Pi-hole and the sync sidecar.

Synchronization runs every five minutes, from primary to secondary. Make changes
on the primary: groups, lists, domain rules, clients and their group assignments
are copied, along with local hosts, CNAME records and reverse DNS forwarding.
Gravity is rebuilt after synchronization. Runtime logs, query history, DHCP,
webserver configuration and node-specific settings are not copied. Upstream DNS
and listening mode remain configured independently by Helm.

Both instances reuse the existing SOPS-managed `pihole-credentials` Secret.
Kubernetes expands the Secret-backed password into the sidecar's endpoint
variables; credential-bearing endpoints are never stored in Git.

## Rollout and verification

Deploy the secondary and confirm successful synchronization before changing DHCP
DNS settings or restarting the primary. Advertise both node addresses only on
networks already using Pi-hole, after verifying TCP and UDP 53 are permitted to
both addresses. Clients may use either DNS server; the order is not a guaranteed
primary/standby preference. Allow existing DHCP leases to renew.

```bash
KUBECONFIG=~/.kube/talos kubectl -n pihole get pods -o wide
KUBECONFIG=~/.kube/talos kubectl -n pihole get pvc
KUBECONFIG=~/.kube/talos kubectl -n pihole logs deployment/pihole-secondary -c nebula-sync --tail=100
KUBECONFIG=~/.kube/talos kubectl -n longhorn-system get replicas.longhorn.io -o wide
```

Check that the secondary's Longhorn replica is on its workload node. From a LAN
client, query each node address using both `dig @<node-address> example.org` and
`dig +tcp @<node-address> example.org`. Compare local records and a known blocked
domain on both servers. Verify each monitor in Uptime Kuma and its `k8s` status
page; HTTP availability alone does not establish successful synchronization.

After both DNS addresses have been verified, test with the primary node down
during a maintenance window. A single control plane means existing workloads
may continue serving, but new scheduling and storage attachment require the
control plane to return. This pair does not make the Kubernetes control plane
highly available.

## Rollback

First restore DHCP to advertise only the primary address and allow leases to
renew. Suspend or remove the secondary Helm release through Git only after
clients no longer depend on it. Preserve both PVs, PVCs and Longhorn volumes;
do not delete persistent resources as part of rollback. Secondary-only UI edits
will be overwritten by the next synchronization.

## Upstream references

- [Pi-hole Helm chart](https://github.com/MoJo2600/pihole-kubernetes/tree/pihole-2.39.0/charts/pihole)
- [Nebula Sync configuration](https://github.com/lovelaze/nebula-sync)
- [Longhorn data locality](https://longhorn.io/docs/1.13.0/high-availability/data-locality/)
