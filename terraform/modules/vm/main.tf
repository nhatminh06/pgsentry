locals {
  disk_bytes = var.disk_size_gib * 1024 * 1024 * 1024
}

resource "libvirt_volume" "root" {
  name       = "${var.name}-root.qcow2"
  pool       = var.storage_pool
  capacity   = local.disk_bytes
  allocation = 0
  target     = { format = { type = "qcow2" } }
  backing_store = {
    path   = var.base_volume_path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "this" {
  name = "${var.name}-cloud-init"
  meta_data = yamlencode({
    instance-id    = var.name
    local-hostname = var.name
    pgsentry-role  = var.role
  })
  user_data = "#cloud-config\n${yamlencode({
    users = [{
      name                = var.ssh_user
      groups              = "sudo"
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = [var.ssh_public_key]
    }]
    disable_root    = true
    ssh_pwauth      = false
    package_update  = false
    package_upgrade = false
  })}"
}

resource "libvirt_volume" "cloudinit" {
  name = "${var.name}-cloud-init.iso"
  pool = var.storage_pool
  create = {
    content = { url = libvirt_cloudinit_disk.this.path }
  }
}

resource "libvirt_domain" "this" {
  name        = var.name
  memory      = var.memory_mib
  memory_unit = "MiB"
  vcpu        = var.vcpu
  type        = "kvm"
  running     = true
  features = {
    acpi = true
    apic = {}
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }
  devices = {
    disks = [
      {
        source = { volume = { pool = libvirt_volume.root.pool, volume = libvirt_volume.root.name } }
        target = { dev = "vda", bus = "virtio" }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = { volume = { pool = libvirt_volume.cloudinit.pool, volume = libvirt_volume.cloudinit.name } }
        target = { dev = "sda", bus = "sata" }
      }
    ]
    interfaces = [{
      type   = "network"
      mac    = { address = var.mac_address }
      model  = { type = "virtio" }
      source = { network = { network = var.network_name } }
    }]
    graphics = [{ vnc = { auto_port = true, listen = "127.0.0.1" } }]
  }
}
