variable "master_server_list" {
  type        = list(string)
  description = "This variable contains list of Master k3s server"
}
variable "flags_master_server" {
  type        = list(string)
  description = "This variable contains the flags of k3s master options"
}

variable "nfs_directories" {
  type = list(string)
}
variable "private_key" {
  type = string
}

variable "github_app_id" {
  description = "GitHub App ID"
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID"
  type        = string
  default     = ""
}

variable "github_app_pem" {
  description = "The contents of the GitHub App private key PEM file"
  sensitive   = true
  type        = string
  default     = ""
}

variable "sops_age_key" {
  type      = string
  sensitive = true
}

variable "metoro_bearer_token" {
  type      = string
  sensitive = true
}
variable "cloudflare_api_token" {
  type        = string
  description = "cloudflare api token"
  sensitive   = true
}
variable "cloudflare_account" {
  type        = map(string)
  description = "cloudflare settings"
  sensitive   = true
}
variable "cloudflare_idp_google" {
  type        = map(string)
  description = "Sensitive data for idp google configuration"
  sensitive   = true
}
variable "services" {
  description = "Values for the services to be exposed via Cloudflare Tunnel"
  type = map(object({
    hostname  = string
    service   = string
    protected = bool
  }))
}
variable "whitelist_email" {
  description = "whitelist of email for idp provider"
  type        = map(string)
}
