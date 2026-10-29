variable "master_server_list" {
  type        = list(string)
  description = "IP del control plane Talos (usato anche dai servizi Cloudflare)."
}

variable "cluster_name" {
  type    = string
  default = "mediafactory-talos"
}

variable "talos_version" {
  type    = string
  default = "v1.14.5"
}

variable "install_disk" {
  description = "Disco del ThinkPad da inizializzare per Talos."
  type        = string
  default     = "/dev/nvme0n1"
  nullable    = false

  validation {
    condition     = trimspace(var.install_disk) != ""
    error_message = "install_disk deve essere un device valido per il bootstrap."
  }
}

variable "media_disk_uuids" {
  description = "UUID dei tre filesystem XFS esistenti del ThinkPad, nell'ordine externaldisk1-3."
  type        = list(string)
  default = [
    "5245c734-d3ab-4955-a2ee-55ff9496f3a6",
    "54168ec8-e4d3-4509-8b48-2f8c2ca39756",
    "fc53a0ea-d640-4dd8-9d30-864e0fede3fc",
  ]

  validation {
    condition = length(var.media_disk_uuids) == 0 || (
      length(var.media_disk_uuids) == 3 && length(distinct(var.media_disk_uuids)) == 3 && alltrue([
        for uuid in var.media_disk_uuids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", uuid))
      ])
    )
    error_message = "Fornire zero UUID per generare solo l'immagine o tre UUID filesystem distinti e validi del ThinkPad."
  }
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
    hostname          = string
    internal_hostname = string
    protected         = bool
  }))
}
variable "whitelist_email" {
  description = "whitelist of email for idp provider"
  type        = map(string)
}
