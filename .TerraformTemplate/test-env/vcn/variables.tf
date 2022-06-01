variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "vcn_type" {}
variable "vcn_cidr" {}
variable "peer_vcn_cidr" {}
variable "peer_id" {
  default = null
}
variable "is_private_network" {
  type = bool
}
