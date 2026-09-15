resource "kubernetes_manifest" "monitoring" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
YAML
  )
}

resource "kubernetes_manifest" "metoro_exporter_secret" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Secret
metadata:
  name: metoro-exporter-secret
  namespace: monitoring
type: Opaque
data:
  REDIS_PASSWORD: "${base64encode(var.redis_password)}"
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
    name  = "redis.enabled"
    value = "false"
  }

  # set {
  #   name  = "exporter.secret.externalSecret.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "exporter.envVars.userDefined.REDIS_HOST"
  #   value = "redis-master.database.svc.cluster.local"
  # }

  # set {
  #   name  = "exporter.envVars.userDefined.REDIS_PORT"
  #   value = "6379"
  # }
  # set_sensitive {
  #   name  = "exporter.envVars.userDefined.REDIS_PASSWORD"
  #   value = var.redis_password
  # }

  # set {
  #   name  = "exporter.envVars.userDefined.REDIS_DB"
  #   value = "5"
  # }
}