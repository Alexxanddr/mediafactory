# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    host                   = module.k3s.kubernetes.api_endpoint
    cluster_ca_certificate = module.k3s.kubernetes.cluster_ca_certificate
    client_certificate     = module.k3s.kubernetes.client_certificate
    client_key             = module.k3s.kubernetes.client_key
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  host                   = module.k3s.kubernetes.api_endpoint
  cluster_ca_certificate = module.k3s.kubernetes.cluster_ca_certificate
  client_certificate     = module.k3s.kubernetes.client_certificate
  client_key             = module.k3s.kubernetes.client_key
}
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
provider "mongodbatlas" {
  client_id     = var.mongodb_atlas_api_key.client_id
  client_secret = var.mongodb_atlas_api_key.client_secret
}
provider "null" {}
