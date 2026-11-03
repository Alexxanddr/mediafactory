# External media disks, mergerfs, and NFS

Talos mounts the three existing XFS filesystems by filesystem UUID at
`/var/mnt/externaldisk1-3`. The UUIDs are in
[`terraform/variables.tf`](../../../terraform/variables.tf); the equivalent
Talos patch for manual use is [`terraform/media-volumes.yaml`](../../../terraform/media-volumes.yaml).
These are `ExistingVolumeConfig` resources: they discover and mount existing
filesystems and do not partition or format them.

The `mergerfs` Deployment waits until all three host paths are mounted as XFS,
then presents them at `/run/mergerfs`. `/run` is used because Talos keeps
`/var/mnt` read-only to Pods. NFS-Ganesha waits for the FUSE mount before
starting and exports these NFSv4 paths:

- `/MediaFactory`

`/MediaFactory` allows `192.168.20.0/24`, `192.168.10.0/24`, and
`192.168.99.0/24`. No other directory is exported. The existing PVs use
reclaim policy `Retain`; deleting a claim does not ask Kubernetes to delete
files from an export.

[Samba](../samba/README.md) additionally exposes the entire pool as `md0`
over authenticated SMB2/SMB3 on the node TCP port 445. The Talos pool path
`/run/mergerfs` corresponds to the former `/mnt/md0`.

For a manual bootstrap on the ThinkPad, from the repository root:

```sh
export KUBECONFIG=~/.kube/talos
talosctl --talosconfig terraform/talosconfig patch machineconfig \
  --nodes 192.168.20.3 --patch @terraform/media-volumes.yaml
kubectl label node p53-talos \
  mediafactory/storage-ready=true --overwrite
kubectl apply \
  -f flux/apps/mergerfs/namespace.yaml \
  -f flux/apps/mergerfs/deployment.yaml
kubectl -n mergerfs \
  rollout status deployment/mergerfs
kubectl apply \
  -f flux/apps/mergerfs/nfs-ganesha-config.yaml \
  -f flux/apps/mergerfs/nfs-ganesha-deployment.yaml
kubectl apply \
  -f flux/infrastructure/nfs-csi/helmrepository.yaml \
  -f flux/infrastructure/nfs-csi/storageclass.yaml \
  -f flux/infrastructure/nfs-csi/persistentvolume.yaml \
  -f flux/infrastructure/nfs-csi/persistentvolumeclaim.yaml
```

The Talos patch and manifests are idempotent. Do not replace these existing
filesystems with `UserVolumeConfig`, and do not run formatting or wipe commands
against the three data disks.

## Automatic recovery controller

The infrastructure manifests in `flux/infrastructure/storage-recovery/` deploy
[stale-file-controller-k8s](https://github.com/Alexxanddr/stale-file-controller-k8s).
It serializes MergerFS restart/read -> Ganesha restart/real NFS export read ->
all discovered client restarts/namespace mount reads. NFS CSI 4.13.4's
NodePublish ESTALE remount complements this ordering. Plex's local MergerFS PV
is discovered as well as NFS CSI claims. The privileged diagnostic DaemonSet
checks actual client mount namespaces even for images without shell tools.

The checkpoint and Lease survive controller restarts. Normal pod termination
is never forced: blocked NFS I/O requires storage/node investigation, and
recovery remains incomplete until replacement mounts pass checks. See the
software README for exact privileges, timeouts and read-only verification
commands. Deployment through Flux requires the published GHCR image to be
publicly pullable. No manual apply is required.

### Live validation — 2026-10-29

Activated via Flux at revision `024641e` after explicit approval of the storage
interruption. The initial recovery completed in one cycle: MergerFS recreated
and its FUSE path read, Ganesha recreated only after that gate, real NFS export
read, then 15 client Pods normally recreated and all replacements Ready.
Client-namespace filesystem checks passed for NFS and direct MergerFS mounts,
including `/export/MediaFactory/torrents` in Radarr, Sonarr and qBittorrent, and
the FUSE mounts of Plex and Samba. Final checkpoint: `phase=complete`,
`active=false`, `failures=0`.

The API server's WebSocket upgrade authorization required `create` as well as
`get` on `pods/exec`. This was corrected only in the dedicated namespaced Role,
through GitOps. Recovery resumed from its checkpoint without repeating the
MergerFS restart or duplicating client restarts. The reusable upstream manifests
include the same fix in release v0.1.1 and an authorization regression test
(35 tests plus the Linux FUSE/shell-less smoke test passed).

No forced deletion, direct apply or PVC/PV/data mutation was used. Blocked-kernel
I/O and simultaneous externally induced failures were not injected on the live
cluster; those behavior limits and automated tests are documented upstream.

## Directory attribute freshness

Use `func.getattr=newest` when exporting the union through NFS. MergerFS's
default `getattr` policy is `ff`: a directory duplicated across branches can
retain the first branch's old mtime even after a child is created on another
branch. NFS directory/name caches can then retain an outdated view without
returning ESTALE. Selecting the branch with the newest mtime exposes that
change to metadata consumers. This costs additional attribute lookups across
branches and also affects attributes of regular files duplicated across them.
It does not replace the normal cache/coherency rules of NFS.

[Upstream explanation](https://trapexit.github.io/mergerfs/2.42.0/known_issues_bugs/#directory-mtime-is-not-being-updated).

Run `sh tests/mergerfs-directory-mtime.sh` from the repository root to check
the configured image and options against synthetic branches. The local Docker
test requires privileged FUSE support (and amd64 emulation on other platforms),
uses no host data volumes or networking, and fails if a visible new child does
not update the union parent's advertised mtime. It does not restart Kubernetes
workloads. Applying a changed MergerFS command through Flux does restart the
union server and triggers the configured storage recovery sequence.

The recovery controller checks mount accessibility and stale-handle errors,
not equality of every directory listing between FUSE and NFS. A successful
health check does not prove that every newly created name is already visible
through a cached client mount.

### Directory coherency validation — 2026-11-02

The `func.getattr=newest` change was reconciled through Flux after approval of
storage/client restarts. The recovery sequence completed with 15 clients Ready
and their live mounts verified; the checkpoint returned to `complete`,
`active=false`, `failures=0`.

A live filesystem check created one uniquely named empty diagnostic directory
through a client NFS mount as the application's UID 1000. The directory was
visible from the creating client, another client Pod, and the FUSE union. The
union parent's mtime matched the newest backing branch, and the NFS parent's
mtime matched the union. The diagnostic directory was removed with `rmdir`;
no existing media files were modified. The previously reported missing series
directory was visible through the original client mount after recovery.

The configured-image Docker regression test, full Flux apps/infrastructure
renders, whitespace checks and SOPS/Gitleaks pre-commit hooks passed. This
validates the observed metadata-policy defect; it is not a guarantee of
instantaneous cache invalidation across every independent NFS client.

## Diagnosing overlapping mounts

The backing host bind and FUSE overmount can both appear at the union path in
`/proc/PID/mountinfo`. Mount IDs are reusable identifiers, not a numeric or
lexicographic visibility order. The visible filesystem must be resolved through
parent relationships, including overmounts that hide older child mounts.

A probe reporting `expected fuse, found tmpfs` while an in-container read and
mountinfo show the FUSE above tmpfs can be a diagnostic-parser failure. Probe
release v0.1.2 fixes this case, with regression coverage for both layer orders,
hidden child mounts and a Linux FUSE-over-tmpfs integration fixture. The
DaemonSet template revision ensures that the diagnostic agent pulls the fix.
Do not reset a recovery checkpoint or bypass the filesystem gate to hide this
error; updating the agent lets the existing recovery resume its normal sequence.

### Visible-mount validation — 2026-11-03

A controller Pod was Running with no restarts but failed readiness with HTTP
503 because a checkpoint had remained in `mergerfs-up` beyond its deadline.
An in-container read succeeded, while the old probe selected the underlying
tmpfs instead of the visible FUSE overmount from the same mountinfo records.
The parser defect was reproduced before the fix and covered by regression tests.

Source release v0.1.2 (`05400d6`) passed 39 tests and the Linux stacked-mount
smoke test. Flux revision `8c2a1a2` rolled the diagnostic agent to that image.
The original checkpoint and Lease were preserved: MergerFS passed its gate
without another restart, then Ganesha and 15 clients completed normal recovery.
The original controller Pod became Ready with zero restarts, all replacement
clients were Ready and their mounts verified, and the checkpoint returned to
`complete`, `active=false`, `failures=0`. No health gate was disabled, no deadline
or permissions were relaxed, and no forced deletion or volume/data mutation
was used.
