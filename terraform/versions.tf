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
    null = {
      source  = "hashicorp/null"
      version = ">=3.2.4"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = ">=2.3.0"
    }
  }
  # https://github.com/hashicorp/terraform/releases
  required_version = ">= 1.0"
}
