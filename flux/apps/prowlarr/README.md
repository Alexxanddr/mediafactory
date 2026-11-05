# Prowlarr custom definitions

`configmap.yaml` bundles MIRCrew and ilDragonero from
[AlexZorzi/Indexers](https://github.com/AlexZorzi/Indexers/tree/648c0561ebd94c1a00d0b103ce2ce6d3e2f9c863/definitions/v11)
at commit `648c0561ebd94c1a00d0b103ce2ce6d3e2f9c863`.
The upstream files have no extension; the ConfigMap exposes them as `.yml`,
as required by Prowlarr.

The Deployment mounts each definition read-only under
`/config/Definitions/Custom/`, preserving other custom files and the existing
configuration PVC. Definitions are versioned in Git and require no startup
download. SubPath mounts require a pod restart after a ConfigMap update.

After Flux deploys the change, open **Indexers → Add Indexer**, select MIRCrew
or ilDragonero, enter the required tracker credentials, then **Test** and
**Save**. Credentials remain in Prowlarr's persistent configuration, not Git.
Installing definitions does not create or enable indexer instances.

Verify both files and check Prowlarr's logs:

```sh
KUBECONFIG=~/.kube/talos kubectl -n multimedia-factory exec deployment/prowlarr -- ls -l /config/Definitions/Custom/mircrew.yml /config/Definitions/Custom/ildragonero.yml
KUBECONFIG=~/.kube/talos kubectl -n multimedia-factory logs deployment/prowlarr --tail=100
```

Confirm both entries appear in **Add Indexer**. A successful tracker test also
requires valid credentials and network access to the tracker.
