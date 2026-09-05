output "postgres_addresses" {
  description = "Canonical PostgreSQL-role node addresses."
  value       = { for name, vm in module.vm : name => vm.ip_address if vm.role == "postgres" }
}

output "etcd_addresses" {
  description = "Canonical etcd-role node addresses."
  value       = { for name, vm in module.vm : name => vm.ip_address if vm.role == "etcd" }
}

output "control_address" {
  description = "Dedicated control-host address."
  value       = module.vm["control-01"].ip_address
}

output "ssh_targets" {
  description = "SSH targets for all canonical nodes."
  value       = { for name, vm in module.vm : name => vm.ssh_target }
}

