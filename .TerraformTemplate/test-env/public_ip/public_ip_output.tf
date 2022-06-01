output "bastion_private_ip_id" {
  value = lookup(data.oci_core_private_ips.bastion_private_ips.private_ips[0], "id")
}

output "bastion_public_ip" {
  value = oci_core_public_ip.bastion_public_ip.ip_address
}
