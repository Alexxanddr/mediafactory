resource "kubernetes_manifest" "monitoring" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
YAML
  )
}


resource "helm_release" "metoro_exporter" {
  name       = "metoro-exporter"
  namespace  = "monitoring"
  repository = "https://metoro-io.github.io/metoro-helm-charts"
  chart      = "metoro-exporter"
  version    = "0.478.0"

  set_sensitive {
    name  = "exporter.secret.bearerToken"
    value = var.metoro_bearer_token
  }

  set {
    name  = "redis.master.count"
    value = "0"
  }

  # Temporarily suspend Metoro workloads while the Talos node is stabilized.
  # Disable the HPA as it would otherwise restore exporter replicas.
  set {
    name  = "exporter.autoscaling.horizontalPodAutoscaler.enabled"
    value = "false"
  }

  set {
    name  = "exporter.replicas"
    value = "0"
  }

  set {
    name  = "serviceMonitorScraping.enabled"
    value = "false"
  }

  # The chart renders nodeAgent as a DaemonSet without an enabled switch.
  # This selector deliberately matches no node, so it has no scheduled pods.
  set {
    name  = "nodeAgent.scheduling.nodeSelector.kubernetes\\.io/hostname"
    value = "metoro-disabled"
  }
}
