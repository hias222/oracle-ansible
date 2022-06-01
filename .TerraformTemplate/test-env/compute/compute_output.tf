output "bastion_id" {
  value = oci_core_instance.Bastion.id
}

output "load_id" {
  value = oci_core_instance.LoadTest.id
}

output "DBServ0_id" {
  value = oci_core_instance.DBServ0.id
}

output "DBServ1_id" {
  value = oci_core_instance.DBServ1.id
}

data "oci_core_vnic_attachments" "vnic_list" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.Bastion.id
}

data "oci_core_vnic" "bastion_primary_vnic" {
  vnic_id = lookup(data.oci_core_vnic_attachments.vnic_list.vnic_attachments[0], "vnic_id")
}

data "oci_core_private_ips" "bastion_private_ips" {
  vnic_id = data.oci_core_vnic.bastion_primary_vnic.id
}

output "bastion_ip" {
  value = lookup(data.oci_core_private_ips.bastion_private_ips.private_ips[0], "ip_address")
}

data "oci_core_vnic_attachments" "vnic_list_load" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.LoadTest.id
}

data "oci_core_vnic" "load_primary_vnic" {
  vnic_id = lookup(data.oci_core_vnic_attachments.vnic_list_load.vnic_attachments[0], "vnic_id")
}

data "oci_core_private_ips" "load_private_ips" {
  vnic_id = data.oci_core_vnic.load_primary_vnic.id
}

output "load_ip" {
  value = lookup(data.oci_core_private_ips.load_private_ips.private_ips[0], "ip_address")
}

data "oci_core_vnic_attachments" "vnic_list_db0" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.DBServ0.id
}

data "oci_core_vnic" "db0_primary_vnic" {
  vnic_id = lookup(data.oci_core_vnic_attachments.vnic_list_db0.vnic_attachments[0], "vnic_id")
}

data "oci_core_private_ips" "db0_private_ips" {
  vnic_id = data.oci_core_vnic.db0_primary_vnic.id
}

output "db0_ip" {
  value = lookup(data.oci_core_private_ips.db0_private_ips.private_ips[0], "ip_address")
}

data "oci_core_vnic_attachments" "vnic_list_db1" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.DBServ1.id
}

data "oci_core_vnic" "db1_primary_vnic" {
  vnic_id = lookup(data.oci_core_vnic_attachments.vnic_list_db1.vnic_attachments[0], "vnic_id")
}

data "oci_core_private_ips" "db1_private_ips" {
  vnic_id = data.oci_core_vnic.db1_primary_vnic.id
}

output "db1_ip" {
  value = lookup(data.oci_core_private_ips.db1_private_ips.private_ips[0], "ip_address")
}
