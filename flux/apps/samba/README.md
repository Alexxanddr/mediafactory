# Samba on the MergerFS pool

Samba exposes the entire existing pool as `md0`, including `MediaFactory` and
`Documents`. On Talos the host path is `/run/mergerfs` (the former `/mnt/md0`);
the container presents it at `/mnt/md0`. No data is copied or reformatted.
The init container waits for a FUSE mount and uses HostToContainer propagation.

Connect from Finder with **Go → Connect to Server** (`Cmd+K`):

```text
smb://192.168.20.3/md0
```

Use registered user `mediafactory`. The generated password is stored only in
the SOPS Secret `samba-auth`, namespace `mergerfs`. Retrieve it locally:

```sh
KUBECONFIG=~/.kube/talos kubectl -n mergerfs get secret samba-auth \
  -o jsonpath='{.data.password}' | base64 --decode
```

SMB2/SMB3 use TCP 445 on the node via host networking. Allowed client networks
match NFS (`192.168.20.0/24`, `192.168.10.0/24`, `192.168.99.0/24`), plus
loopback and the cluster pod network for monitoring. Route TCP 445 between
client VLANs and the node as needed. No HTTPRoute or Internet exposure is used.
Bonjour and Windows discovery are disabled; use the explicit address above.

The upstream image enables `fruit` and `streams_xattr` for macOS compatibility.
Time Machine advertising is disabled. Access is authenticated, read/write,
and uses UID/GID 1000:1000 to match the media directories. Existing Unix
permissions remain authoritative: the pool root is root-owned and `TimeMachine`
currently belongs to 1001:1002 with mode 0700, so this account cannot write to
the pool root or access that directory. No recursive chmod/chown is performed.
Samba SID/database state persists on the 1Gi `samba-state` Longhorn volume,
with one replica and a Retain PV. It does not store the shared media.

## Verification

After the commit is pushed and Flux reconciles:

```sh
export KUBECONFIG=~/.kube/talos
kubectl -n mergerfs rollout status deployment/samba
kubectl -n mergerfs exec deployment/samba -- testparm -s
nc -vz 192.168.20.3 445
smbutil view //mediafactory@192.168.20.3
```

From Finder, open `md0/MediaFactory`, create a temporary file, read it back,
rename it, and remove it. Check the same file from another client if available.
The monitor and TCP probes verify reachability, not authenticated file access.
For configuration changes, increment the pod `config-revision` annotation;
for password rotation, edit `secret.enc.yaml` with SOPS and restart through a
pod-template change committed to Git.

Upstream: <https://github.com/crazy-max/docker-samba>.
