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
  description = "Development topology network."
  type        = string
  default     = "192.168.131.0/24"
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

variable "vcpu" {
  description = "Virtual CPUs per development node."
  type        = number
  default     = 2
}

variable "memory_mib" {
  description = "Memory in MiB per development node."
  type        = number
  default     = 2048
}

variable "disk_size_gib" {
  description = "Disk capacity in GiB per development node."
  type        = number
  default     = 20
}

