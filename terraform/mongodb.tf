resource "kubernetes_manifest" "extra_tools" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: extra-tools
YAML
  )
}

resource "mongodbatlas_project" "homelab" {
  name   = "HomeLab"
  org_id = var.mongodb_org_id
}

# # Create a cluster
resource "mongodbatlas_advanced_cluster" "this" {
  project_id   = mongodbatlas_project.homelab.id
  name         = "HomeLab"
  cluster_type = "REPLICASET"

  replication_specs = [
    {
      region_configs = [
        {
          electable_specs = {
            instance_size = "M0"
          }
          provider_name         = "TENANT"
          backing_provider_name = "AWS"
          region_name           = "EU_CENTRAL_1"
          priority              = 7
        }
      ]
    }
  ]
}



resource "mongodbatlas_database_user" "admin" {
  username           = var.mongodb_user.username
  password           = var.mongodb_user.password
  project_id         = mongodbatlas_project.homelab.id
  auth_database_name = "admin"

  roles {
    role_name     = "atlasAdmin"
    database_name = "admin"
  }

  scopes {
    name = mongodbatlas_advanced_cluster.this.name
    type = "CLUSTER"
  }
}

resource "kubernetes_manifest" "mongodb_host" {
  manifest = yamldecode(<<YAML
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-secret
  namespace: extra-tools
type: Opaque
data:
  MONGO_ENDPOINT: "${local.mongodb_uri_encoded}"
  API_ENDPOINT: "${base64encode(local.yourspotifyserver_endpoint)}"
  CLIENT_ENDPOINT: "${base64encode(local.yourspotify_endpoint)}"
YAML
  )
}


locals {
  mongodb_host        = replace(mongodbatlas_advanced_cluster.this.connection_strings.standard_srv, "mongodb+srv://", "")
  mongodb_uri_encoded = base64encode("mongodb+srv://${var.mongodb_user.username}:${urlencode(var.mongodb_user.password)}@${local.mongodb_host}/your_spotify")
  yourspotify_endpoint = "https://spotify.internal.${data.cloudflare_zone.cfzone.name}"
  yourspotifyserver_endpoint = "https://spotify-server.internal.${data.cloudflare_zone.cfzone.name}"
}
