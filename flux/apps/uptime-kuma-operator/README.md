# Uptime Kuma operator

The operator runs in `extra-tools` using the public `1.2.0` image from
[uptime-kuma-operator](https://github.com/Alexxanddr/uptime-kuma-operator/releases/tag/v1.2.0).
This existing operator deliberately uses a versioned image for controlled,
validated upgrades; the old moving `latest` tag is not part of this rollout.
Keel annotations are retained for compatibility.

## Runtime

- One replica and `Recreate`; overlapping independent Socket.IO controllers are unsupported.
- Non-root UID/GID 10001, read-only root, dropped capabilities, writable `/tmp`.
- Requests 50m CPU/128Mi memory; limits 500m CPU/512Mi memory. The previous process
  used approximately 216Mi, so the generic 256Mi limit was raised for this workload count.
- Startup/liveness/readiness use port 8080 `/healthz`; process health does not
  replace monitoring of Kuma authentication/reconciliation errors.
- `service.yaml` preserves the legacy dummy port and exposes the internal health port.
- Credentials remain in the existing SOPS-encrypted Secret; values are not documented here.
- RBAC is split by Kind and grants workload get/list/watch/patch plus event create/patch.

## Ownership-safe upgrades

Keep monitor IDs/history and existing group/notification associations. Before
replacing a legacy controller, export a consistent SQLite backup and monitor
inventory outside Git. Stop the old controller declaratively, verify identities,
and migrate only unambiguous ownership markers before starting the replacement.

The 2026-10-30 upgrade used a temporary GitOps Job to migrate 78 verified ownership
markers. Its checks preserved all 89 existing monitor/group IDs and settings,
including a historical duplicate. The Job and ConfigMap were removed from the
reconciled source after completion; their history remains in Git.

Changing an existing server-side-applied Deployment from RollingUpdate to
Recreate can retain defaulted rolling fields. This rollout first explicitly
owned the existing RollingUpdate fields while pausing replicas, then removed
them when selecting Recreate. The Deployment UID was preserved.

After upgrade, compare the full original ID set, targets, groups, notifications,
intervals, active state, and unrelated monitor settings. Verify enabled workloads
report successful reconciliation and confirm the controller is Ready without
restarts. Restore ownership markers before attempting to run an old unsafe
controller; see the upstream migration guide. Never bulk-clear finalizers.

Version 1.1.2 keeps health probes asynchronous during reconciliation bursts and
excludes controller-generated state annotations from desired-state comparison.
This prevents executor starvation and status feedback loops. The normal probe
budgets are restored. Automated E2E coverage includes 64 simultaneous workloads.

## Dedicated status page

The status-page configuration targets `k8s-services` (page ID 2), titled
`Kubernetes Services`. Initial provisioning on 2026-10-30 explicitly published
82 UID-owned active monitors, preserving all 93 monitor/group configurations and
the original `k8s` page with its `Homelab` aggregate group. Publication does not
expose monitor target URLs. Page tag and certificate-expiry display are disabled;
refresh remains 300 seconds. Initial monitor order follows source weight/name/ID.

Publication is declared next to each workload's monitoring configuration with
`uptime-kuma.io/status-page: "true"`. Direct workloads use their existing metadata
or pod-template annotation location; Helm releases and Falco resources use the
same supported annotation maps as the monitoring settings. There is no monitor-ID
environment allowlist in this deployment. A recreated workload keeps its explicit
publication intent while UID ownership protects unrelated monitors.

Only the target page identity and source/public group ID mapping remain in the
operator environment. Set `status-page: "false"` or remove the annotation to opt
out. New services require an explicit publication decision; names and operational
status are public information even when target URLs are hidden. Updating Helm
pod-template annotations may restart pods; preserve the declarative annotation
contract rather than avoiding those rollouts with an ID list.

Destination groups are explicitly reserved by ID:

| Kuma source ID | Public group ID | Name |
| --- | --- | --- |
| 102 | 9 | Media & Streaming |
| 103 | 10 | Media Acquisition |
| 106 | 11 | Monitoring & Observability |
| 105 | 12 | Network & Connectivity |
| 107 | 13 | Security & Cluster |
| 104 | 14 | Storage & Databases |
| 108 | 15 | Utilities |

Require one writer for this page. Existing group/member order is preserved;
new entries append and source group renames update full-path titles. Reserve
membership/link settings of UID-owned monitors in these groups for the operator;
do not add hidden custom URLs. Manual hidden links outside that contract block
lossy saves. New or recreated public groups require explicit reviewed ID mapping.
Opt out and verify cleanup before changing page identity or removing old mappings.

Version 1.2.0 status-page writes support Kuma 2.5.8 only, preserving authenticated
page configuration including `autoRefreshInterval` and verifying save readback.
See the upstream [status-page guide](https://github.com/Alexxanddr/uptime-kuma-operator/blob/main/docs/status-pages.md)
for ownership, public data exposure and the unavoidable concurrent-save limit.
The committed configuration is desired state; verify the running image and
successful reconciliation before treating automatic synchronization as active.
