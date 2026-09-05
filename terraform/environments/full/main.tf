terraform {
  required_version = ">= 1.8.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.9"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

locals {
  nodes = {
    pg-01      = { role = "postgres", ip_address = "192.168.130.11", mac_address = "52:54:00:13:00:11" }
    pg-02      = { role = "postgres", ip_address = "192.168.130.12", mac_address = "52:54:00:13:00:12" }
    pg-03      = { role = "postgres", ip_address = "192.168.130.13", mac_address = "52:54:00:13:00:13" }
    etcd-01    = { role = "etcd", ip_address = "192.168.130.21", mac_address = "52:54:00:13:00:21" }
    etcd-02    = { role = "etcd", ip_address = "192.168.130.22", mac_address = "52:54:00:13:00:22" }
    etcd-03    = { role = "etcd", ip_address = "192.168.130.23", mac_address = "52:54:00:13:00:23" }
    control-01 = { role = "control", ip_address = "192.168.130.31", mac_address = "52:54:00:13:00:31" }
  }
}

resource "libvirt_volume" "base" {
  name   = "pgsentry-full-base.qcow2"
  pool   = var.storage_pool
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.image_url } }
}

module "network" {
  source = "../../modules/network"
  name   = "pgsentry-full"
  cidr   = var.network_cidr
  hosts  = local.nodes
}

module "vm" {
  for_each         = local.nodes
  source           = "../../modules/vm"
  name             = each.key
  role             = each.value.role
  vcpu             = var.role_resources[each.value.role].vcpu
  memory_mib       = var.role_resources[each.value.role].memory_mib
  disk_size_gib    = var.role_resources[each.value.role].disk_size_gib
  storage_pool     = var.storage_pool
  base_volume_path = libvirt_volume.base.path
  network_name     = module.network.name
  ip_address       = each.value.ip_address
  mac_address      = each.value.mac_address
  ssh_user         = var.ssh_user
  ssh_public_key   = file(pathexpand(var.ssh_public_key_path))
}

