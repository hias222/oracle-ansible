output "vcnid" {
  value = oci_core_virtual_network.base_vcn.id
}

output "default_dhcp_id" {
  value = oci_core_virtual_network.base_vcn.default_dhcp_options_id
}

output "local_peering_gateway" {
  value = oci_core_local_peering_gateway.local_peering_gateway.id
}

output "subnet_id" {
  value = oci_core_subnet.subnet.id
}
