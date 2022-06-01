variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "private_key_password" {}
variable "home_region" {}
variable "region" {}
variable "public_vcn_cidr" {}
variable "private_vcn_cidr" {}
variable "bastion_shape" {}
variable "load_shape" {}
variable "db_shape" {}
variable "num_volumes" {}
variable "size_volumes" {}
variable "authorized_keys_path" {}

# Default Image for compute
variable "image_id" {
  type = map(string)
  default = {
    // See https://docs.cloud.oracle.com/iaas/images/
    // Oracle-provided image "Oracle-Linux-7.8-2020.07.28-0"
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaahxue6crkdeevk75bzw63cmhh3c4uyqddcwov7mwlv7na4lkz7zla"
  }
}
