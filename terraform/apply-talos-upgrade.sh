#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
export KUBECONFIG="$HOME/.kube/talos"

node=p53-talos
address=192.168.20.3
plan=${1:?Usage: apply-talos-upgrade.sh /absolute/path/to/upgrade.tfplan}
terraform show -json "$plan" | jq -e '[.resource_changes[] | select(.mode == "managed" and .change.actions != ["no-op"])] | length == 1 and (.[0] | .address == "talos_machine.this" and .change.actions == ["update"] and .change.before.image != .change.after.image and (.change.before | del(.image)) == (.change.after | del(.image)))' >/dev/null

kubectl get node "$node" -o json | jq -e --arg address "$address" '
  (.spec.unschedulable != true) and any(.status.addresses[]; .type == "InternalIP" and .address == $address)
' >/dev/null
kubectl -n mergerfs rollout status deployment/nfs-ganesha --timeout=60s

clients() {
  jq -rs --arg address "$address" '
    (.[0].items | map(select((.spec.csi.driver == "nfs.csi.k8s.io" and .spec.csi.volumeAttributes.server == $address) or .spec.nfs.server == $address) | .metadata.name)) as $volumes
    | (.[1].items | map(select(.spec.volumeName as $volume | $volumes | index($volume)) | [.metadata.namespace, .metadata.name])) as $claims
    | .[2].items[] | . as $pod
    | select(any(.spec.volumes[]?; .nfs.server == $address or ([$pod.metadata.namespace, .persistentVolumeClaim.claimName] as $claim | any($claims[]; . == $claim))))
    | [.metadata.namespace, .metadata.name] | @tsv
  '
}

kubectl cordon "$node"
apply_started=false
cleanup() {
  if ! $apply_started; then
    kubectl uncordon "$node"
  fi
}
trap cleanup EXIT

pvs=$(kubectl get pv -o json)
pvcs=$(kubectl get pvc -A -o json)
pods=$(kubectl get pods -A --field-selector "spec.nodeName=$node" -o json)
client_pods=$(printf '%s\n' "$pvs" "$pvcs" "$pods" | clients)
while IFS=$'\t' read -r namespace pod; do
  [[ -n "$pod" ]] || continue
  kubectl -n "$namespace" delete pod "$pod" --ignore-not-found --wait=false
done <<< "$client_pods"

# Talos must be able to unmount volumes while the local NFS server is still running.
for ((attempt=0; attempt<60; attempt++)); do
  pods=$(kubectl get pods -A --field-selector "spec.nodeName=$node" -o json)
  client_pods=$(printf '%s\n' "$pvs" "$pvcs" "$pods" | clients)
  mountinfo=$(talosctl --talosconfig ./talosconfig -n "$address" read /proc/1/mountinfo)
  local_mounts=$(awk -v server="$address:" '/ - nfs4? / && index($(NF-1), server) == 1 {print $5}' <<< "$mountinfo")
  if [[ -z "$client_pods" && -z "$local_mounts" ]]; then
    break
  fi
  sleep 5
done
if [[ -n "$client_pods" || -n "$local_mounts" ]]; then
  printf 'Local NFS clients or mounts remain. Upgrade aborted.\n%s\n%s\n' "$client_pods" "$local_mounts" >&2
  exit 1
fi

apply_started=true
terraform apply -input=false "$plan"
kubectl wait --for=condition=Ready "node/$node" --timeout=5m
kubectl uncordon "$node"
