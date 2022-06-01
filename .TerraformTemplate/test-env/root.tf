module "public_vcn" {
  source             = "./vcn"
  tenancy_ocid       = var.tenancy_ocid
  compartment_ocid   = var.compartment_ocid
  vcn_type           = "public"
  vcn_cidr           = var.public_vcn_cidr
  peer_vcn_cidr      = var.private_vcn_cidr
  is_private_network = false
}

module "private_vcn" {
  source             = "./vcn"
  tenancy_ocid       = var.tenancy_ocid
  compartment_ocid   = var.compartment_ocid
  vcn_type           = "private"
  vcn_cidr           = var.private_vcn_cidr
  peer_vcn_cidr      = var.public_vcn_cidr
  is_private_network = true
  peer_id            = module.public_vcn.local_peering_gateway
}

module "compute" {
  source               = "./compute"
  tenancy_ocid         = var.tenancy_ocid
  compartment_ocid     = var.compartment_ocid
  public_subnet_id     = module.public_vcn.subnet_id
  private_subnet_id    = module.private_vcn.subnet_id
  load_ip              = "10.0.10.10"
  db_ip                = ["10.0.10.100", "10.0.10.110"]
  bastion_shape        = var.bastion_shape
  load_shape           = var.load_shape
  db_shape             = var.db_shape
  ad                   = data.oci_identity_availability_domains.ad
  source_id            = var.image_id[var.region]
  authorized_keys_path = var.authorized_keys_path
}

module "volumes" {
  count            = 2
  source           = "./volumes"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  index            = count.index
  ad_name          = data.oci_identity_availability_domains.ad.availability_domains[count.index].name
  dbserver         = [module.compute.DBServ0_id, module.compute.DBServ1_id]
  num_volumes      = var.num_volumes
  size_volumes     = var.size_volumes
}

module "public_ip" {
  source           = "./public_ip"
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  public_subnet_id = module.public_vcn.subnet_id
  ad               = data.oci_identity_availability_domains.ad
  instance_id      = module.compute.bastion_id
}

output "bastion_public_ip" {
  value = module.public_ip.bastion_public_ip
}
output "load_private_ip" {
  value = module.compute.load_ip
}
output "db0_private_ip" {
  value = module.compute.db0_ip
}
output "db1_private_ip" {
  value = module.compute.db1_ip
}
