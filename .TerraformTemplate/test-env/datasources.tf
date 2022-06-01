data "oci_core_boot_volume_backups" "bastion_boot_backup" {
  compartment_id = var.compartment_ocid
  state          = "AVAILABLE"
  display_name   = "Bastion (Boot Volume)"
}

data "oci_identity_availability_domains" "ad" {
  # root compartment has the OCID of the tenancy
  compartment_id = var.tenancy_ocid
}

data "template_file" "ad_names" {
  count = length(data.oci_identity_availability_domains.ad.availability_domains)
  #template = lookup(data.oci_identity_availability_domains.ad.availability_domains[count.index], "name")
  template = data.oci_identity_availability_domains.ad.availability_domains[count.index].name
}