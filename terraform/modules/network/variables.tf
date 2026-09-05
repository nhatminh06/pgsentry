variable "name" {
  description = "Deterministic libvirt network name."
  type        = string
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "Network name must not be empty."
  }
}

variable "cidr" {
  description = "IPv4 CIDR used by the project network."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 1))
    error_message = "Network CIDR must be valid."
  }
}

variable "hosts" {
  description = "Static DHCP reservations keyed by VM name."
  type = map(object({
    ip_address  = string
    mac_address = string
  }))
}

