# Uptime Kuma operator

The operator runs in `extra-tools` using the public `1.1.2` image from
[uptime-kuma-operator](https://github.com/Alexxanddr/uptime-kuma-operator/releases/tag/v1.1.2).
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
