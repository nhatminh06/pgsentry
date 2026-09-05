output "node_addresses" {
  description = "Development node addresses."
  value       = { for name, vm in module.vm : name => vm.ip_address }
}

output "ssh_targets" {
  description = "SSH targets for all development nodes."
  value       = { for name, vm in module.vm : name => vm.ssh_target }
}

