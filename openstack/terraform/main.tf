resource "openstack_compute_keypair_v2" "k3s" {
  name       = "k3s"
  public_key = file("${var.ssh_key_file}.pub")
}

resource "openstack_networking_network_v2" "k3s" {
  name           = "k3s"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "k3s" {
  name            = "k3s"
  network_id      = openstack_networking_network_v2.k3s.id
  cidr            = "10.13.37.0/24"
  ip_version      = 4
  dns_nameservers = ["DNS1", "DNS2"] # CHANGEME
}

data "openstack_networking_network_v2" "k3s" {
  name = "public"
}

resource "openstack_networking_router_v2" "k3s" {
  name                = "k3s"
  admin_state_up      = "true"
  external_network_id = data.openstack_networking_network_v2.k3s.id
}

resource "openstack_networking_router_interface_v2" "k3s" {
  router_id = openstack_networking_router_v2.k3s.id
  subnet_id = openstack_networking_subnet_v2.k3s.id
}

resource "openstack_networking_secgroup_v2" "k3s" {
  name        = "k3s"
  description = "Security group for the k3s instances"
}

resource "openstack_networking_secgroup_rule_v2" "k3s_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s.id
}

resource "openstack_networking_secgroup_rule_v2" "k3s_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s.id
}

resource "openstack_compute_instance_v2" "k3s" {
  for_each        = var.instance_name
  name            = each.key
  image_name      = "Ubuntu 24.04"
  flavor_name     = "SCS-4V-8-50"
  key_pair        = openstack_compute_keypair_v2.k3s.name
  security_groups = ["${openstack_networking_secgroup_v2.k3s.name}"]
  network {
    uuid = openstack_networking_network_v2.k3s.id
  }
}

resource "openstack_networking_floatingip_v2" "k3s" {
  for_each = var.instance_name
  pool     = "public"
}
