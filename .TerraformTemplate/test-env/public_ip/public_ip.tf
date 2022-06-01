# Assign a reserved public IP to the bastion host
data "oci_core_vnic_attachments" "vnic_list" {
  compartment_id      = var.compartment_ocid
  availability_domain = lookup(var.ad.availability_domains[0], "name")
  instance_id         = var.instance_id
}

data "oci_core_vnic" "bastion_primary_vnic" {
  vnic_id = lookup(data.oci_core_vnic_attachments.vnic_list.vnic_attachments[0], "vnic_id")
}

data "oci_core_private_ips" "bastion_private_ips" {
  vnic_id = data.oci_core_vnic.bastion_primary_vnic.id
}

#terraform import oci_core_public_ip.bastion_public_ip "ocid1.publicip.oc1.eu-frankfurt-1.aaaaaaaaalvkmhau3r25t3zezw7poulsqgrjv64ra353wme7ixz7e2frarvq"
resource "oci_core_public_ip" "bastion_public_ip" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  display_name   = "Bastion"
  private_ip_id  = lookup(data.oci_core_private_ips.bastion_private_ips.private_ips[0], "id")
  lifecycle {
    prevent_destroy = "false"
  }
}
