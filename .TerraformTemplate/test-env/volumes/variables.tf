variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "index" {}
variable "ad_name" {}
variable "dbserver" {}
variable "num_volumes" {}
variable "size_volumes" {}

variable "backups_found" {
  type    = bool
  default = false
}

variable "new_volume_count" {
  type    = number
  default = 0
}

variable "restore_volume_count" {
  type    = number
  default = 0
}
