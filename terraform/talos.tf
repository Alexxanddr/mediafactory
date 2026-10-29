locals {
  machine_patch = yamlencode({
    machine = merge(
      {
        kernel = {
          modules = [
            { name = "i915" },
            { name = "nvidia" },
            { name = "nvidia_uvm" },
            { name = "nvidia_drm" },
            { name = "nvidia_modeset" },
          ]
        }
      },
    )
  })

  unattended_install_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UnattendedInstallConfig"
    installer = {
      image = data.talos_image_factory_urls.thinkpad.urls.installer
    }
    provisioning = {
      diskSelector = {
        match = "disk.dev_path == \"${var.install_disk}\" && disk.serial == \"PHHP943100NH512C\""
      }
      wipe = true
    }
  })

  hostname_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "HostnameConfig"
    auto       = "off"
    hostname   = "p53-talos"
  })

  disk_volume_patches = [
    for index, uuid in var.media_disk_uuids : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExistingVolumeConfig"
      name       = "externaldisk${index + 1}"
      discovery = {
        volumeSelector = {
          match = "volume.uuid == \"${uuid}\""
        }
      }
    })
  ]

  talos_extensions = [
    "siderolabs/fuse3",
    "siderolabs/i915",
    "siderolabs/intel-ucode",
    "siderolabs/iscsi-tools",
    "siderolabs/nfsd",
    "siderolabs/nfs-utils",
    "siderolabs/nvidia-container-toolkit-lts",
    "siderolabs/nvidia-open-gpu-kernel-modules-lts",
    "siderolabs/util-linux-tools",
  ]
}

resource "talos_image_factory_schematic" "thinkpad" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = local.talos_extensions
      }
    }
  })
}

data "talos_image_factory_urls" "thinkpad" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.thinkpad.id
  architecture  = "amd64"
  platform      = "metal"
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.master_server_list[0]}:6443"
  talos_version    = var.talos_version
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = concat(
    [
      local.machine_patch,
      local.unattended_install_patch,
      local.hostname_patch,
    ],
    local.disk_volume_patches,
    [
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeNodeConfig"
        labels     = length(var.media_disk_uuids) == 3 ? { "mediafactory/storage-ready" = "true" } : {}
        taints = {
          "node-role.kubernetes.io/control-plane" = {
            "$patch" = "delete"
          }
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
    ],
  )
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [var.master_server_list[0]]
  endpoints            = [var.master_server_list[0]]
}

resource "terraform_data" "initial_config" {
  input = sha256(jsonencode(talos_machine_secrets.this.machine_secrets))

  triggers_replace = sha256(jsonencode({
    machine_secrets       = talos_machine_secrets.this.machine_secrets
    machine_configuration = data.talos_machine_configuration.controlplane.machine_configuration
  }))

  lifecycle {
    precondition {
      condition     = trimspace(var.install_disk) != ""
      error_message = "Per installare Talos imposta install_disk al device di sistema del ThinkPad."
    }
  }

  provisioner "local-exec" {
    command = "printf '%s' \"$TALOS_MACHINE_CONFIGURATION\" | talosctl --talosconfig ${path.module}/talosconfig --nodes ${var.master_server_list[0]} apply-config --file /dev/stdin"

    environment = {
      TALOS_MACHINE_CONFIGURATION = data.talos_machine_configuration.controlplane.machine_configuration
    }
  }
}

resource "talos_machine" "this" {
  depends_on            = [terraform_data.initial_config]
  node                  = var.master_server_list[0]
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.controlplane.machine_configuration
  image                 = data.talos_image_factory_urls.thinkpad.urls.installer
  drain_on_upgrade      = false
}

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine.this]
  node                 = var.master_server_list[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  node                 = var.master_server_list[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}
