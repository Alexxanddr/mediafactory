module "k3s" {
  source  = "xunleii/k3s/module"
  version = "3.4.0"

  k3s_version    = "latest"
  cluster_domain = "cluster.local"
  drain_timeout  = "30s"
  managed_fields = ["label", "taint"]
  global_flags   = ["--kubelet-arg=allowed-unsafe-sysctls=net.core.rmem_max", "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.ip_forward", "--kubelet-arg=allowed-unsafe-sysctls=net.core.wmem_max", "--kubelet-arg=allowed-unsafe-sysctls=net.core.rmem_max"]
  servers = {
    k3s-server = {
      ip = var.master_server_list[0] // internal node IP
      connection = {
        timeout     = "60s"
        type        = "ssh"
        host        = var.master_server_list[0]
        private_key = trimspace(base64decode(var.private_key))
      }
      flags = var.flags_master_server
    }
  }

}


resource "null_resource" "setup_nfs_server" {
  connection {
    type        = "ssh"
    host        = var.master_server_list[0]
    user        = "root" #
    private_key = trimspace(base64decode(var.private_key))
    timeout     = "2m"
  }
  provisioner "remote-exec" {
    inline = flatten([
      [
        "dnf -y install nfs-utils policycoreutils-python-utils",
        "systemctl enable nfs-server",
        "systemctl start nfs-server",
        # "sysctl -w fs.inotify.max_user_watches=100000",
        # "sysctl -w fs.inotify.max_user_instances=100000",
        # "dnf -y install nvidia-container-toolkit",
        # "sudo nvidia-ctk runtime configure --runtime=containerd"
      ],
      # Per ogni directory:
      [for dir in var.nfs_directories : [
        "echo '${dir} *(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,fsid=1)' >> /etc/exports",
        "semanage fcontext -a -t public_content_rw_t '${dir}(/.*)?'",
        "restorecon -Rv ${dir}"
      ]],
      [
        "exportfs -rva"
      ]
    ])
  }

  triggers = {
    directories_hash = md5(join(",", var.nfs_directories))
  }
}
