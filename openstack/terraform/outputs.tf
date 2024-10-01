output "address" {
  value = {
    for k, fip in openstack_networking_floatingip_v2.k3s : k => fip.address
  }
}
