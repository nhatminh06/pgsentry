output "name" {
  description = "VM name."
  value       = libvirt_domain.this.name
}

output "role" {
  description = "VM role."
  value       = var.role
}

output "ip_address" {
  description = "Reserved IPv4 address."
  value       = var.ip_address
}

output "ssh_target" {
  description = "SSH destination for later automation."
  value       = "${var.ssh_user}@${var.ip_address}"
}
