resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  create_namespace = true
}

resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  values = [
    file("values/flux-values.yaml")
  ]
}

resource "kubernetes_manifest" "flux_app" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
type: Opaque
data:
  githubAppID: "${base64encode(var.github_app_id)}"
  githubAppInstallationID: "${base64encode(var.github_app_installation_id)}"
  githubAppPrivateKey: "${var.github_app_pem}"
YAML
  )
}


resource "kubernetes_manifest" "flux_sops" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Secret
metadata:
  name: sops-age
  namespace: flux-system
type: Opaque
data:
  age.agekey: "${var.sops_age_key}"
YAML
  )
}
