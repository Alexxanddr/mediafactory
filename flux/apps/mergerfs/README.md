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
