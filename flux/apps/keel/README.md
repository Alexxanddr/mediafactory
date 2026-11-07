# Keel workload coverage

Keel configuration belongs on Deployment, StatefulSet, DaemonSet or CronJob
metadata, not only on the Pod template. The policy used here is `force`, with
`poll` and `matchTag: "true"`: it follows changes to the current image tag and
does not select a newer version tag. Existing image tags and digests are kept.

Helm releases use supported workload annotation values when available. Releases
without those values use Flux Helm post-renderer patches. The Metoro patch only
targets Deployments and DaemonSets, leaving its Redis StatefulSet unchanged.
NVIDIA's `daemonsets.annotations` also covers operator-generated DaemonSets.
Falco propagates CR labels to its generated workloads, so its instances use
Keel labels, which Keel accepts as well as annotations.

Database workloads, database operators and database maintenance jobs are excluded.
Completed Jobs are not changed. Longhorn-generated CSI workloads, engine-image
DaemonSets and maintenance CronJobs remain managed by Longhorn: the chart
post-renderer only covers resources actually rendered by Helm. CoreDNS,
kube-proxy and Flannel remain managed by Talos. These generated resources have
no workload metadata customization in the configuration used here; annotating
Pods alone would not enable Keel for them.

Flux Operator and its controllers are configured through Terraform Helm values.
Their changes require applying the two Flux Helm resources through Terraform;
reconciling the applications GitRepository does not apply bootstrap values.

Validate changes with the complete Flux apps/infrastructure builds and render
each changed Helm release, including its post-renderer. After reconciliation,
inspect workload metadata and Keel logs; annotations alone do not prove a
successful registry poll or an image update. Operator reconciliation may also
restore an operator-managed image after Keel changes it.

```sh
KUBECONFIG=~/.kube/talos kubectl get deployment,statefulset,daemonset,cronjob -A \
  -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name,POLICY:.metadata.annotations.keel\.sh/policy,LABEL_POLICY:.metadata.labels.keel\.sh/policy'
KUBECONFIG=~/.kube/talos kubectl logs -n system-addon deployment/keel --since=15m
```
