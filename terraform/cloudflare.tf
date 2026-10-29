# Cloudflare is still managed by the unchanged k3s-server workspace. Remove
# any objects recorded by failed applies in mediafactory-talos from this
# workspace state without deleting them from Cloudflare.
removed {
  from = cloudflare_zero_trust_access_identity_provider.google

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_access_policy.policy_google

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_access_policy.policy_geo

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_tunnel_cloudflared.tunnel_k8s

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_access_application.apps

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.homelab

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.vault_homelab_tunnel

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.vault_homelab_tunnel_internal

  lifecycle {
    destroy = false
  }
}
