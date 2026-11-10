variable "plex_public_ipv4" {
  description = "Public IPv4 address of the home router forwarding HTTPS to the dedicated Plex ingress."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.plex_public_ipv4}/32"))
    error_message = "Provide the public IPv4 address of the home router."
  }
}

# Keep DNS in the existing Cloudflare state; migrate ownership without deleting the record.
moved {
  from = cloudflare_dns_record.vault_homelab_tunnel["plex"]
  to   = cloudflare_dns_record.plex_remote
}

resource "cloudflare_dns_record" "plex_remote" {
  zone_id = data.cloudflare_zone.cfzone.id
  name    = "plex.${data.cloudflare_zone.cfzone.name}"
  content = var.plex_public_ipv4
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Plex dedicated ingress via home router"
}
