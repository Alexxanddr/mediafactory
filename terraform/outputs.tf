output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talos_installer_image" {
  value = data.talos_image_factory_urls.thinkpad.urls.installer
}

output "talos_iso" {
  value = data.talos_image_factory_urls.thinkpad.urls.iso
}

output "talos_disk_image" {
  description = "Immagine raw compressa da scrivere sul disco di boot del ThinkPad."
  value       = data.talos_image_factory_urls.thinkpad.urls.disk_image
}

output "talos_schematic_id" {
  value = talos_image_factory_schematic.thinkpad.id
}
