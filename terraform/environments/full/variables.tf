variable "libvirt_uri" {
  description = "Local libvirt connection URI."
  type        = string
  default     = "qemu:///system"
}

variable "storage_pool" {
  description = "Existing libvirt storage pool."
  type        = string
  default     = "default"
}

variable "image_url" {
  description = "Cloud image URL used as the shared backing volume."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "network_cidr" {
  description = "Canonical topology network."
  type        = string
  default     = "192.168.130.0/24"
}

variable "ssh_user" {
  description = "Cloud-init administration user."
  type        = string
  default     = "pgsentry"
}

variable "ssh_public_key_path" {
  description = "Path to an existing OpenSSH public key."
  type        = string
}

variable "role_resources" {
  description = "Per-role VM sizing."
  type = map(object({
    vcpu          = number
    memory_mib    = number
    disk_size_gib = number
  }))
  default = {
    postgres = { vcpu = 2, memory_mib = 2048, disk_size_gib = 20 }
    etcd     = { vcpu = 1, memory_mib = 1024, disk_size_gib = 10 }
    control  = { vcpu = 2, memory_mib = 2048, disk_size_gib = 20 }
  }
}

