output "name" {
  description = "Created libvirt network name."
  value       = libvirt_network.this.name
}

output "cidr" {
  description = "Created network CIDR."
  value       = var.cidr
}

