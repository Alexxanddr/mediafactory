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
starting and exports only:

- `/MediaFactory`
- `/Documents/backup-k3s`

Clients are limited to `192.168.20.0/24`, `192.168.30.0/24`, and
`192.168.10.0/24`. The existing PVs use reclaim policy `Retain`; deleting a
claim does not ask Kubernetes to delete files from an export.

For a manual bootstrap on the ThinkPad, from the repository root:

```sh
talosctl --talosconfig terraform/talosconfig patch machineconfig \
  --nodes 192.168.20.3 --patch @terraform/media-volumes.yaml
kubectl --kubeconfig terraform/kubeconfig label node p53-talos \
  mediafactory/storage-ready=true --overwrite
kubectl --kubeconfig terraform/kubeconfig apply \
  -f flux/apps/mergerfs/namespace.yaml \
  -f flux/apps/mergerfs/deployment.yaml
kubectl --kubeconfig terraform/kubeconfig -n mergerfs \
  rollout status deployment/mergerfs
kubectl --kubeconfig terraform/kubeconfig apply \
  -f flux/apps/mergerfs/nfs-ganesha-config.yaml \
  -f flux/apps/mergerfs/nfs-ganesha-deployment.yaml
kubectl --kubeconfig terraform/kubeconfig apply \
  -f flux/infrastructure/nfs-csi/helmrepository.yaml \
  -f flux/infrastructure/nfs-csi/storageclass.yaml \
  -f flux/infrastructure/nfs-csi/persistentvolume.yaml \
  -f flux/infrastructure/nfs-csi/persistentvolumeclaim.yaml
```

The Talos patch and manifests are idempotent. Do not replace these existing
filesystems with `UserVolumeConfig`, and do not run formatting or wipe commands
against the three data disks.
