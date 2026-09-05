variable "name" {
  description = "Deterministic VM name and hostname."
  type        = string
}

variable "role" {
  description = "Machine role recorded in metadata."
  type        = string
  validation {
    condition     = contains(["postgres", "etcd", "control", "colocated"], var.role)
    error_message = "Role must be postgres, etcd, control, or colocated."
  }
}

variable "vcpu" {
  description = "Virtual CPU count."
  type        = number
  validation {
    condition     = var.vcpu >= 1 && floor(var.vcpu) == var.vcpu
    error_message = "vCPU count must be a positive integer."
  }
}

variable "memory_mib" {
  description = "Memory allocation in MiB."
  type        = number
  validation {
    condition     = var.memory_mib >= 512
    error_message = "Memory must be at least 512 MiB."
  }
}

variable "disk_size_gib" {
  description = "Root disk capacity in GiB."
  type        = number
  validation {
    condition     = var.disk_size_gib >= 8
    error_message = "Disk size must be at least 8 GiB."
  }
}

variable "storage_pool" {
  description = "Existing libvirt storage pool."
  type        = string
}

variable "base_volume_path" {
  description = "Shared cloud-image base volume path."
  type        = string
}

variable "network_name" {
  description = "Libvirt network to attach."
  type        = string
}

variable "ip_address" {
  description = "Address reserved by the network module."
  type        = string
}

variable "mac_address" {
  description = "MAC matching the DHCP reservation."
  type        = string
}

variable "ssh_user" {
  description = "Non-root administration user."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the administration user."
  type        = string
  sensitive   = true
}

