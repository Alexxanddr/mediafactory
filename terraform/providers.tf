# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig"
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
provider "talos" {}
