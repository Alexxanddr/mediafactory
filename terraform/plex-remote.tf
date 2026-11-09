variable "plex_vps_ipv4" {
  description = "Reserved public IPv4 address of the dedicated OCI Plex relay."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.plex_vps_ipv4}/32"))
    error_message = "Provide the reserved public IPv4 address of the Plex relay."
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
  content = var.plex_vps_ipv4
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Plex TCP relay over Tailscale"
}
