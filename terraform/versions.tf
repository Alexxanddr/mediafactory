terraform {
  required_providers {
    # https://registry.terraform.io/providers/hashicorp/helm/latest/docs
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    # https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.3.2"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
    /* Cloudflare resta gestito dal workspace k3s-server.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5"
    }
    */
  }
  # https://github.com/hashicorp/terraform/releases
  required_version = ">= 1.7.0"
}
