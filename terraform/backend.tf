terraform {
  cloud {
    organization = "alexxanddr-cloud"

    workspaces {
      name = "mediafactory-talos"
    }
  }
}
