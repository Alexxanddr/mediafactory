# PostgreSQL restore drill

This diagnostic Cluster is deliberately outside active Flux paths. It restores
an NFS-backed CSI snapshot into a new 50 GiB Longhorn PVC, using the same
PostgreSQL image as production. It does not change application services or the
production Cluster. Update the snapshot reference and image before reuse.

The 2026-11-02 run was explicitly authorized as a diagnostic restore test.
Apply `cluster.yaml` only for an authorized drill; compare database/schema
inventories, run a complete logical dump of each non-template database, and
verify an insert/read/rollback in the restored instance. Never redirect
application traffic to the restored services.

After verification, delete the diagnostic Cluster and its PVC. Because the
StorageClass uses `Retain`, also remove only the identified test PV and detached
Longhorn volume after confirming the production volume ID differs. Never use
wildcards or production selectors for cleanup. Do not leave the test copy on
the NVMe after the drill.

`backup.yaml` is a one-time post-cleanup checkpoint, also excluded from Flux.
It deliberately uses the daily schedule's label so the normal seven-successful-
backup retention includes it. Apply it only after purge/TRIM has completed;
update its dated name before repeating the procedure. Do not delete the Backup
or its CSI snapshot after testing: it is a retained recovery point on NFS.
