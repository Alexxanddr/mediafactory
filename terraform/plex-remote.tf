# Keep Plex DNS in the existing Cloudflare state.
moved {
  from = cloudflare_dns_record.vault_homelab_tunnel["plex"]
  to   = cloudflare_dns_record.plex_remote
}

resource "cloudflare_dns_record" "plex_remote" {
  zone_id = data.cloudflare_zone.cfzone.id
  name    = "plex.${data.cloudflare_zone.cfzone.name}"
  content = "router.${data.cloudflare_zone.cfzone.name}"
  type    = "CNAME"
  proxied = false
  ttl     = 60
  comment = "Plex dedicated ingress via home router"
}
