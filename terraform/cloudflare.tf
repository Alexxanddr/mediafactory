data "cloudflare_zone" "cfzone" {
  zone_id = var.cloudflare_account.zone_id
}



resource "cloudflare_zero_trust_access_identity_provider" "google" {
  config = {
    client_id     = var.cloudflare_idp_google.client_id
    client_secret = var.cloudflare_idp_google.client_secret
    pkce_enabled  = true
  }
  name    = "google"
  type    = "google"
  zone_id = data.cloudflare_zone.cfzone.id
}

resource "cloudflare_zero_trust_access_policy" "policy_google" {
  account_id = var.cloudflare_account.account_id

  name     = "google-policy"
  decision = "allow"

  include = [{
    email = var.whitelist_email
  }]

  isolation_required             = false
  purpose_justification_required = false
  session_duration               = "24h"
}

resource "cloudflare_zero_trust_access_policy" "policy_geo" {
  account_id = var.cloudflare_account.account_id

  name     = "geo-policy"
  decision = "allow"

include = [
    {
      geo = {
        country_code = "IT"
      }
    }
  ]


  isolation_required             = false
  purpose_justification_required = false
  session_duration               = "24h"
}


resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel_k8s" {
  account_id    = var.cloudflare_account.account_id
  name          = "k8s"
  config_src    = "cloudflare"
  tunnel_secret = var.cloudflare_account.token_tunnel
}



resource "cloudflare_zero_trust_access_application" "apps" {
  for_each = {
    for name, svc in var.services :
    name => svc
    if svc.protected
  }

  domain  = "${each.value.hostname}.${data.cloudflare_zone.cfzone.name}"
  type    = "self_hosted"
  zone_id = data.cloudflare_zone.cfzone.id

  app_launcher_visible      = true
  auto_redirect_to_identity = true

  policies = [
    {
      id = cloudflare_zero_trust_access_policy.policy_google.id
    },
    {
      id = cloudflare_zero_trust_access_policy.policy_geo.id
    }
  ]
}


locals {
  ingress_rules = [
    for service in var.services : {
      hostname = "${service.hostname}.${data.cloudflare_zone.cfzone.name}"
      origin_request = {
        no_tls_verify = true
      }
      service = service.service
    }
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel_k8s.id
  config = {
    ingress = concat(local.ingress_rules, [
      {
        origin_request = {
          connect_timeout        = 0
          keep_alive_connections = 0
          keep_alive_timeout     = 0
          tcp_keep_alive         = 0
          tls_timeout            = 0
        }
        service = "http_status:503"
      },
    ])
    warp_routing = {
      enabled = false
    }
  }
}



resource "cloudflare_dns_record" "vault_homelab_tunnel" {
  for_each = var.services

  zone_id = data.cloudflare_zone.cfzone.id
  comment = "${each.key} tunnel record"
  content = join(".", [cloudflare_zero_trust_tunnel_cloudflared.tunnel_k8s.id, "cfargotunnel.com"])
  name    = "${each.value.hostname}.${data.cloudflare_zone.cfzone.name}"
  proxied = true
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "vault_homelab_tunnel_internal" {
  zone_id = data.cloudflare_zone.cfzone.id
  comment = "zone internal record"
  content = var.master_server_list[0]
  name    = "*.internal.${data.cloudflare_zone.cfzone.name}"
  proxied = false
  ttl     = 1
  type    = "A"
}