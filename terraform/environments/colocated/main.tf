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
    node-01 = { role = "colocated", ip_address = "192.168.131.11", mac_address = "52:54:00:13:10:11" }
    node-02 = { role = "colocated", ip_address = "192.168.131.12", mac_address = "52:54:00:13:10:12" }
    node-03 = { role = "colocated", ip_address = "192.168.131.13", mac_address = "52:54:00:13:10:13" }
  }
}

resource "libvirt_volume" "base" {
  name   = "pgsentry-colocated-base.qcow2"
  pool   = var.storage_pool
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.image_url } }
}

module "network" {
  source = "../../modules/network"
  name   = "pgsentry-colocated"
  cidr   = var.network_cidr
  hosts  = local.nodes
}

module "vm" {
  for_each         = local.nodes
  source           = "../../modules/vm"
  name             = each.key
  role             = each.value.role
  vcpu             = var.vcpu
  memory_mib       = var.memory_mib
  disk_size_gib    = var.disk_size_gib
  storage_pool     = var.storage_pool
  base_volume_path = libvirt_volume.base.path
  network_name     = module.network.name
  ip_address       = each.value.ip_address
  mac_address      = each.value.mac_address
  ssh_user         = var.ssh_user
  ssh_public_key   = file(pathexpand(var.ssh_public_key_path))
}

