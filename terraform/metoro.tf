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
  name      = "metoro-exporter"
  namespace = "monitoring"

  repository = "https://metoro-io.github.io/metoro-helm-charts/"
  chart      = "metoro-exporter"
  version    = "0.469.0"

  set_sensitive {
    name  = "exporter.secret.bearerToken"
    value = var.metoro_bearer_token
  }
}
