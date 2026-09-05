resource "libvirt_network" "this" {
  name      = var.name
  autostart = true
  forward   = { mode = "nat" }

  ips = [{
    address = cidrhost(var.cidr, 1)
    prefix  = tonumber(split("/", var.cidr)[1])
    dhcp = {
      hosts = [for name, host in var.hosts : {
        name = name
        ip   = host.ip_address
        mac  = host.mac_address
      }]
    }
  }]
}

