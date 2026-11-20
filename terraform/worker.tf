resource "talos_image_factory_schematic" "thinkcentre" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          for extension in local.talos_extensions : extension
          if !startswith(extension, "siderolabs/nvidia-")
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "thinkcentre" {
  talos_version = data.talos_image_factory_urls.thinkpad_upgrade.talos_version
  schematic_id  = talos_image_factory_schematic.thinkcentre.id
  architecture  = "amd64"
  platform      = "metal"
}

variable "thinkcentre_ip" {
  description = "Reserved IP address of the ThinkCentre worker."
  type        = string
  default     = "192.168.20.4"
}

data "talos_machine_configuration" "thinkcentre" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = "https://${var.master_server_list[0]}:6443"
  talos_version      = data.talos_image_factory_urls.thinkcentre.talos_version
  kubernetes_version = "v1.37.0"
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = "thinkcentre-talos"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = data.talos_image_factory_urls.thinkcentre.urls.installer
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/nvme0n1\" && disk.serial == \"FJACN72991100CT37\""
        }
        wipe = true
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeletConfig"
      extraArgs = {
        "max-pods"               = "200"
        "allowed-unsafe-sysctls" = "net.ipv4.conf.all.src_valid_mark,net.ipv6.conf.all.disable_ipv6"
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ResolverConfig"
      hostDNS = {
        enabled              = false
        forwardKubeDNSToHost = false
      }
    }),
  ]
}

resource "talos_machine" "thinkcentre" {
  node                  = var.thinkcentre_ip
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.thinkcentre.machine_configuration
  image                 = data.talos_image_factory_urls.thinkcentre.urls.installer
  kubeconfig            = file("${path.module}/kubeconfig")

  lifecycle {
    precondition {
      condition     = !contains(var.master_server_list, var.thinkcentre_ip)
      error_message = "The ThinkCentre worker must have a different IP from the control plane."
    }
  }
}
