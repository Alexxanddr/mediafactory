# PostgreSQL backups

`postgres-longhorn-daily` is a CloudNativePG `ScheduledBackup`. It requests an
online backup at 01:00 UTC every day (02:00 in Rome in winter, 03:00 in summer),
with an immediate first run. PostgreSQL remains available during the backup.

The `longhorn-backup` CSI `VolumeSnapshotClass` uses `type: bak`, so Longhorn
uploads the snapshot to its existing default NFS backup target on the media
disks. It is not merely an NVMe-local snapshot. Longhorn must have a working,
writable backup target for a run to complete. CSI CRDs are vendored from
external-snapshotter v8.6.0 under `flux/bootstrap/snapshot-api`; the controller
uses the same version as Longhorn's CSI snapshotter. Flux establishes the API
before infrastructure and waits for the snapshot controller and CNPG operator
before reconciling applications. The CNPG pod annotation triggers API discovery
after installation.

No external WAL archive is configured. `waitForArchive: false` avoids waiting
for one; recovery uses the WAL retained in the snapshot. These backups support
snapshot recovery, not arbitrary point-in-time recovery. Backup and source disks
are separate, but remain attached to the same server.

## Retention

CloudNativePG does not apply retention policies to CSI snapshots. The
`postgres-backup-retention` CronJob runs at 05:00 UTC and keeps the seven newest
**completed** backups belonging to this schedule. Failed, running, manual and
other clusters' backups are excluded. If fewer than eight backups have completed,
nothing is deleted. The service account can only list and delete CNPG Backup
objects in `database`; it cannot delete PVCs or PostgreSQL clusters.

Each snapshot is owned by its CNPG `Backup`. Deleting an expired backup cascades
to its `VolumeSnapshot`; the class's `deletionPolicy: Delete` removes the CSI
content and corresponding NFS backup. Deleting the schedule also cascades to its
backups because `backupOwnerReference: self` is set. Do not remove the schedule
as a way to pause it; use `spec.suspend: true` instead.

This retention does not delete existing Longhorn recurring/system backups or
local snapshot chains. Those require separate inspection and cleanup.

## Verification

```sh
KUBECONFIG=~/.kube/talos kubectl -n database get scheduledbackup,backup
KUBECONFIG=~/.kube/talos kubectl -n database get volumesnapshot
KUBECONFIG=~/.kube/talos kubectl get volumesnapshotcontent
KUBECONFIG=~/.kube/talos kubectl -n longhorn-system get backups.longhorn.io
KUBECONFIG=~/.kube/talos kubectl -n database get cronjob postgres-backup-retention
KUBECONFIG=~/.kube/talos kubectl -n database get jobs
python3 flux/apps/postgresql/test_retention.py
```

A successful run has CNPG phase `completed`, a CSI snapshot with
`readyToUse: true`, a content handle starting with `bak://`, and a corresponding
Longhorn backup in state `Completed`. Job existence alone is not proof of success.

## Recovery

Restore to a **new** Cluster and PVC, never overwrite the live database. Use the
CNPG snapshot recovery procedure and the selected `VolumeSnapshot` name in
`spec.bootstrap.recovery.volumeSnapshots.storage`. Preserve the snapshot's CNPG
labels and annotations: they contain the backup metadata needed for hot snapshot
recovery. If Kubernetes metadata was lost, first import the Longhorn NFS backup
as a CSI snapshot and recover its CNPG backup metadata from the saved manifests.
The NFS backup alone does not preserve the Kubernetes resources.

References:

- [CloudNativePG snapshot backup and recovery](https://cloudnative-pg.io/docs/1.30/appendixes/backup_volumesnapshot/)
- [Longhorn CSI backups](https://longhorn.io/docs/1.13.0/snapshots-and-backups/csi-snapshot-support/csi-volume-snapshot-associated-with-longhorn-backup/)
- [External snapshotter v8.6.0](https://github.com/kubernetes-csi/external-snapshotter/tree/v8.6.0)

## Live validation — 2026-11-02

The first backup, `postgres-longhorn-daily-20261102114905`, completed at
11:49:49 UTC. The CSI snapshot is ready, with handle
`bak://pvc-1efc8a08-9f4a-4d39-b49f-2f6fc88d7c0a/backup-3d0a1fe8e4aa4b67`.
Longhorn reports that backup `Completed` at 100%. PostgreSQL remained healthy,
and all Flux Kustomizations returned Ready. Retention selection tests passed;
RBAC allows listing/deleting CNPG backups and denies PVC deletion. The first
scheduled retention run and a restore drill have not yet been performed.
