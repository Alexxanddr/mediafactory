# Longhorn backups

The default backup target uses the existing NFS backup directory. Its URL pins
NFSv4.1 with soft I/O, a 10-second RPC timeout and two retransmissions. The
NFSv4.2 client session observed on 2026-11-02 had an expired lease and blocked
backup processes indefinitely after the NFS server was recreated. A fresh
NFSv4.1 mount could read the same backupstore immediately. This setting is a
mitigation; it does not prove that every NFS session recovery failure is fixed.

Volume backups run daily at 02:00 UTC; system backups run at 03:00 UTC. Both
retain seven backups. CronJobs use `Forbid`, so a stuck run prevents subsequent
runs. Check completion and backup timestamps, rather than CronJob existence:

```sh
KUBECONFIG=~/.kube/talos kubectl get cronjobs,jobs -n longhorn-system
KUBECONFIG=~/.kube/talos kubectl get backups.longhorn.io -n longhorn-system
KUBECONFIG=~/.kube/talos kubectl get systembackups.longhorn.io -n longhorn-system
KUBECONFIG=~/.kube/talos kubectl get volumes.longhorn.io -n longhorn-system \
  -o custom-columns=NAME:.metadata.name,LAST_BACKUP:.status.lastBackupAt
```

If an instance-manager backupstore mount stops responding while a fresh mount
works, inspect NFS lease/session state before restarting anything. Restarting
an instance manager interrupts every volume it hosts; use a maintenance window
and verify application recovery. Never delete completed backups to clear a
stuck job.

## Recovery validation — 2026-11-02

After the explicitly authorized instance-manager restart, all 57 attached
volumes returned healthy and all application Pods became ready. All 57 have
a completed backup dated November 2, including `vinted-monitoring`, which
previously had no backup. The remaining detached volume retains its previous
backup and is excluded by `allow-recurring-job-while-volume-detached=false`.
The system backup `system-b-8aef4930-eda9-4686-96ec-6de1b9879cd1` reached
`Ready`. No backup created after recovery entered `Error`.

The CronJob automatically caught up its missed November 2 run after removal
of the stuck October 31 Job. It initially skipped volumes still attaching;
the subsequent system backup covered these after attachment completed. A
temporary duplicate manual volume Job was stopped. Historical failed backup
records were preserved. This validation did not include a restore test.
